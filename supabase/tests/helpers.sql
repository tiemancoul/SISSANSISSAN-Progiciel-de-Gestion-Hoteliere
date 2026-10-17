-- Fonctions de test partagées (temporaires à la session).
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


-- Réserve la chambre 101 de J+d1 à J+d2 (plpgsql : corps non validé avant la migration 02).
create function pg_temp.book(d1 int, d2 int, st text default 'confirmee') returns void language plpgsql as $$
begin
  insert into public.reservations (hotel_id, guest_id, room_id, check_in, check_out, status)
  select '10000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000000', id,
         current_date + d1, current_date + d2, st::public.reservation_status
  from public.rooms where number = '101';
end $$;
