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

