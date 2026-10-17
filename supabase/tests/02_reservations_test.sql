-- Tests clients et réservations (s'appuie sur les données de 01_socle_test.sql).
\set ON_ERROR_STOP on
\o /dev/null
grant select, insert, update, delete on public.guests, public.reservations to authenticated;
grant execute on function public.check_in(uuid), public.check_out(uuid) to authenticated;
\i tests/helpers.sql

-- Préparation par l'admin : un client et une 2e chambre hors service
set role authenticated;
select pg_temp.as_user(2);
insert into public.guests (id, hotel_id, last_name) values
  ('30000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000000', 'Traoré');
insert into public.rooms (id, hotel_id, number, room_type_id, status) values
  ('40000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000000', '102',
   '20000000-0000-0000-0000-000000000000', 'hors_service');

-- 1. Réception : réservation confirmée, tarif figé depuis la catégorie
select pg_temp.as_user(3);
insert into public.reservations (id, hotel_id, guest_id, room_id, check_in, check_out)
select '50000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000000',
       '30000000-0000-0000-0000-000000000000', id, current_date, current_date + 3
from public.rooms where number = '101';
do $$ begin
  if (select nightly_rate::text || currency from public.reservations) <> '25000.00XOF'
    then raise exception 'ÉCHEC tarif non figé'; end if;
end $$;

-- 2. Double réservation refusée, chevauchement partiel compris ; dates contiguës acceptées
do $$ begin
  perform pg_temp.book(2, 5);
  raise exception 'ÉCHEC double réservation acceptée';
exception when exclusion_violation then null;
end $$;
select pg_temp.book(3, 5);
select pg_temp.book(1, 2, 'en_attente'); -- une demande en attente ne bloque pas
do $$ begin
  update public.reservations set status = 'confirmee' where status = 'en_attente';
  raise exception 'ÉCHEC confirmation en conflit acceptée';
exception when exclusion_violation then null;
end $$;

-- 3. Chambre hors service et capacité
do $$ begin
  insert into public.reservations (hotel_id, guest_id, room_id, check_in, check_out)
  values ('10000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000000',
          '40000000-0000-0000-0000-000000000000', current_date + 10, current_date + 11);
  raise exception 'ÉCHEC chambre hors service réservée';
exception when check_violation then null;
end $$;
do $$ begin
  perform pg_temp.book(20, 21); -- ok
  update public.reservations set adults = 5 where check_in = current_date + 20;
  raise exception 'ÉCHEC capacité dépassée acceptée';
exception when check_violation then null;
end $$;

-- 4. Statuts protégés : pas de passage direct à "arrivée", pas de suppression
select pg_temp.expect_denied($$update public.reservations set status = 'arrivee' where id = '50000000-0000-0000-0000-000000000000'$$, 'arrivée sans check-in');
select pg_temp.expect_denied($$delete from public.reservations$$, 'suppression de réservation');

-- 5. Arrivée puis départ : statuts et état de la chambre
select public.check_in('50000000-0000-0000-0000-000000000000');
do $$ begin
  if (select status from public.rooms where number = '101') <> 'occupee' then raise exception 'ÉCHEC chambre non occupée'; end if;
end $$;
select pg_temp.expect_denied($$update public.reservations set status = 'annulee' where id = '50000000-0000-0000-0000-000000000000'$$, 'annulation d''un séjour en cours');
select public.check_out('50000000-0000-0000-0000-000000000000');
do $$ begin
  if (select status from public.rooms where number = '101') <> 'nettoyage' then raise exception 'ÉCHEC chambre non à nettoyer'; end if;
  if (select status from public.reservations where id = '50000000-0000-0000-0000-000000000000') <> 'partie' then raise exception 'ÉCHEC statut partie'; end if;
end $$;
do $$ begin
  perform public.check_in(id) from public.reservations where check_in = current_date + 3;
  raise exception 'ÉCHEC arrivée anticipée acceptée';
exception when check_violation then null;
end $$;

-- 6. Rôles sans accès aux clients
reset role;
update public.profiles set role = 'entretien' where id = '00000000-0000-0000-0000-000000000004';
set role authenticated;
select pg_temp.as_user(4);
do $$ begin
  if (select count(*) from public.guests) <> 0 then raise exception 'ÉCHEC entretien voit les clients'; end if;
  perform public.check_in('50000000-0000-0000-0000-000000000000');
  raise exception 'ÉCHEC entretien fait un check-in';
exception when insufficient_privilege then null;
end $$;
reset role;
\o
\echo 'Réservations : tests passés.'
