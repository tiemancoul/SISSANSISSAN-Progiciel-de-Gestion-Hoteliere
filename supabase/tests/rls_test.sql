-- Tests RLS du socle. Lancer : ./supabase/tests/run.sh
\set ON_ERROR_STOP on
\o /dev/null
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on all tables in schema public from anon;

insert into auth.users (id, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', '{"full_name":"Super"}'),
  ('00000000-0000-0000-0000-000000000002', '{"full_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000003', '{"full_name":"Réception"}'),
  ('00000000-0000-0000-0000-000000000004', '{"full_name":"Nouveau"}');
insert into public.hotels (id, name) values ('10000000-0000-0000-0000-000000000000', 'SISSAN SISSAN');
update public.profiles set hotel_id = '10000000-0000-0000-0000-000000000000',
  role = (array['super_admin','admin','reception']::public.app_role[])[right(id::text,1)::int]
  where right(id::text,1) in ('1','2','3');
insert into public.hotel_settings (hotel_id) values ('10000000-0000-0000-0000-000000000000');
insert into public.currencies (hotel_id, code, name, decimals, is_base)
  values ('10000000-0000-0000-0000-000000000000', 'XOF', 'Franc CFA', 0, true);

create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000' || n, false);
$$;

create function pg_temp.expect_denied(stmt text, label text) returns void language plpgsql as $$
declare n int;
begin
  execute stmt;
  get diagnostics n = row_count;
  if n > 0 then raise exception 'ÉCHEC % : % ligne(s) modifiée(s)', label, n; end if;
exception when insufficient_privilege or check_violation then null;
end $$;

-- 1. Super admin : règles et devises
set role authenticated;
select pg_temp.as_user(1);
update public.hotel_settings set deposit_percent = 40;
insert into public.currencies (hotel_id, code, name) values ('10000000-0000-0000-0000-000000000000', 'EUR', 'Euro');
insert into public.exchange_rates (hotel_id, code, rate) values ('10000000-0000-0000-0000-000000000000', 'EUR', 655.957);

-- 2. Admin : catalogue oui, règles non, promotion super admin non
select pg_temp.as_user(2);
insert into public.room_types (id, hotel_id, name, base_rate, currency)
  values ('20000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000000', 'Standard', 25000, 'XOF');
insert into public.rooms (hotel_id, number, room_type_id)
  values ('10000000-0000-0000-0000-000000000000', '101', '20000000-0000-0000-0000-000000000000');
insert into public.conference_rooms (hotel_id, name, capacity, half_day_rate, full_day_rate, currency)
  values ('10000000-0000-0000-0000-000000000000', 'Salle Baobab', 40, 50000, 90000, 'XOF');
select pg_temp.expect_denied($$update public.hotel_settings set deposit_percent = 0$$, 'admin modifie les règles');
select pg_temp.expect_denied($$insert into public.taxes (hotel_id, name, kind, rate) values ('10000000-0000-0000-0000-000000000000','TVA','pourcentage',18)$$, 'admin crée une taxe');
update public.profiles set hotel_id = '10000000-0000-0000-0000-000000000000', role = 'reception'
  where id = '00000000-0000-0000-0000-000000000004';
select pg_temp.expect_denied($$update public.profiles set role = 'super_admin' where id = '00000000-0000-0000-0000-000000000004'$$, 'admin promeut super admin');
select pg_temp.expect_denied($$update public.profiles set role = 'super_admin' where id = '00000000-0000-0000-0000-000000000002'$$, 'admin se promeut');
select pg_temp.expect_denied($$update public.profiles set role = 'reception' where id = '00000000-0000-0000-0000-000000000001'$$, 'admin rétrograde le super admin');

-- 3. Réception : lecture oui, écriture non, audit invisible
select pg_temp.as_user(3);
do $$ begin
  if (select count(*) from public.rooms) <> 1 then raise exception 'ÉCHEC réception ne voit pas les chambres'; end if;
  if (select count(*) from public.audit_logs) <> 0 then raise exception 'ÉCHEC réception voit l''audit'; end if;
  if (select count(*) from public.profiles) <> 1 then raise exception 'ÉCHEC réception voit les autres profils'; end if;
end $$;
select pg_temp.expect_denied($$update public.rooms set number = '999'$$, 'réception modifie une chambre');
select pg_temp.expect_denied($$update public.hotels set name = 'X'$$, 'réception modifie l''hôtel');
select pg_temp.expect_denied($$delete from public.audit_logs$$, 'réception efface l''audit');

-- 4. Anonyme : aucun accès
reset role;
set role anon;
select pg_temp.as_user(0);
select pg_temp.expect_denied($$select * from public.rooms$$, 'anon lit les chambres');

-- 5. Audit alimenté et effacement impossible même pour le super admin
reset role;
set role authenticated;
select pg_temp.as_user(1);
select pg_temp.expect_denied($$delete from public.audit_logs$$, 'super admin efface l''audit');
do $$ begin
  if (select count(*) from public.audit_logs where table_name = 'rooms' and action = 'INSERT') <> 1
    then raise exception 'ÉCHEC audit des chambres absent'; end if;
end $$;
reset role;
\o
\echo 'Tous les tests RLS sont passés.'
