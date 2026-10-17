-- Socle : hôtel, paramètres, devises, taxes, profils et rôles, chambres, salles, audit.
-- Toutes les tables privées ont RLS ; aucune n'est lisible par le rôle anon.

create extension if not exists pgcrypto;

create type public.app_role as enum (
  'super_admin', 'admin', 'gerant', 'reception', 'caissier', 'comptable',
  'restaurant_bar', 'magasinier', 'entretien', 'maintenance', 'auditeur'
);

create type public.room_status as enum (
  'disponible', 'occupee', 'nettoyage', 'maintenance', 'hors_service'
);

-- Établissement --------------------------------------------------------------

create table public.hotels (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  legal_name text,
  address text,
  phone text,
  email text,
  tax_id text,
  logo_path text,
  timezone text not null default 'UTC',
  created_at timestamptz not null default now()
);

-- Règles réservées au super administrateur (décision D4).
create table public.hotel_settings (
  hotel_id uuid primary key references public.hotels on delete cascade,
  check_in_time time not null default '14:00',
  check_out_time time not null default '12:00',
  free_cancellation_hours int not null default 48 check (free_cancellation_hours >= 0),
  deposit_percent numeric(5,2) not null default 30 check (deposit_percent between 0 and 100),
  no_show_nights_charged int not null default 1 check (no_show_nights_charged >= 0),
  walk_in_allowed boolean not null default true,
  invoice_mentions text,
  updated_at timestamptz not null default now()
);

create table public.currencies (
  hotel_id uuid not null references public.hotels on delete cascade,
  code char(3) not null check (code ~ '^[A-Z]{3}$'),
  name text not null,
  decimals smallint not null default 2 check (decimals between 0 and 4),
  is_base boolean not null default false,
  active boolean not null default true,
  primary key (hotel_id, code)
);
-- Une seule devise principale par hôtel.
create unique index currencies_one_base on public.currencies (hotel_id) where is_base;

-- Historique des taux : 1 unité de `code` = `rate` unités de la devise principale.
create table public.exchange_rates (
  id bigint generated always as identity primary key,
  hotel_id uuid not null,
  code char(3) not null,
  rate numeric(18,8) not null check (rate > 0),
  valid_from timestamptz not null default now(),
  created_by uuid default auth.uid(),
  foreign key (hotel_id, code) references public.currencies on delete cascade
);
create index exchange_rates_lookup on public.exchange_rates (hotel_id, code, valid_from desc);

create table public.taxes (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  name text not null,
  kind text not null check (kind in ('pourcentage', 'montant_par_nuit')),
  rate numeric(14,4) not null check (rate >= 0),
  currency char(3),
  applies_to text not null default 'hebergement'
    check (applies_to in ('hebergement', 'restauration', 'prestations', 'tout')),
  active boolean not null default true,
  check (kind = 'pourcentage' or currency is not null)
);

-- Identité et accès ----------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  hotel_id uuid references public.hotels on delete set null,
  full_name text,
  role public.app_role, -- null = compte sans accès tant qu'un administrateur ne l'a pas attribué
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Profil créé automatiquement, sans rôle, à l'inscription.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Helpers RLS : security definer pour éviter la récursion sur profiles.
create function public.my_role() returns public.app_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid() and active
$$;

create function public.my_hotel() returns uuid
language sql stable security definer set search_path = '' as $$
  select hotel_id from public.profiles where id = auth.uid() and active and role is not null
$$;

