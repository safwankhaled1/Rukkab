-- Run as the database owner after deployment. Every fixture is rolled back.
-- This smoke check exercises native PostGIS and RPC execution, not push delivery.
begin;
do $$
declare
 driver uuid := gen_random_uuid(); rider uuid := gen_random_uuid();
 vehicle uuid := gen_random_uuid(); route uuid := gen_random_uuid();
 origin_stop uuid := gen_random_uuid(); destination_stop uuid := gen_random_uuid();
 trip uuid; booking uuid; pickup jsonb; rejected boolean := false;
begin
 if exists(select 1 from pg_tables where schemaname='public' and not rowsecurity) then
  raise exception 'UNPROTECTED_APP_TABLE';
 end if;
 if has_function_privilege('anon','public.admin_action(text,jsonb)','execute') then
  raise exception 'ANONYMOUS_ADMIN_ACCESS';
 end if;
 if not exists(select 1 from storage.buckets where id='driver-documents' and not public) then
  raise exception 'DOCUMENT_BUCKET_NOT_PRIVATE';
 end if;
 if not exists(select 1 from cron.job where jobname='rukkab-dispatch' and active) then
  raise exception 'DISPATCH_SCHEDULER_INACTIVE';
 end if;
 insert into auth.users(id,email,raw_user_meta_data) values
  (driver,driver::text||'@example.test','{"full_name":"Deployment test driver"}'),
  (rider,rider::text||'@example.test','{"full_name":"Deployment test rider"}');
 update public.profiles set role='driver' where id=driver;
 insert into public.driver_details(user_id,date_of_birth,phone) values(driver,'1990-01-01','+970599000000');
 insert into public.routes(id,name_ar,name_en,governorate,path_geojson)
 values(route,'خط اختبار مؤقت','Temporary test route','test',
  '{"type":"LineString","coordinates":[[35,31.4],[35,31.45]]}');
 insert into public.stops(id,route_id,name_ar,name_en,sequence,latitude,longitude) values
  (origin_stop,route,'أ','A',0,31.4,35),
  (destination_stop,route,'ب','B',1,31.45,35);
 insert into public.vehicles(id,driver_id,plate,kind,capacity,approved)
 values(vehicle,driver,'TEST-'||vehicle::text,'minibus',7,true);
 insert into public.vehicle_routes values(vehicle,route);
 insert into public.documents(vehicle_id,kind,storage_path,expires_on,verified)
 select vehicle,kind,'test-only',current_date+30,true
 from unnest(array['license','insurance','registration','vehicle_photo','permit']) kind;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 trip := public.publish_trip(jsonb_build_object('vehicle_id',vehicle,'route_id',route,
  'service','shared','origin','أ','destination','ب','starts_at',now()+interval '1 day',
  'ends_at',now()+interval '25 hours','price',15,'seat_limit',1));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
 pickup := public.propose_pickup(route,31.42,35.0001,destination_stop);
 if not public.validate_pickup(route,origin_stop,destination_stop,1,
  (pickup->>'latitude')::float8,(pickup->>'longitude')::float8) then
  raise exception 'PROJECTED_PICKUP_INVALID';
 end if;
 begin
  perform public.propose_pickup(route,31.42,35.1,destination_stop);
 exception when others then
  if sqlerrm='PICKUP_TOO_FAR_FROM_ROUTE' then rejected:=true; else raise; end if;
 end;
 if not rejected then raise exception 'OUTSIDE_ROUTE_PICKUP_ACCEPTED'; end if;
 booking := public.request_booking(jsonb_build_object('trip_id',trip,'seats',1,
  'origin_stop_id',origin_stop,'destination_stop_id',destination_stop));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 perform public.accept_booking(booking);
 if public.available_seats(trip)<>0 then raise exception 'SEAT_RESERVATION_FAILED'; end if;
 if not public.route_pair_valid(route,destination_stop,origin_stop,-1) then
  raise exception 'REVERSE_ROUTE_FAILED';
 end if;
 update public.documents set expires_on=(now() at time zone 'Asia/Hebron')::date-1 where vehicle_id=vehicle and kind='license';
 if public.vehicle_ready(vehicle) then raise exception 'EXPIRED_DRIVER_STILL_READY'; end if;
 perform public.process_document_renewals();
 perform public.process_document_renewals();
 if (select count(*) from public.notifications where user_id=driver and kind='document.expired')<>1 then raise exception 'RENEWAL_NOTIFICATION_NOT_DEDUPLICATED'; end if;
 update public.documents set expires_on=(now() at time zone 'Asia/Hebron')::date+365,verified=true where vehicle_id=vehicle and kind='license';
 if public.vehicle_ready(vehicle) then raise exception 'UNREVIEWED_RENEWAL_RESTORED_WORK'; end if;
end $$;
rollback;
select 'PASS: native PostGIS pickup, route directions, booking seats, driver identity, document expiry, persistent renewal hold and reminders, RLS, private storage, scheduler; fixtures rolled back' as deployment_check;
