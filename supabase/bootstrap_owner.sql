-- Run using psql as the database administrator:
-- psql "$DATABASE_URL" -v owner_email="your-verified-email" -f supabase/bootstrap_owner.sql
-- Never place DATABASE_URL in client configuration or commit it.
begin;
select set_config('rukkab.bootstrap_owner_email', :'owner_email', true);
do $$
begin
 if exists(select 1 from public.profiles where role='owner') then
  raise exception 'OWNER_ALREADY_EXISTS_USE_OWNER_ADMINISTRATION';
 end if;
 if (select count(*) from auth.users u join public.profiles p on p.id=u.id
  where u.email=current_setting('rukkab.bootstrap_owner_email') and u.email_confirmed_at is not null)<>1 then
  raise exception 'EXACTLY_ONE_VERIFIED_OWNER_ACCOUNT_REQUIRED';
 end if;
end $$;
update public.profiles p set role='owner'
from auth.users u where p.id=u.id and u.email=:'owner_email' and u.email_confirmed_at is not null;
insert into public.audit_log(actor_id,action,entity_id,details)
select null,'admin.bootstrap_owner',p.id,'{"source":"verified_initial_account"}'::jsonb
from public.profiles p join auth.users u on u.id=p.id where u.email=:'owner_email';
-- Return the specific account that was promoted. This script never creates a login.
select p.id,p.full_name,p.role,u.email from public.profiles p join auth.users u on u.id=p.id where u.email=:'owner_email';
commit;
