-- Tighten operational checks without changing client write permissions.
-- Approved routes are authoritative even if a client supplies misleading place names.
-- A delayed journey remains exclusive until its passengers leave and it is finished.
create unique index one_active_trip_per_vehicle on public.trips(vehicle_id) where state='active';

create or replace function public.publish_trip(p jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_rider(); v public.vehicles; r uuid:=nullif(p->>'route_id','')::uuid;
 s public.service_kind:=(p->>'service')::public.service_kind; st timestamptz:=(p->>'starts_at')::timestamptz;
 en timestamptz:=(p->>'ends_at')::timestamptz; n uuid; route_origin text; route_destination text; direction integer:=coalesce((p->>'direction')::integer,1); cap integer:=(p->>'seat_limit')::integer;
begin
 select * into v from public.vehicles where id=(p->>'vehicle_id')::uuid for update;
 if v.id is null or v.driver_id<>u or not public.vehicle_ready(v.id) then raise exception 'DRIVER_NOT_APPROVED'; end if;
 if cap>v.capacity or cap<1 then raise exception 'INVALID_CAPACITY'; end if;
 if s='private' then
  if v.kind<>'taxi' then raise exception 'PRIVATE_TAXI_ONLY'; end if;
  cap:=v.capacity; r:=null;
 else
  if r is null or not exists(select 1 from public.routes where id=r and active) or not exists(select 1 from public.vehicle_routes where vehicle_id=v.id and route_id=r) then raise exception 'PERMIT_ROUTE_MISMATCH'; end if;
  if direction not in (-1,1) or (select count(*) from public.stops where route_id=r)<2 then raise exception 'PERMIT_ROUTE_MISMATCH'; end if;
  select name_ar into route_origin from public.stops where route_id=r order by sequence*direction limit 1;
  select name_ar into route_destination from public.stops where route_id=r order by sequence*direction desc limit 1;
  if (nullif(trim(p->>'origin'),'') is not null and trim(p->>'origin')<>route_origin)
   or (nullif(trim(p->>'destination'),'') is not null and trim(p->>'destination')<>route_destination) then raise exception 'PERMIT_ROUTE_MISMATCH'; end if;
 end if;
 if st < now()-interval '5 minutes' or en<=st then raise exception 'INVALID_TRIP_TIME'; end if;
 if exists(select 1 from public.trips where vehicle_id=v.id and state in ('published','active') and starts_at<en and ends_at>st) then raise exception 'VEHICLE_TIME_CONFLICT'; end if;
 insert into public.trips(vehicle_id,route_id,service,direction,origin,destination,starts_at,ends_at,price,seat_limit,instant)
 values(v.id,r,s,direction,case when s='shared' then route_origin else p->>'origin' end,case when s='shared' then route_destination else p->>'destination' end,st,en,(p->>'price')::numeric,cap,coalesce((p->>'instant')::boolean,false)) returning id into n;
 perform public.log_action('trip.publish',n); return n;
end $$;

create or replace function public.trip_action(tid uuid,a text,p jsonb default '{}'::jsonb) returns void language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_user(); t public.trips; v public.vehicles; st timestamptz; en timestamptz; b record; delta integer;
begin
 select * into t from public.trips where id=tid;
 select * into v from public.vehicles where id=t.vehicle_id for update;
 select * into t from public.trips where id=tid for update;
 if t.id is null or (v.driver_id<>u and not public.is_staff()) then raise exception 'FORBIDDEN'; end if;
 if t.state in ('completed','cancelled') then raise exception 'TRIP_FINISHED'; end if;
 if a='start' then
  if t.state<>'published' then raise exception 'INVALID_TRIP_ACTION'; end if;
  if exists(select 1 from public.trips where vehicle_id=v.id and id<>tid and state='active') then raise exception 'VEHICLE_ALREADY_ON_TRIP'; end if;
  if not public.vehicle_ready(v.id) then raise exception 'DRIVER_NOT_APPROVED'; end if;
  if t.starts_at>now()+interval '30 minutes' then raise exception 'TOO_EARLY'; end if;
  update public.trips set state='active' where id=tid;
 elsif a='pickup' and t.state='active' then update public.trips set pickup_started_at=coalesce(pickup_started_at,now()) where id=tid;
 elsif a='arrive' and t.state='active' then
  update public.trips set arrived_at=coalesce(arrived_at,now()) where id=tid;
 elsif a='street' and t.state='active' then
  delta:=(p->>'delta')::integer;
  if delta not in (-1,1) or t.service='private' then raise exception 'INVALID_STREET_ADJUSTMENT'; end if;
  if (delta>0 and public.available_seats(tid)<delta) or t.street_passengers+delta<0 then raise exception 'NO_SEATS'; end if;
  update public.trips set street_passengers=street_passengers+delta where id=tid;
 elsif a='finish' then
  if exists(select 1 from public.bookings where trip_id=tid and state in ('confirmed','boarded','reschedule_pending')) or t.street_passengers>0 then raise exception 'PASSENGERS_REMAIN'; end if;
  update public.trips set state='completed' where id=tid;
  update public.bookings set state='rejected' where trip_id=tid and state='pending';
 elsif a='cancel' then
  if t.street_passengers>0 then raise exception 'PASSENGERS_REMAIN'; end if;
  if exists(select 1 from public.bookings where trip_id=tid and state='boarded') then raise exception 'PASSENGERS_REMAIN'; end if;
  update public.trips set state='cancelled' where id=tid;
  update public.bookings set state='cancelled',cancellation_reason='driver_cancelled' where trip_id=tid and state in ('pending','confirmed','reschedule_pending');
 elsif a='reschedule' and t.state='published' then
  st:=(p->>'starts_at')::timestamptz; en:=(p->>'ends_at')::timestamptz;
  if st<now() or en<=st then raise exception 'INVALID_TRIP_TIME'; end if;
  if exists(select 1 from public.trips where vehicle_id=v.id and id<>tid and state in ('published','active') and starts_at<en and ends_at>st) then raise exception 'VEHICLE_TIME_CONFLICT'; end if;
  update public.trips set previous_starts_at=starts_at,starts_at=st,ends_at=en where id=tid;
  update public.bookings set state='reschedule_pending' where trip_id=tid and state='confirmed';
 else raise exception 'INVALID_TRIP_ACTION'; end if;
 for b in select * from public.bookings where trip_id=tid loop
  if a<>'street' then perform public.notify_user(b.rider_id,'trip.'||a,'Trip updated: '||a,b.id); end if;
 end loop;
 perform public.log_action('trip.'||a,tid,p);
end $$;

create or replace function public.request_booking(p jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_rider(); t public.trips; n uuid; seats integer:=(p->>'seats')::integer;
 a uuid:=nullif(p->>'origin_stop_id','')::uuid; b uuid:=nullif(p->>'destination_stop_id','')::uuid;
begin
 select * into t from public.trips where id=(p->>'trip_id')::uuid;
 if t.id is null or t.state not in ('published','active') or t.ends_at<=now() or not public.vehicle_ready(t.vehicle_id) then raise exception 'TRIP_UNAVAILABLE'; end if;
 if exists(select 1 from public.vehicles where id=t.vehicle_id and driver_id=u) then raise exception 'CANNOT_BOOK_OWN_VEHICLE'; end if;
 if t.service='private' and ((p->>'pickup_latitude')::float8 is null or (p->>'pickup_longitude')::float8 is null
  or nullif(trim(p->>'origin'),'') is null or nullif(trim(p->>'destination'),'') is null) then raise exception 'PICKUP_REQUIRED'; end if;
 if t.service='shared' and not public.route_pair_valid(t.route_id,a,b,t.direction) then raise exception 'STOP_ROUTE_MISMATCH'; end if;
 if seats<1 or seats>t.seat_limit then raise exception 'INVALID_CAPACITY'; end if;
 if public.available_seats(t.id)<seats then raise exception 'NO_SEATS'; end if;
 if t.service='private' then seats:=t.seat_limit; end if;
 insert into public.bookings(trip_id,rider_id,seats,total_price,origin_stop_id,destination_stop_id,pickup_text,dropoff_text,pickup_latitude,pickup_longitude)
 values(t.id,u,seats,case when t.service='private' then t.price else t.price*seats end,a,b,p->>'origin',p->>'destination',(p->>'pickup_latitude')::float8,(p->>'pickup_longitude')::float8) returning id into n;
 perform public.notify_user((select driver_id from public.vehicles where id=t.vehicle_id),'booking.requested','New booking request',n);
 perform public.log_action('booking.request',n); return n;
end $$;

create or replace function public.account_action(a text,p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_user(); n uuid; v public.vehicles;
begin
 case a
 when 'profile' then update public.profiles set full_name=p->>'full_name',language=coalesce(p->>'language','ar') where id=u;
 when 'register_vehicle' then
  if exists(select 1 from public.profiles where id=u and role in ('owner','operator')) then raise exception 'STAFF_ACCOUNT'; end if;
  update public.profiles set role='driver' where id=u;
  insert into public.vehicles(driver_id,plate,kind,capacity) values(u,p->>'plate',p->>'kind',(p->>'capacity')::integer) returning id into n;
 when 'document' then
  select * into v from public.vehicles where id=(p->>'vehicle_id')::uuid for update;
  if v.driver_id is distinct from u then raise exception 'FORBIDDEN'; end if;
  if split_part(p->>'storage_path','/',1)<>u::text or split_part(p->>'storage_path','/',2)<>v.id::text then raise exception 'INVALID_DOCUMENT_PATH'; end if;
  if not exists(select 1 from storage.objects where bucket_id='driver-documents' and name=p->>'storage_path') then raise exception 'DOCUMENT_UPLOAD_REQUIRED'; end if;
  if p->>'kind'='vehicle_photo' and lower(p->>'storage_path') !~ '\.(jpg|jpeg|png)$' then raise exception 'DOCUMENT_FORMAT'; end if;
  if p->>'kind'<>'vehicle_photo' and nullif(p->>'expires_on','') is null then raise exception 'DOCUMENT_EXPIRY_REQUIRED'; end if;
  update public.vehicles set approved=false,online=false where id=v.id;
  insert into public.documents(vehicle_id,kind,storage_path,expires_on) values(v.id,p->>'kind',p->>'storage_path',nullif(p->>'expires_on','')::date)
  on conflict(vehicle_id,kind) do update set storage_path=excluded.storage_path,expires_on=excluded.expires_on,verified=false;
 when 'online' then
  n:=(p->>'vehicle_id')::uuid;
  if not exists(select 1 from public.vehicles where id=n and driver_id=u) then raise exception 'FORBIDDEN'; end if;
  if (p->>'online')::boolean and not public.vehicle_ready(n) then raise exception 'DRIVER_NOT_APPROVED'; end if;
  if (p->>'online')::boolean then update public.vehicles set online=false where driver_id=u and id<>n; end if;
  update public.vehicles set online=(p->>'online')::boolean where id=n;
 when 'appeal' then
  n:=(p->>'violation_id')::uuid;
  if not exists(select 1 from public.violations where id=n and user_id=u and not voided) then raise exception 'FORBIDDEN'; end if;
  insert into public.appeals(violation_id,user_id,message) values(n,u,p->>'message') returning id into n;
 when 'read_notification' then update public.notifications set read_at=now() where id=(p->>'id')::uuid and user_id=u;
 when 'device_token' then insert into public.device_tokens(user_id,token) values(u,p->>'token') on conflict(token) do update set user_id=excluded.user_id;
 when 'remove_device_token' then delete from public.device_tokens where user_id=u and token=p->>'token';
 when 'cancel_request' then
  n:=(p->>'id')::uuid;
  if not exists(select 1 from public.ride_requests where id=n and rider_id=u and state in ('searching','offered')) then raise exception 'FORBIDDEN'; end if;
  update public.ride_requests set state='cancelled' where id=n;
  update public.bookings set state='cancelled' where request_id=n and state='pending';
 else raise exception 'INVALID_ACCOUNT_ACTION'; end case;
 perform public.log_action('account.'||a,n);
 return jsonb_build_object('id',n,'ok',true);
end $$;
