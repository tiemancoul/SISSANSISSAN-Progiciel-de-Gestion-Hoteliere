-- Factures, paiements et caisse.
-- Règles : montants NUMERIC ; une facture validée est figée (lignes, taxes, total,
-- numéro) ; un paiement porte sa devise et le taux utilisé ; une clé d'idempotence
-- empêche les doubles paiements ; un remboursement est une opération distincte.
-- Arrondi : au nombre de décimales de la devise de la facture, au demi supérieur (round()).

create type public.invoice_status as enum ('brouillon', 'validee', 'annulee');
create type public.payment_method as enum ('especes', 'carte', 'mobile_money', 'virement');

-- Taux d'une devise vers la devise principale à un instant donné (1 si principale).
create function public.rate_to_base(p_hotel uuid, p_code char(3), p_at timestamptz default now())
returns numeric language sql stable set search_path = '' as $$
  select case
    when exists (select 1 from public.currencies where hotel_id = p_hotel and code = p_code and is_base) then 1::numeric
    else (select rate from public.exchange_rates
          where hotel_id = p_hotel and code = p_code and valid_from <= p_at
          order by valid_from desc limit 1)
  end
$$;

create function public.base_currency(p_hotel uuid) returns char(3)
language sql stable set search_path = '' as $$
  select code from public.currencies where hotel_id = p_hotel and is_base
$$;

-- Factures ---------------------------------------------------------------------

create table public.invoice_sequences (
  hotel_id uuid not null references public.hotels on delete cascade,
  year int not null,
  last_number int not null default 0,
  primary key (hotel_id, year)
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  number text unique, -- attribué à la validation, séquentiel par année
  guest_id uuid references public.guests,
  reservation_id uuid references public.reservations,
  customer_name text, -- client de passage (restaurant, bar, salle)
  status public.invoice_status not null default 'brouillon',
  currency char(3) not null,
  subtotal numeric(14,2),
  tax_total numeric(14,2),
  total numeric(14,2),
  issued_at timestamptz,
  cancelled_reason text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  foreign key (hotel_id, currency) references public.currencies,
  check (guest_id is not null or customer_name is not null),
  check (status = 'brouillon' or (number is not null and total is not null)),
  check (status <> 'annulee' or cancelled_reason is not null)
);
create index invoices_hotel on public.invoices (hotel_id, created_at desc);

create table public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices on delete cascade,
  category text not null default 'hebergement'
    check (category in ('hebergement', 'restauration', 'prestations')),
  description text not null,
  quantity numeric(10,2) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  amount numeric(14,2) generated always as (round(quantity * unit_price, 2)) stored
);
create index invoice_items_invoice on public.invoice_items (invoice_id);

-- Taxes figées à la validation.
create table public.invoice_taxes (
  invoice_id uuid not null references public.invoices on delete cascade,
  name text not null,
  kind text not null,
  rate numeric(14,4) not null,
  base numeric(14,2) not null,
  amount numeric(14,2) not null
);

-- Une facture non brouillon ne change plus, sauf pour être annulée.
create function public.invoice_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_table_name = 'invoices' then
    if old.status = 'annulee' then
      raise exception 'Facture annulée : modification impossible' using errcode = '23514';
    end if;
    if old.status = 'validee' and not (
      new.status = 'annulee' and new.cancelled_reason is not null
      and (to_jsonb(new) - 'status' - 'cancelled_reason') = (to_jsonb(old) - 'status' - 'cancelled_reason')
    ) then
      raise exception 'Facture validée : seule l''annulation est possible' using errcode = '23514';
    end if;
    return new;
  end if;
  -- invoice_items
  if exists (select 1 from public.invoices where id = coalesce(new.invoice_id, old.invoice_id) and status <> 'brouillon') then
    raise exception 'Facture validée : lignes non modifiables' using errcode = '23514';
  end if;
  return coalesce(new, old);
end $$;

create trigger invoice_guard before update or delete on public.invoices
  for each row execute function public.invoice_guard();
create trigger invoice_guard before insert or update or delete on public.invoice_items
  for each row execute function public.invoice_guard();

