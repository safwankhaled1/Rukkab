-- Native PostgreSQL smoke check. Fixture accounts, objects and notices roll back.
-- Run from the authorized SQL editor. All fixture changes remain in this rollback-only transaction.
begin;
do $$
declare driver uuid:=gen_random_uuid(); owner uuid; vehicle uuid; result jsonb; document_kind text; path text; jobs jsonb; job jsonb;
begin
 select id into owner from public.profiles where role='owner' and not disabled limit 1;
 if owner is null then raise exception 'OWNER_REQUIRED'; end if;
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data,raw_app_meta_data)
 values(driver,driver::text||'@example.test',now(),jsonb_build_object('account_type','driver','full_name','سائق اختبار مؤقت','phone','٠٥٩٠٠٠٠٠٠٠','date_of_birth','١٩٩٠-٠١-٠١'),'{"provider":"email"}');
 if (select phone from public.driver_details where user_id=driver)<>'+970590000000' then raise exception 'ARABIC_PHONE_FAILED'; end if;
 if exists(select 1 from public.notifications where kind='driver.registered' and body::jsonb->>'driver_id'=driver::text) then raise exception 'DRAFT_SIGNUP_ALERT'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 result:=public.account_action('register_vehicle',jsonb_build_object('kind','medium_bus','capacity','١٩','plate','TEST-APPLICATION-'||driver::text,'permit_line','السموع – الخليل','vehicle_owner_name','مالك مستقل','permit_holder_name','صاحب بيرميت مستقل'));
 vehicle:=(result->>'id')::uuid;
 if (select capacity from public.vehicles where id=vehicle)<>19 then raise exception 'ARABIC_CAPACITY_FAILED'; end if;
 begin
  perform public.submit_driver_application(vehicle);
  raise exception 'INCOMPLETE_APPLICATION_ACCEPTED';
 exception when others then
  if sqlerrm<>'DOCUMENTS_INCOMPLETE' then raise; end if;
 end;
 foreach document_kind in array array['license','permit','insurance','registration','vehicle_photo'] loop
  path:=driver::text||'/'||vehicle::text||'/'||document_kind||'.jpg';
  insert into storage.objects(bucket_id,name) values('driver-documents',path);
  perform public.account_action('document',jsonb_build_object('vehicle_id',vehicle,'kind',document_kind,'storage_path',path,'expires_on','2099-01-01'));
 end loop;
 if exists(select 1 from public.notifications where user_id=owner and case when kind like 'driver.%' then body::jsonb->>'vehicle_id' end=vehicle::text) then raise exception 'DRAFT_STEP_ALERT'; end if;
 result:=public.submit_driver_application(vehicle);
 if result->>'state'<>'submitted' then raise exception 'SUBMISSION_FAILED'; end if;
 result:=public.submit_driver_application(vehicle);
 if not (result->>'already_submitted')::boolean then raise exception 'IDEMPOTENCY_FAILED'; end if;
 if (select count(*) from public.notifications where user_id=owner and kind='driver.application_submitted' and body::jsonb->>'vehicle_id'=vehicle::text)<>1 then raise exception 'FINAL_NOTICE_FAILED'; end if;
 if (select count(*) from public.driver_application_emails where vehicle_id=vehicle)<>1 then raise exception 'MAIL_QUEUE_FAILED'; end if;
 if public.vehicle_ready(vehicle) then raise exception 'UNAPPROVED_APPLICATION_READY'; end if;
 if has_function_privilege('authenticated','public.claim_driver_application_emails()','execute') then raise exception 'MAIL_QUEUE_EXPOSED'; end if;
 if has_function_privilege('authenticated','public.account_action_before_applications(text,jsonb)','execute') then raise exception 'LEGACY_RPC_EXPOSED'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner,'role','authenticated','aal','aal2')::text,true);
 result:=public.admin_page('vehicles','TEST-APPLICATION-'||driver::text,0);
 if result->'rows'->0->>'application_state'<>'submitted' then raise exception 'ADMIN_APPLICATION_STATE_FAILED'; end if;
 result:=public.admin_page_filtered('vehicles','TEST-APPLICATION-'||driver::text,0,'{"application_state":"submitted","approved":false}','capacity');
 if (result->>'count')::integer<>1 or (result->'rows'->0->>'capacity')::integer<>19 then raise exception 'FILTERED_APPLICATION_FAILED'; end if;
 perform public.admin_action('reject_vehicle',jsonb_build_object('id',vehicle,'note','Fixture correction requested'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 begin
  perform public.admin_page_filtered('vehicles','',0,'{}','newest');
  raise exception 'DRIVER_ADMIN_FILTER_ACCESS';
 exception when others then
  if sqlerrm<>'ADMIN_MFA_REQUIRED' then raise; end if;
 end;
 perform public.account_action('update_vehicle_draft',jsonb_build_object('vehicle_id',vehicle,'kind','medium_bus','capacity','٢٠','plate','TEST-APPLICATION-'||driver::text,'permit_line','السموع – الخليل','vehicle_owner_name','مالك مستقل مصحح','permit_holder_name','صاحب بيرميت مستقل'));
 if (select capacity from public.vehicles where id=vehicle)<>20 then raise exception 'DRAFT_CAPACITY_EDIT_FAILED'; end if;
 perform public.submit_driver_application(vehicle);
 perform public.submit_driver_application(vehicle);
 if (select revision from public.driver_applications where vehicle_id=vehicle)<>2 then raise exception 'RESUBMISSION_REVISION_FAILED'; end if;
 if (select count(*) from public.notifications where user_id=owner and kind='driver.application_submitted' and body::jsonb->>'vehicle_id'=vehicle::text)<>2 then raise exception 'RESUBMISSION_NOTICE_FAILED'; end if;
 if (select count(*) from public.driver_application_emails where vehicle_id=vehicle)<>2 then raise exception 'RESUBMISSION_MAIL_QUEUE_FAILED'; end if;

end $$;
rollback;
select 'PASS: Arabic drafts, final submission once, admin filters and MFA, rejected application correction and revision 2; all fixtures rolled back' as driver_application_check;