create function public.has_role(variadic roles public.app_role[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.my_role() = any(roles), false)
$$;

-- Chambres et salles ---------------------------------------------------------

create table public.room_types (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  name text not null,
  description text,
  max_adults smallint not null default 2 check (max_adults > 0),
  max_children smallint not null default 0 check (max_children >= 0),
  base_rate numeric(14,2) not null check (base_rate >= 0),
  currency char(3) not null,
  active boolean not null default true,
  unique (hotel_id, name),
  foreign key (hotel_id, currency) references public.currencies
);

create table public.amenities (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  name text not null,
  unique (hotel_id, name)
);

create table public.room_type_amenities (
  room_type_id uuid not null references public.room_types on delete cascade,
  amenity_id uuid not null references public.amenities on delete cascade,
  primary key (room_type_id, amenity_id)
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  number text not null,
  room_type_id uuid not null references public.room_types,
  floor text,
  status public.room_status not null default 'disponible',
  notes text,
  active boolean not null default true,
  unique (hotel_id, number)
);
create index rooms_type on public.rooms (room_type_id);

create table public.conference_rooms (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  name text not null,
  capacity int not null check (capacity > 0),
  half_day_rate numeric(14,2) not null check (half_day_rate >= 0),
  full_day_rate numeric(14,2) not null check (full_day_rate >= 0),
  currency char(3) not null,
  equipment text,
  active boolean not null default true,
  unique (hotel_id, name),
  foreign key (hotel_id, currency) references public.currencies
);

-- Audit ----------------------------------------------------------------------

create table public.audit_logs (
  id bigint generated always as identity primary key,
  hotel_id uuid,
  actor uuid,
  table_name text not null,
  action text not null,
  row_pk text,
  old_data jsonb,
  new_data jsonb,
  at timestamptz not null default now()
);
create index audit_logs_hotel_at on public.audit_logs (hotel_id, at desc);

create function public.audit_row() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  rec jsonb := to_jsonb(coalesce(new, old));
begin
  insert into public.audit_logs (hotel_id, actor, table_name, action, row_pk, old_data, new_data)
  values (
    coalesce((rec ->> 'hotel_id')::uuid, case when tg_table_name = 'hotels' then (rec ->> 'id')::uuid end),
    auth.uid(), tg_table_name, tg_op,
    coalesce(rec ->> 'id', rec ->> 'code', rec ->> 'hotel_id'),
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end
  );
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['hotels','hotel_settings','currencies','exchange_rates','taxes',
    'profiles','room_types','amenities','rooms','conference_rooms'] loop
    execute format('create trigger audit after insert or update or delete on public.%I
      for each row execute function public.audit_row()', t);
  end loop;
end $$;

-- RLS ------------------------------------------------------------------------

alter table public.hotels enable row level security;
alter table public.hotel_settings enable row level security;
alter table public.currencies enable row level security;
alter table public.exchange_rates enable row level security;
alter table public.taxes enable row level security;
alter table public.profiles enable row level security;
alter table public.room_types enable row level security;
alter table public.amenities enable row level security;
alter table public.room_type_amenities enable row level security;
alter table public.rooms enable row level security;
alter table public.conference_rooms enable row level security;
alter table public.audit_logs enable row level security;

-- Lecture : tout le personnel actif de l'hôtel.
create policy staff_read on public.hotels for select to authenticated using (id = public.my_hotel());
create policy staff_read on public.hotel_settings for select to authenticated using (hotel_id = public.my_hotel());
create policy staff_read on public.currencies for select to authenticated using (hotel_id = public.my_hotel());
create policy staff_read on public.exchange_rates for select to authenticated using (hotel_id = public.my_hotel());
create policy staff_read on public.taxes for select to authenticated using (hotel_id = public.my_hotel());
create policy staff_read on public.room_types for select to authenticated using (hotel_id = public.my_hotel());
create policy staff_read on public.amenities for select to authenticated using (hotel_id = public.my_hotel());
create policy staff_read on public.room_type_amenities for select to authenticated
  using (exists (select 1 from public.room_types rt where rt.id = room_type_id and rt.hotel_id = public.my_hotel()));
create policy staff_read on public.rooms for select to authenticated using (hotel_id = public.my_hotel());
create policy staff_read on public.conference_rooms for select to authenticated using (hotel_id = public.my_hotel());

-- Identité de l'hôtel et logo : super admin, admin, gérant (D1).
create policy identity_write on public.hotels for update to authenticated
  using (id = public.my_hotel() and public.has_role('super_admin','admin','gerant'))
  with check (id = public.my_hotel());

-- Devises, taux, taxes et règles de séjour : super admin uniquement (D2, D3, D4).
create policy super_admin_write on public.hotel_settings for all to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin'))
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin'));
create policy super_admin_write on public.currencies for all to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin'))
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin'));
create policy super_admin_insert on public.exchange_rates for insert to authenticated
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin'));
create policy super_admin_write on public.taxes for all to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin'))
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin'));

-- Chambres, catégories, tarifs, équipements, salles : super admin et admin (D9).
create policy catalog_write on public.room_types for all to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin'))
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin','admin'));
create policy catalog_write on public.amenities for all to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin'))
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin','admin'));
create policy catalog_write on public.room_type_amenities for all to authenticated
  using (public.has_role('super_admin','admin') and exists (select 1 from public.room_types rt where rt.id = room_type_id and rt.hotel_id = public.my_hotel()))
  with check (public.has_role('super_admin','admin') and exists (select 1 from public.room_types rt where rt.id = room_type_id and rt.hotel_id = public.my_hotel()));
create policy catalog_write on public.rooms for all to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin'))
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin','admin'));
create policy catalog_write on public.conference_rooms for all to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin'))
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin','admin'));

-- Profils : chacun voit le sien ; super admin et admin voient ceux de l'hôtel
-- et les comptes en attente (sans hôtel). Un admin ne peut ni créer ni modifier un super admin.
create policy own_read on public.profiles for select to authenticated using (id = auth.uid());
create policy managers_read on public.profiles for select to authenticated
  using (public.has_role('super_admin','admin') and (hotel_id = public.my_hotel() or hotel_id is null));
create policy managers_update on public.profiles for update to authenticated
  using (public.has_role('super_admin','admin') and (hotel_id = public.my_hotel() or hotel_id is null)
         and (role is distinct from 'super_admin' or public.has_role('super_admin')))
  with check (hotel_id = public.my_hotel() and id <> auth.uid()
         and (role is distinct from 'super_admin' or public.has_role('super_admin')));

-- Audit : lecture seule pour super admin, admin, gérant et auditeur ; aucune écriture directe.
create policy audit_read on public.audit_logs for select to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin','gerant','auditeur'));

-- Le client public (anon) n'a aucun droit sur ces tables.
revoke all on all tables in schema public from anon;
