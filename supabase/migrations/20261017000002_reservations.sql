-- Clients et réservations. La double réservation d'une chambre est rendue
-- impossible par une contrainte d'exclusion, donc même en cas de requêtes concurrentes.

create extension if not exists btree_gist;

create type public.reservation_status as enum (
  'en_attente', 'confirmee', 'arrivee', 'partie', 'annulee', 'no_show'
);

create table public.guests (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  last_name text not null check (length(trim(last_name)) > 0),
  first_name text,
  phone text,
  email text,
  nationality text,
  id_document text, -- type et numéro de pièce d'identité
  notes text,
  created_at timestamptz not null default now()
);
create index guests_search on public.guests (hotel_id, lower(last_name));

create sequence public.reservation_number_seq;
grant usage on sequence public.reservation_number_seq to authenticated;

create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  reference text not null unique
    default 'R' || to_char(now(), 'YYMM') || '-' || lpad(nextval('public.reservation_number_seq')::text, 5, '0'),
  guest_id uuid not null references public.guests,
  room_id uuid not null references public.rooms,
  check_in date not null,
  check_out date not null, -- exclusive : nuits = check_out - check_in
  adults smallint not null default 1 check (adults > 0),
  children smallint not null default 0 check (children >= 0),
  status public.reservation_status not null default 'confirmee',
  nightly_rate numeric(14,2) check (nightly_rate >= 0), -- figé à la création
  currency char(3),
  source text not null default 'interne' check (source in ('interne', 'public')),
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (check_out > check_in),
  exclude using gist (room_id with =, daterange(check_in, check_out) with &&)
    where (status in ('confirmee', 'arrivee'))
);
create index reservations_dates on public.reservations (hotel_id, check_in, check_out);

-- Fige le tarif de la catégorie et vérifie la capacité et l'état de la chambre.
create function public.reservation_defaults() returns trigger
language plpgsql set search_path = '' as $$
declare
  rt record;
begin
  select t.base_rate, t.currency, t.max_adults, t.max_children, r.status as room_status, r.active
    into rt
    from public.rooms r join public.room_types t on t.id = r.room_type_id
    where r.id = new.room_id and r.hotel_id = new.hotel_id;
  if not found then raise exception 'Chambre inconnue pour cet hôtel' using errcode = '23503'; end if;
  if tg_op = 'INSERT' or new.room_id is distinct from old.room_id then
    if not rt.active or rt.room_status = 'hors_service' then
      raise exception 'Chambre hors service' using errcode = '23514';
    end if;
  end if;
  if new.adults > rt.max_adults or new.children > rt.max_children then
    raise exception 'Capacité de la chambre dépassée' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' then
    new.nightly_rate := coalesce(new.nightly_rate, rt.base_rate);
    new.currency := coalesce(new.currency, rt.currency);
  end if;
  return new;
end $$;

create trigger reservation_defaults before insert or update of room_id, adults, children
  on public.reservations for each row execute function public.reservation_defaults();

-- Arrivée et départ : changent aussi l'état de la chambre, que la réception
-- ne peut pas modifier directement.
create function public.check_in(reservation uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.reservations;
begin
  if not public.has_role('super_admin','admin','gerant','reception') then
    raise exception 'Action non autorisée' using errcode = '42501';
  end if;
  select * into r from public.reservations where id = reservation and hotel_id = public.my_hotel() for update;
  if not found then raise exception 'Réservation introuvable' using errcode = 'P0002'; end if;
  if r.status <> 'confirmee' then raise exception 'Seule une réservation confirmée peut être enregistrée à l''arrivée' using errcode = '23514'; end if;
  if r.check_in > current_date then raise exception 'Arrivée prévue le %', r.check_in using errcode = '23514'; end if;
  update public.reservations set status = 'arrivee' where id = r.id;
  update public.rooms set status = 'occupee' where id = r.room_id;
end $$;

create function public.check_out(reservation uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.reservations;
begin
  if not public.has_role('super_admin','admin','gerant','reception') then
    raise exception 'Action non autorisée' using errcode = '42501';
  end if;
  select * into r from public.reservations where id = reservation and hotel_id = public.my_hotel() for update;
  if not found then raise exception 'Réservation introuvable' using errcode = 'P0002'; end if;
  if r.status <> 'arrivee' then raise exception 'Le client n''est pas enregistré comme arrivé' using errcode = '23514'; end if;
  update public.reservations set status = 'partie' where id = r.id;
  update public.rooms set status = 'nettoyage' where id = r.room_id;
end $$;

revoke execute on function public.check_in(uuid), public.check_out(uuid) from public, anon;

create trigger audit after insert or update or delete on public.guests
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.reservations
  for each row execute function public.audit_row();

alter table public.guests enable row level security;
alter table public.reservations enable row level security;

-- Données clients : personnel d'accueil et direction uniquement.
create policy front_desk on public.guests for all to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin','gerant','reception'))
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin','admin','gerant','reception'));

create policy staff_read on public.reservations for select to authenticated
  using (hotel_id = public.my_hotel());
create policy front_desk_insert on public.reservations for insert to authenticated
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin','admin','gerant','reception')
              and status in ('en_attente', 'confirmee'));
-- Les passages à "arrivée" et "partie" se font uniquement via check_in / check_out.
create policy front_desk_update on public.reservations for update to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin','gerant','reception')
         and status in ('en_attente', 'confirmee'))
  with check (hotel_id = public.my_hotel() and status in ('en_attente', 'confirmee', 'annulee', 'no_show'));

revoke all on public.guests, public.reservations from anon;
