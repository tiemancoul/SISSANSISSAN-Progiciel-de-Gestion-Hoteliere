-- Tests facturation, paiements et caisse (s'appuie sur 01 à 03 : réservation de 3 nuits à 25 000 XOF,
-- 1 EUR = 655,957 XOF ; utilisateurs 1 super admin, 2 admin, 3 réception).
\set ON_ERROR_STOP on
\o /dev/null
grant select, insert, update, delete on public.invoices, public.invoice_items to authenticated;
grant select on public.invoice_taxes, public.payments, public.cash_sessions, public.invoice_balances to authenticated;
grant execute on all functions in schema public to authenticated;
\i tests/helpers.sql
set role authenticated;

-- Taxes : TVA 18 % sur l'hébergement, taxe de séjour 500 XOF / nuit
select pg_temp.as_user(1);
insert into public.taxes (hotel_id, name, kind, rate, currency) values
  ('10000000-0000-0000-0000-000000000000', 'TVA', 'pourcentage', 18, null),
  ('10000000-0000-0000-0000-000000000000', 'Taxe de séjour', 'montant_par_nuit', 500, 'XOF');

-- 1. Réception : facture depuis la réservation, validation, numéro et totaux figés
select pg_temp.as_user(3);
create temp table t as select public.invoice_from_reservation('50000000-0000-0000-0000-000000000000') as inv;
do $$ declare n text; i record; begin
  n := public.finalize_invoice((select inv from t));
  select * into i from public.invoices where id = (select inv from t);
  if n !~ '^F\d{4}-00001$' then raise exception 'ÉCHEC numéro %', n; end if;
  -- 75 000 + TVA 13 500 + taxe de séjour 1 500
  if (i.subtotal, i.tax_total, i.total) <> (75000, 15000, 90000) then
    raise exception 'ÉCHEC totaux % % %', i.subtotal, i.tax_total, i.total; end if;
  if (select count(*) from public.invoice_taxes where invoice_id = i.id) <> 2 then raise exception 'ÉCHEC taxes figées'; end if;
end $$;

-- 2. Facture validée figée : pas de ligne, pas de modification, pas d'annulation par la réception
select pg_temp.expect_denied($$insert into public.invoice_items (invoice_id, description, quantity, unit_price) select inv, 'Ajout', 1, 1 from t$$, 'ligne sur facture validée');
select pg_temp.expect_denied($$update public.invoices set total = 1 where id = (select inv from t)$$, 'modification du total');
select pg_temp.expect_denied($$update public.invoices set status = 'annulee', cancelled_reason = 'x' where id = (select inv from t)$$, 'annulation par la réception');
do $$ begin
  perform public.finalize_invoice((select inv from t));
  raise exception 'ÉCHEC double validation';
exception when check_violation then null;
end $$;

-- 3. Paiement espèces sans caisse refusé ; avec caisse : monnaie rendue
do $$ begin
  perform public.record_payment((select inv from t), 50000, 'XOF', 'especes', gen_random_uuid(), 50000);
  raise exception 'ÉCHEC espèces sans caisse';
exception when check_violation then null;
end $$;
create temp table s as select public.open_cash_session(10000) as id;
select public.record_payment((select inv from t), 40000, 'XOF', 'especes',
  '60000000-0000-0000-0000-000000000001', 50000);
do $$ begin
  if (select change_given from public.payments where idempotency_key = '60000000-0000-0000-0000-000000000001') <> 10000
    then raise exception 'ÉCHEC monnaie rendue'; end if;
end $$;

-- 4. Idempotence : la même clé ne crée pas de second paiement
select public.record_payment((select inv from t), 40000, 'XOF', 'especes',
  '60000000-0000-0000-0000-000000000001', 50000);
do $$ begin
  if (select count(*) from public.payments) <> 1 then raise exception 'ÉCHEC double paiement'; end if;
end $$;

-- 5. Paiement en euros converti au taux figé ; dépassement du solde refusé
select public.record_payment((select inv from t), 50, 'EUR', 'carte', gen_random_uuid(), null, 'TPE 123');
do $$ begin
  if (select amount_invoice from public.payments where currency = 'EUR') <> 32798 then
    raise exception 'ÉCHEC conversion %', (select amount_invoice from public.payments where currency = 'EUR'); end if;
  if (select balance from public.invoice_balances where invoice_id = (select inv from t)) <> 17202 then
    raise exception 'ÉCHEC solde'; end if;
  perform public.record_payment((select inv from t), 20000, 'XOF', 'carte', gen_random_uuid());
  raise exception 'ÉCHEC paiement supérieur au solde';
exception when check_violation then null;
end $$;

-- 6. Écriture directe dans payments interdite ; remboursement réservé à la direction
select pg_temp.expect_denied($$insert into public.payments (hotel_id, invoice_id, method, amount, currency, rate, amount_invoice, idempotency_key) select '10000000-0000-0000-0000-000000000000', inv, 'carte', 1, 'XOF', 1, 1, gen_random_uuid() from t$$, 'insertion directe de paiement');
do $$ begin
  perform public.record_payment((select inv from t), 1000, 'XOF', 'carte', gen_random_uuid(), null, null, 'remboursement');
  raise exception 'ÉCHEC remboursement par la réception';
exception when insufficient_privilege then null;
end $$;

-- 7. Clôture : théorique = 10 000 + 40 000 ; écart sur comptage
do $$ begin
  if public.close_cash_session((select id from s), 49500) <> -500 then raise exception 'ÉCHEC écart de caisse'; end if;
  if (select expected_amount from public.cash_sessions) <> 50000 then raise exception 'ÉCHEC théorique'; end if;
end $$;

-- 8. Direction : remboursement partiel puis annulation
select pg_temp.as_user(2);
select public.record_payment((select inv from t), 5000, 'XOF', 'carte', gen_random_uuid(), null, null, 'remboursement');
do $$ begin
  if (select balance from public.invoice_balances where invoice_id = (select inv from t)) <> 22202 then
    raise exception 'ÉCHEC solde après remboursement'; end if;
end $$;
update public.invoices set status = 'annulee', cancelled_reason = 'Erreur de chambre' where id = (select inv from t);
select pg_temp.expect_denied($$update public.invoices set cancelled_reason = 'autre' where id = (select inv from t)$$, 'modification d''une facture annulée');
reset role;
\o
\echo 'Facturation : tests passés.'