-- Brouillon de facture pour une réservation : une ligne d'hébergement au tarif figé.
create function public.invoice_from_reservation(reservation uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  r public.reservations;
  inv uuid;
  room text;
begin
  if not public.has_role('super_admin','admin','gerant','reception','caissier') then
    raise exception 'Action non autorisée' using errcode = '42501';
  end if;
  select * into r from public.reservations where id = reservation and hotel_id = public.my_hotel();
  if not found then raise exception 'Réservation introuvable' using errcode = 'P0002'; end if;
  select number into room from public.rooms where id = r.room_id;
  insert into public.invoices (hotel_id, guest_id, reservation_id, currency)
    values (r.hotel_id, r.guest_id, r.id, r.currency) returning id into inv;
  insert into public.invoice_items (invoice_id, category, description, quantity, unit_price)
    values (inv, 'hebergement',
            format('Chambre %s, du %s au %s', room, r.check_in, r.check_out),
            r.check_out - r.check_in, r.nightly_rate);
  return inv;
end $$;

-- Valide une facture : calcule et fige taxes et totaux, attribue le numéro.
create function public.finalize_invoice(invoice uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  inv public.invoices;
  t record;
  dec int;
  base numeric;
  sub numeric;
  tax_sum numeric := 0;
  n int;
  yr int := extract(year from now())::int;
begin
  if not public.has_role('super_admin','admin','gerant','reception','caissier','comptable') then
    raise exception 'Action non autorisée' using errcode = '42501';
  end if;
  select * into inv from public.invoices where id = invoice and hotel_id = public.my_hotel() for update;
  if not found then raise exception 'Facture introuvable' using errcode = 'P0002'; end if;
  if inv.status <> 'brouillon' then raise exception 'Facture déjà validée' using errcode = '23514'; end if;
  select coalesce(sum(amount), 0) into sub from public.invoice_items where invoice_id = inv.id;
  if not exists (select 1 from public.invoice_items where invoice_id = inv.id) then
    raise exception 'Facture sans ligne' using errcode = '23514';
  end if;
  select decimals into dec from public.currencies where hotel_id = inv.hotel_id and code = inv.currency;

  for t in select * from public.taxes where hotel_id = inv.hotel_id and active loop
    if t.kind = 'pourcentage' then
      select coalesce(sum(amount), 0) into base from public.invoice_items
        where invoice_id = inv.id and (t.applies_to = 'tout' or category = t.applies_to);
      continue when base = 0;
      insert into public.invoice_taxes values (inv.id, t.name, t.kind, t.rate, base, round(base * t.rate / 100, dec));
      tax_sum := tax_sum + round(base * t.rate / 100, dec);
    else -- montant_par_nuit, sur les nuits d'hébergement
      select coalesce(sum(quantity), 0) into base from public.invoice_items
        where invoice_id = inv.id and category = 'hebergement';
      continue when base = 0;
      if t.currency is distinct from inv.currency then
        raise exception 'La taxe % est en %, la facture en %', t.name, t.currency, inv.currency using errcode = '23514';
      end if;
      insert into public.invoice_taxes values (inv.id, t.name, t.kind, t.rate, base, round(base * t.rate, dec));
      tax_sum := tax_sum + round(base * t.rate, dec);
    end if;
  end loop;

  insert into public.invoice_sequences (hotel_id, year) values (inv.hotel_id, yr)
    on conflict do nothing;
  update public.invoice_sequences set last_number = last_number + 1
    where hotel_id = inv.hotel_id and year = yr returning last_number into n;

  update public.invoices set
    status = 'validee',
    number = format('F%s-%s', yr, lpad(n::text, 5, '0')),
    subtotal = round(sub, dec),
    tax_total = tax_sum,
    total = round(sub, dec) + tax_sum,
    issued_at = now()
  where id = inv.id;
  return format('F%s-%s', yr, lpad(n::text, 5, '0'));
end $$;

-- Caisse -------------------------------------------------------------------------

create table public.cash_sessions (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  opened_by uuid not null default auth.uid(),
  opened_at timestamptz not null default now(),
  opening_float numeric(14,2) not null check (opening_float >= 0),
  currency char(3) not null,
  closed_at timestamptz,
  expected_amount numeric(14,2),
  counted_amount numeric(14,2),
  difference numeric(14,2),
  check ((closed_at is null) = (counted_amount is null))
);
-- Une seule session ouverte par utilisateur.
create unique index cash_sessions_one_open on public.cash_sessions (opened_by) where closed_at is null;

create function public.open_cash_session(opening_float numeric) returns uuid
language plpgsql security definer set search_path = '' as $$
declare id uuid;
begin
  if not public.has_role('super_admin','admin','gerant','reception','caissier','restaurant_bar') then
    raise exception 'Action non autorisée' using errcode = '42501';
  end if;
  insert into public.cash_sessions (hotel_id, opening_float, currency)
    values (public.my_hotel(), opening_float, public.base_currency(public.my_hotel()))
    returning cash_sessions.id into id;
  return id;
end $$;

-- Paiements ----------------------------------------------------------------------

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  invoice_id uuid not null references public.invoices,
  kind text not null default 'paiement' check (kind in ('paiement', 'remboursement')),
  method public.payment_method not null,
  amount numeric(14,2) not null check (amount > 0), -- dans la devise du paiement
  currency char(3) not null,
  rate numeric(18,8) not null,                    -- vers la devise de la facture, figé
  amount_invoice numeric(14,2) not null,          -- contre-valeur en devise de facture
  balance_after numeric(14,2) not null,           -- solde dû juste après, pour le reçu
  cash_received numeric(14,2),
  change_given numeric(14,2),
  reference text,
  cash_session_id uuid references public.cash_sessions,
  idempotency_key uuid not null unique,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  foreign key (hotel_id, currency) references public.currencies,
  check (method <> 'especes' or cash_session_id is not null)
);
create index payments_invoice on public.payments (invoice_id);
create index payments_session on public.payments (cash_session_id);

-- Solde restant dû en devise de facture.
create view public.invoice_balances with (security_invoker = true) as
  select i.id as invoice_id, i.total,
         coalesce(sum(case p.kind when 'paiement' then p.amount_invoice else -p.amount_invoice end), 0) as paid,
         i.total - coalesce(sum(case p.kind when 'paiement' then p.amount_invoice else -p.amount_invoice end), 0) as balance
  from public.invoices i left join public.payments p on p.invoice_id = i.id
  group by i.id;

-- Encaisse ou rembourse. Rejouer la même clé renvoie le paiement déjà enregistré.
create function public.record_payment(
  invoice uuid, amount numeric, currency char(3), method public.payment_method,
  idempotency_key uuid, cash_received numeric default null, reference text default null,
  kind text default 'paiement'
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  inv public.invoices;
  existing uuid;
  r numeric;
  amt_inv numeric;
  dec int;
  bal numeric;
  session uuid;
  change numeric;
begin
  select id into existing from public.payments p where p.idempotency_key = record_payment.idempotency_key;
  if found then return existing; end if;

  if kind = 'remboursement' and not public.has_role('super_admin','admin','gerant') then
    raise exception 'Remboursement réservé à la direction' using errcode = '42501';
  end if;
  if not public.has_role('super_admin','admin','gerant','reception','caissier','restaurant_bar') then
    raise exception 'Action non autorisée' using errcode = '42501';
  end if;
  select * into inv from public.invoices i where i.id = invoice and i.hotel_id = public.my_hotel() for update;
  if not found then raise exception 'Facture introuvable' using errcode = 'P0002'; end if;
  if inv.status <> 'validee' then raise exception 'Seule une facture validée peut être encaissée' using errcode = '23514'; end if;

  -- taux devise du paiement -> devise de facture, via la devise principale
  r := public.rate_to_base(inv.hotel_id, currency) / public.rate_to_base(inv.hotel_id, inv.currency);
  if r is null then raise exception 'Aucun taux de change pour %', currency using errcode = '23514'; end if;
  select decimals into dec from public.currencies c where c.hotel_id = inv.hotel_id and c.code = inv.currency;
  amt_inv := round(amount * r, dec);
  select b.balance into bal from public.invoice_balances b where b.invoice_id = inv.id;

  if kind = 'paiement' and amt_inv > bal then
    raise exception 'Montant supérieur au solde dû (% %)', bal, inv.currency using errcode = '23514';
  end if;
  if kind = 'remboursement' and amt_inv > inv.total - bal then
    raise exception 'Remboursement supérieur aux sommes encaissées' using errcode = '23514';
  end if;

  if method = 'especes' then
    select id into session from public.cash_sessions
      where opened_by = auth.uid() and closed_at is null;
    if not found then raise exception 'Ouvrez d''abord une session de caisse' using errcode = '23514'; end if;
    if kind = 'paiement' then
      if cash_received is null or cash_received < amount then
        raise exception 'Espèces reçues insuffisantes' using errcode = '23514';
      end if;
      change := cash_received - amount;
    end if;
  elsif cash_received is not null then
    raise exception 'Espèces reçues seulement pour un paiement en espèces' using errcode = '23514';
  end if;

  insert into public.payments (hotel_id, invoice_id, kind, method, amount, currency, rate, amount_invoice,
                               balance_after, cash_received, change_given, reference, cash_session_id, idempotency_key)
    values (inv.hotel_id, inv.id, kind, method, amount, currency, r, amt_inv,
            case kind when 'paiement' then bal - amt_inv else bal + amt_inv end,
            cash_received, change, reference, session, record_payment.idempotency_key)
    on conflict on constraint payments_idempotency_key_key do nothing
    returning id into existing;
  if existing is null then -- course avec une requête identique
    select id into existing from public.payments p where p.idempotency_key = record_payment.idempotency_key;
  end if;
  return existing;
end $$;

-- Clôture : théorique = fonds + encaissements espèces − remboursements espèces
-- (contre-valeur en devise principale).
create function public.close_cash_session(session uuid, counted numeric) returns numeric
language plpgsql security definer set search_path = '' as $$
declare
  s public.cash_sessions;
  expected numeric;
begin
  select * into s from public.cash_sessions
    where id = session and hotel_id = public.my_hotel() and closed_at is null for update;
  if not found then raise exception 'Session introuvable ou déjà clôturée' using errcode = 'P0002'; end if;
  if s.opened_by <> auth.uid() and not public.has_role('super_admin','admin','gerant') then
    raise exception 'Seul le titulaire ou la direction peut clôturer' using errcode = '42501';
  end if;
  select s.opening_float + coalesce(sum(
           (case p.kind when 'paiement' then 1 else -1 end) * round(p.amount * public.rate_to_base(s.hotel_id, p.currency, p.created_at), 2)
         ), 0)
    into expected
    from public.payments p where p.cash_session_id = s.id;
  update public.cash_sessions set
    closed_at = now(), expected_amount = expected, counted_amount = counted, difference = counted - expected
  where id = s.id;
  return counted - expected;
end $$;

revoke execute on function public.invoice_from_reservation(uuid), public.finalize_invoice(uuid),
  public.open_cash_session(numeric), public.close_cash_session(uuid, numeric),
  public.record_payment(uuid, numeric, char, public.payment_method, uuid, numeric, text, text)
  from public, anon;

-- Audit et RLS ---------------------------------------------------------------------

create trigger audit after insert or update or delete on public.invoices
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.payments
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.cash_sessions
  for each row execute function public.audit_row();

alter table public.invoice_sequences enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
alter table public.invoice_taxes enable row level security;
alter table public.payments enable row level security;
alter table public.cash_sessions enable row level security;

create policy finance_read on public.invoices for select to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin','gerant','reception','caissier','comptable','auditeur','restaurant_bar'));
-- Création de brouillons, modification de brouillons, annulation par la direction.
create policy draft_insert on public.invoices for insert to authenticated
  with check (hotel_id = public.my_hotel() and status = 'brouillon'
              and public.has_role('super_admin','admin','gerant','reception','caissier','restaurant_bar'));
create policy draft_update on public.invoices for update to authenticated
  using (hotel_id = public.my_hotel() and status = 'brouillon'
         and public.has_role('super_admin','admin','gerant','reception','caissier','restaurant_bar'))
  with check (status = 'brouillon');
create policy cancel on public.invoices for update to authenticated
  using (hotel_id = public.my_hotel() and status = 'validee' and public.has_role('super_admin','admin','gerant'))
  with check (status = 'annulee');
create policy draft_delete on public.invoices for delete to authenticated
  using (hotel_id = public.my_hotel() and status = 'brouillon'
         and public.has_role('super_admin','admin','gerant','reception','caissier','restaurant_bar'));

create policy items_read on public.invoice_items for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id));
create policy items_write on public.invoice_items for all to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and i.status = 'brouillon')
         and public.has_role('super_admin','admin','gerant','reception','caissier','restaurant_bar'))
  with check (exists (select 1 from public.invoices i where i.id = invoice_id and i.status = 'brouillon')
         and public.has_role('super_admin','admin','gerant','reception','caissier','restaurant_bar'));
create policy taxes_read on public.invoice_taxes for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id));

-- Paiements et caisse : lecture seule ; les écritures passent par les fonctions.
create policy finance_read on public.payments for select to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin','gerant','reception','caissier','comptable','auditeur','restaurant_bar'));
create policy own_or_managers on public.cash_sessions for select to authenticated
  using (hotel_id = public.my_hotel() and (opened_by = auth.uid() or public.has_role('super_admin','admin','gerant','comptable','auditeur')));

revoke all on public.invoice_sequences, public.invoices, public.invoice_items, public.invoice_taxes,
  public.payments, public.cash_sessions, public.invoice_balances from anon;
