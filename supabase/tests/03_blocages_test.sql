-- Tests des blocages (s'appuie sur 01 et 02 : chambre 101 réservée de J+3 à J+5 et J+20 à J+21).
\set ON_ERROR_STOP on
\o /dev/null
grant select, insert, update, delete on public.room_blocks to authenticated;
\i tests/helpers.sql
set role authenticated;

-- 1. Admin bloque une période libre ; pas de blocage sur une réservation confirmée
select pg_temp.as_user(2);
insert into public.room_blocks (hotel_id, room_id, start_date, end_date, reason)
select hotel_id, id, current_date + 10, current_date + 15, 'Peinture' from public.rooms where number = '101';
do $$ begin
  insert into public.room_blocks (hotel_id, room_id, start_date, end_date, reason)
  select hotel_id, id, current_date + 4, current_date + 6, 'Fuite' from public.rooms where number = '101';
  raise exception 'ÉCHEC blocage sur réservation accepté';
exception when exclusion_violation then null;
end $$;

-- 2. Réception : réservation confirmée refusée sur un blocage, en attente acceptée mais non confirmable
select pg_temp.as_user(3);
do $$ begin
  perform pg_temp.book(12, 13);
  raise exception 'ÉCHEC réservation sur blocage acceptée';
exception when exclusion_violation then null;
end $$;
select pg_temp.book(14, 16, 'en_attente');
do $$ begin
  update public.reservations set status = 'confirmee' where check_in = current_date + 14;
  raise exception 'ÉCHEC confirmation sur blocage acceptée';
exception when exclusion_violation then null;
end $$;
select pg_temp.expect_denied($$delete from public.room_blocks$$, 'réception supprime un blocage');
reset role;
\o
\echo 'Blocages : tests passés.'
