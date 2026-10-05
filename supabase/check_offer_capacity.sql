-- Authorized native PostgreSQL smoke check. Synthetic records only; everything rolls back.
begin;
do $$
declare
 driver uuid:=gen_random_uuid(); rider uuid:=gen_random_uuid();
 vid uuid; tid uuid; rid uuid; own_request uuid; valid_request uuid;
 offer_id uuid; bid uuid; actual public.bookings; route_id uuid:=gen_random_uuid();
 origin_id uuid:=gen_random_uuid(); destination_id uuid:=gen_random_uuid();
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data,raw_app_meta_data) values
 (driver,driver::text||'@example.test',now(),'{"account_type":"driver","full_name":"Temporary Offer Driver","phone":"+970599000001","date_of_birth":"1990-01-01"}','{"provider":"email"}'),
 (rider,rider::text||'@example.test',now(),'{"full_name":"Temporary Offer Rider"}','{"provider":"email"}');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 vid:=(public.account_action('register_vehicle',jsonb_build_object('kind','taxi','capacity',4,'plate','TEST-OFFER-'||driver::text,'vehicle_owner_name','Temporary Fixture Owner'))->>'id')::uuid;
 -- These are isolated database fixtures, not approval of a real driver or uploaded legal documents.
 update public.vehicles set approved=true where id=vid;
 insert into public.documents(vehicle_id,kind,storage_path,expires_on,verified)
 select vid,item,'fixture-only','2099-01-01',true from unnest(array['license','insurance','registration','vehicle_photo']) item;
 tid:=public.publish_trip(jsonb_build_object('vehicle_id',vid,'service','private','origin','Temporary pickup','destination','Temporary destination','starts_at',now()+interval '10 minutes','ends_at',now()+interval '2 hours','price',42.5,'seat_limit',4));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
 rid:=public.post_request(jsonb_build_object('mode','posted','service','private','origin','Temporary pickup','destination','Temporary destination','seats',5,'latitude',31.4,'longitude',35.07,'requested_at',now()+interval '10 minutes'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 begin
  perform public.offer_action(jsonb_build_object('action','create','request_id',rid,'trip_id',tid));
  raise exception 'OVERSIZED_OFFER_CREATED';
 exception when others then if sqlerrm<>'INVALID_CAPACITY' then raise; end if; end;
 insert into public.offers(request_id,trip_id) values(rid,tid) returning id into offer_id;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
 begin
  perform public.offer_action(jsonb_build_object('action','accept','offer_id',offer_id));
  raise exception 'OVERSIZED_LEGACY_OFFER_ACCEPTED';
 exception when others then if sqlerrm<>'INVALID_CAPACITY' then raise; end if; end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 own_request:=public.post_request(jsonb_build_object('mode','posted','service','private','origin','Temporary pickup','destination','Temporary destination','seats',2,'latitude',31.4,'longitude',35.07,'requested_at',now()+interval '10 minutes'));
 begin
  perform public.offer_action(jsonb_build_object('action','create','request_id',own_request,'trip_id',tid));
  raise exception 'OWN_OFFER_CREATED';
 exception when others then if sqlerrm<>'CANNOT_BOOK_OWN_VEHICLE' then raise; end if; end;
 insert into public.offers(request_id,trip_id) values(own_request,tid) returning id into offer_id;
 begin
  perform public.offer_action(jsonb_build_object('action','accept','offer_id',offer_id));
  raise exception 'OWN_LEGACY_OFFER_ACCEPTED';
 exception when others then if sqlerrm<>'CANNOT_BOOK_OWN_VEHICLE' then raise; end if; end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
 valid_request:=public.post_request(jsonb_build_object('mode','posted','service','private','origin','Temporary pickup','destination','Temporary destination','seats',2,'latitude',31.4,'longitude',35.07,'requested_at',now()+interval '10 minutes'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 offer_id:=public.offer_action(jsonb_build_object('action','create','request_id',valid_request,'trip_id',tid));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
 bid:=public.offer_action(jsonb_build_object('action','accept','offer_id',offer_id));
 select * into actual from public.bookings where id=bid;
 if actual.seats<>4 or actual.total_price<>42.5 or actual.state<>'confirmed' or actual.pickup_latitude is distinct from 31.4 or actual.pickup_longitude is distinct from 35.07 then raise exception 'PRIVATE_FARE_OR_ALLOCATION_FAILED'; end if;
 if public.available_seats(tid)<>0 then raise exception 'PRIVATE_CAR_NOT_RESERVED'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 perform public.trip_action(tid,'cancel','{}');
 insert into public.routes(id,name_ar,name_en,governorate,path_geojson) values(route_id,'خط مؤقت','Temporary route','fixture','{"type":"LineString","coordinates":[[35,31.4],[35,31.45]]}');
 insert into public.stops(id,route_id,name_ar,name_en,sequence,latitude,longitude) values(origin_id,route_id,'أ','A',0,31.4,35),(destination_id,route_id,'ب','B',1,31.45,35);
 insert into public.vehicle_routes values(vid,route_id);
 tid:=public.publish_trip(jsonb_build_object('vehicle_id',vid,'route_id',route_id,'service','shared','origin','أ','destination','ب','starts_at',now()+interval '10 minutes','ends_at',now()+interval '2 hours','price',12.5,'seat_limit',4));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
 valid_request:=public.post_request(jsonb_build_object('mode','posted','service','shared','origin','أ','destination','ب','route_id',route_id,'origin_stop_id',origin_id,'destination_stop_id',destination_id,'seats',3,'latitude',31.4,'longitude',35,'requested_at',now()+interval '10 minutes'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',driver,'role','authenticated','aal','aal1')::text,true);
 offer_id:=public.offer_action(jsonb_build_object('action','create','request_id',valid_request,'trip_id',tid));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',rider,'role','authenticated','aal','aal1')::text,true);
 bid:=public.offer_action(jsonb_build_object('action','accept','offer_id',offer_id));
 select * into actual from public.bookings where id=bid;
 if actual.seats<>3 or actual.total_price<>37.5 or actual.state<>'confirmed' or public.available_seats(tid)<>1 then raise exception 'SHARED_TOTAL_FARE_FAILED'; end if;
end $$;
rollback;
select 'PASS: oversized groups rejected at create and accept, own-vehicle offers blocked, private car reserved once at 42.5, three shared seats total 37.5; all fixtures rolled back' as offer_capacity_check;
