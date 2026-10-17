-- À exécuter UNE FOIS dans l'éditeur SQL de Supabase, après les migrations,
-- et après avoir créé votre compte (Authentication > Users > Add user).
-- Remplacez les valeurs entre <>.

with h as (
  insert into public.hotels (name, timezone) values ('<Nom de l''hôtel>', '<Africa/Bamako>')
  returning id
), s as (
  insert into public.hotel_settings (hotel_id) select id from h
), c as (
  insert into public.currencies (hotel_id, code, name, decimals, is_base)
  select id, '<XOF>', '<Franc CFA>', 0, true from h
)
update public.profiles set hotel_id = (select id from h), role = 'super_admin'
where id = (select id from auth.users where email = '<votre e-mail>');
