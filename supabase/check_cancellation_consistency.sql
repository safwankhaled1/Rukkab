-- Native PostgreSQL check: synthetic accounts only, always rolled back.
rollback;
begin;
do $$
declare
 driver uuid:=gen_random_uuid(); rider uuid:=gen_random_uuid(); staff uuid:=gen_random_uuid();
 vid uuid; tid uuid; rid uuid; oid uuid; bid uuid; departure timestamptz; step integer; n integer;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data,raw_app_meta_data) values
 (driver,driver::text||'@example.test',now(),'{"account_type":"driver","full_name":"Temporary Cancellation Driver","phone":"+970599000008","date_of_birth":"1990-01-01"}','{"provider":"email"}'),
 (rider,rider::text||'@example.test',now(),'{"full_name":"Temporary Cancellation Rider"}','{"provider":"email"}'),
 (staff,staff::text||'@example.test',now(),'{"full_name":"Temporary Cancellation Reviewer"}','{"provider":"email"}');
 update public.profiles set role='operator' where id=staff;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 vid:=(public.account_action('register_vehicle',jsonb_build_object('kind','taxi','capacity',4,'plate','TEST-CANCEL-'||driver::text,'vehicle_owner_name','Temporary Fixture Owner'))->>'id')::uuid;
 -- Isolated fixtures do not approve any real account or legal document.
 update public.vehicles set approved=true where id=vid;
 insert into public.documents(vehicle_id,kind,storage_path,expires_on,verified)
 select vid,item,'fixture-only','2099-01-01',true from unnest(array['license','insurance','registration','vehicle_photo']) item;
 for step in 1..6 loop
  departure:=now()+make_interval(days=>step);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
  tid:=public.publish_trip(jsonb_build_object('vehicle_id',vid,'service','private','origin','Temporary pickup','destination','Temporary destination','starts_at',departure,'ends_at',departure+interval '1 hour','price',45,'seat_limit',4));
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
  rid:=public.post_request(jsonb_build_object('mode','posted','service','private','origin','Temporary pickup','destination','Temporary destination','seats',2,'latitude',31.4,'longitude',35.07,'requested_at',departure));
  perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
  oid:=public.offer_action(jsonb_build_object('action','create','request_id',rid,'trip_id',tid));
  perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
  bid:=public.offer_action(jsonb_build_object('action','accept','offer_id',oid));
  if (select state from public.ride_requests where id=rid)<>'booked' then raise exception 'REQUEST_NOT_BOOKED'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
  if step=2 then
   perform public.trip_action(tid,'reschedule',jsonb_build_object('starts_at',departure+interval '1 hour','ends_at',departure+interval '2 hours'));
   perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
   perform public.booking_action(bid,'decline_time',null);
  elsif step=3 then
   update public.trips set starts_at=now()-interval '10 minutes',ends_at=now()+interval '1 hour' where id=tid;
   perform public.trip_action(tid,'start','{}');
   perform public.booking_action(bid,'arrive',null);
   update public.bookings set arrived_at=now()-interval '6 minutes' where id=bid;
   perform public.booking_action(bid,'no_show',null);
   perform public.trip_action(tid,'finish','{}');
  elsif step=5 then perform public.booking_action(bid,'cancel',null);
  else perform public.trip_action(tid,'cancel','{}');
  end if;
  if (select state from public.ride_requests where id=rid)<>'cancelled' then raise exception 'REQUEST_STATE_MISMATCH_STEP_%',step; end if;
  if public.available_seats(tid)<>4 then raise exception 'SEATS_NOT_RELEASED_STEP_%',step; end if;
  select count(*) into n from public.violations where booking_id=bid;
  if n<>(case when step=3 then 1 else 0 end) then raise exception 'WRONG_RIDER_VIOLATION_STEP_%',step; end if;
  select count(*) into n from public.notifications where user_id=staff and kind='driver.cancellation_review' and body::jsonb->>'driver_id'=driver::text;
  if n<>(case when step>=5 then 1 else 0 end) then raise exception 'REVIEW_ALERT_COUNT_STEP_%',step; end if;
 end loop;
 if not exists(select 1 from public.notifications where user_id=staff and kind='driver.cancellation_review' and body::jsonb->>'driver_id'=driver::text and body::jsonb->>'count'='3' and body::jsonb->>'window_days'='30') then raise exception 'REVIEW_DETAILS_INVALID'; end if;
 if exists(select 1 from public.profiles where id=driver and (disabled or suspended_until is not null)) then raise exception 'DRIVER_AUTOMATICALLY_SUSPENDED'; end if;
 if has_function_privilege('authenticated','public.sync_cancelled_request()','EXECUTE') or has_function_privilege('authenticated','public.review_driver_cancellations()','EXECUTE') then raise exception 'TRIGGER_FUNCTIONS_PUBLIC'; end if;
end $$;
rollback;
select 'PASS: cancellation, schedule refusal and no-show update matched requests and release seats; repeated driver cancellations notify staff once without automatic suspension; fixtures rolled back' as cancellation_consistency_check;
