-- Blocages de chambres par période (travaux, maintenance, usage interne).
-- Un blocage et une réservation confirmée ne peuvent pas se chevaucher : les deux
-- triggers verrouillent la ligne de la chambre pour sérialiser les écritures concurrentes.

create table public.room_blocks (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels on delete cascade,
  room_id uuid not null references public.rooms on delete cascade,
  start_date date not null,
  end_date date not null, -- exclusive, comme check_out
  reason text not null check (length(trim(reason)) > 0),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (end_date > start_date),
  exclude using gist (room_id with =, daterange(start_date, end_date) with &&)
);
create index room_blocks_dates on public.room_blocks (hotel_id, start_date, end_date);

create function public.block_vs_reservations() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.rooms where id = new.room_id for update;
  if exists (
    select 1 from public.reservations r
    where r.room_id = new.room_id and r.status in ('confirmee', 'arrivee')
      and daterange(r.check_in, r.check_out) && daterange(new.start_date, new.end_date)
  ) then
    raise exception 'Des réservations confirmées existent sur cette période' using errcode = '23P01';
  end if;
  return new;
end $$;

create trigger block_vs_reservations before insert or update on public.room_blocks
  for each row execute function public.block_vs_reservations();

create function public.reservation_vs_blocks() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status not in ('confirmee', 'arrivee') then return new; end if;
  perform 1 from public.rooms where id = new.room_id for update;
  if exists (
    select 1 from public.room_blocks b
    where b.room_id = new.room_id
      and daterange(b.start_date, b.end_date) && daterange(new.check_in, new.check_out)
  ) then
    raise exception 'La chambre est bloquée sur cette période' using errcode = '23P01';
  end if;
  return new;
end $$;

create trigger reservation_vs_blocks before insert or update of status, room_id, check_in, check_out
  on public.reservations for each row execute function public.reservation_vs_blocks();

create trigger audit after insert or update or delete on public.room_blocks
  for each row execute function public.audit_row();

alter table public.room_blocks enable row level security;

create policy staff_read on public.room_blocks for select to authenticated
  using (hotel_id = public.my_hotel());
create policy block_write on public.room_blocks for all to authenticated
  using (hotel_id = public.my_hotel() and public.has_role('super_admin','admin','gerant','maintenance'))
  with check (hotel_id = public.my_hotel() and public.has_role('super_admin','admin','gerant','maintenance'));

revoke all on public.room_blocks from anon;
