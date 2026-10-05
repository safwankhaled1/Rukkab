-- Native PostgreSQL verification only. All users, alerts and vehicles roll back.
begin;
do $$
declare driver uuid:=gen_random_uuid(); owner uuid; result jsonb; vehicle uuid; page jsonb;
begin
 select id into owner from public.profiles where role='owner' and not disabled limit 1;
 if owner is null then raise exception 'OWNER_REQUIRED_FOR_REVIEW_CHECK'; end if;
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data) values(driver,
  driver::text||'@example.test',jsonb_build_object('account_type','driver','full_name','Temporary Test Driver',
   'phone','+970599000000','date_of_birth','1990-01-01'),'{"provider":"email"}');
 if not exists(select 1 from public.profiles where id=driver and role='driver') then raise exception 'DRIVER_SIGNUP_ROLE_FAILED'; end if;
 if (select count(*) from public.notifications where user_id=owner and kind='driver.registered'
  and body::jsonb->>'driver_id'=driver::text)<>1 then raise exception 'DRIVER_SIGNUP_ALERT_FAILED'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 result:=public.account_action('register_vehicle',jsonb_build_object('kind','minibus','capacity',7,
  'plate','TEST-OWNERS-'||driver::text,'permit_line','Temporary approved-review line',
  'vehicle_owner_name','Another Vehicle Owner','permit_holder_name','Another Permit Holder'));
 vehicle:=(result->>'id')::uuid;
 if not exists(select 1 from public.vehicle_ownership where vehicle_id=vehicle
  and vehicle_owner_name='Another Vehicle Owner' and permit_holder_name='Another Permit Holder') then raise exception 'INDEPENDENT_OWNERSHIP_FAILED'; end if;
 if public.vehicle_ready(vehicle) then raise exception 'UNAPPROVED_REGISTRATION_READY'; end if;
 if (select count(*) from public.notifications where user_id=owner and kind='driver.vehicle_submitted'
  and body::jsonb->>'vehicle_id'=vehicle::text)<>1 then raise exception 'VEHICLE_REVIEW_ALERT_FAILED'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner,'role','authenticated','aal','aal2')::text,true);
 page:=public.admin_page('vehicles','TEST-OWNERS-'||driver::text,0);
 if (page->>'count')::integer<>1 or page->'rows'->0->>'vehicle_owner_name'<>'Another Vehicle Owner'
  or page->'rows'->0->>'permit_holder_name'<>'Another Permit Holder' then raise exception 'ADMIN_OWNERSHIP_REVIEW_FAILED'; end if;
 if has_function_privilege('authenticated','public.account_action_before_ownership(text,jsonb)','execute') then raise exception 'UNGUARDED_LEGACY_ACTION'; end if;
 if has_table_privilege('authenticated','public.vehicle_ownership','insert') then raise exception 'DIRECT_OWNERSHIP_WRITE'; end if;
 if not exists(select 1 from pg_tables where schemaname='public' and tablename='vehicle_ownership' and rowsecurity) then raise exception 'OWNERSHIP_RLS_MISSING'; end if;
end $$;
rollback;
select 'PASS: native driver signup trigger, independent ownership, admin review fields, staff alerts, approval gate and restricted writes; fixtures rolled back' as driver_registration_check;
