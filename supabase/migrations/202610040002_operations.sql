alter table public.ride_requests add column quoted_price numeric(10,2) check(quoted_price>0);
alter table public.bookings add column pickup_text text;
alter table public.bookings add column dropoff_text text;

create function public.publish_trip(p jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_rider(); v public.vehicles; r uuid:=nullif(p->>'route_id','')::uuid;
 s public.service_kind:=(p->>'service')::public.service_kind; st timestamptz:=(p->>'starts_at')::timestamptz;
 en timestamptz:=(p->>'ends_at')::timestamptz; n uuid; cap integer:=(p->>'seat_limit')::integer;
begin
 select * into v from public.vehicles where id=(p->>'vehicle_id')::uuid for update;
 if v.id is null or v.driver_id<>u or not public.vehicle_ready(v.id) then raise exception 'DRIVER_NOT_APPROVED'; end if;
 if cap>v.capacity or cap<1 then raise exception 'INVALID_CAPACITY'; end if;
 if s='private' then
  if v.kind<>'taxi' then raise exception 'PRIVATE_TAXI_ONLY'; end if;
  cap:=v.capacity; r:=null;
 else
  if r is null or not exists(select 1 from public.routes where id=r and active) or not exists(select 1 from public.vehicle_routes where vehicle_id=v.id and route_id=r) then raise exception 'PERMIT_ROUTE_MISMATCH'; end if;
 end if;
 if st < now()-interval '5 minutes' or en<=st then raise exception 'INVALID_TRIP_TIME'; end if;
 if exists(select 1 from public.trips where vehicle_id=v.id and state in ('published','active') and starts_at<en and ends_at>st) then raise exception 'VEHICLE_TIME_CONFLICT'; end if;
 insert into public.trips(vehicle_id,route_id,service,direction,origin,destination,starts_at,ends_at,price,seat_limit,instant)
 values(v.id,r,s,coalesce((p->>'direction')::integer,1),p->>'origin',p->>'destination',st,en,(p->>'price')::numeric,cap,coalesce((p->>'instant')::boolean,false)) returning id into n;
 perform public.log_action('trip.publish',n); return n;
end $$;

create function public.request_booking(p jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_rider(); t public.trips; n uuid; seats integer:=(p->>'seats')::integer;
 a uuid:=nullif(p->>'origin_stop_id','')::uuid; b uuid:=nullif(p->>'destination_stop_id','')::uuid;
begin
 select * into t from public.trips where id=(p->>'trip_id')::uuid;
 if t.id is null or t.state not in ('published','active') or t.ends_at<=now() or not public.vehicle_ready(t.vehicle_id) then raise exception 'TRIP_UNAVAILABLE'; end if;
 if t.service='shared' and not public.route_pair_valid(t.route_id,a,b,t.direction) then raise exception 'STOP_ROUTE_MISMATCH'; end if;
 if seats<1 or seats>t.seat_limit then raise exception 'INVALID_CAPACITY'; end if;
 if public.available_seats(t.id)<seats then raise exception 'NO_SEATS'; end if;
 if t.service='private' then seats:=t.seat_limit; end if;
 insert into public.bookings(trip_id,rider_id,seats,total_price,origin_stop_id,destination_stop_id,pickup_text,dropoff_text,pickup_latitude,pickup_longitude)
 values(t.id,u,seats,case when t.service='private' then t.price else t.price*seats end,a,b,p->>'origin',p->>'destination',(p->>'pickup_latitude')::float8,(p->>'pickup_longitude')::float8) returning id into n;
 perform public.notify_user((select driver_id from public.vehicles where id=t.vehicle_id),'booking.requested','New booking request',n);
 perform public.log_action('booking.request',n); return n;
end $$;

create function public.accept_booking(bid uuid) returns void language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_rider(); b public.bookings; t public.trips; v public.vehicles;
begin
 select * into b from public.bookings where id=bid;
 select * into t from public.trips where id=b.trip_id;
 select * into v from public.vehicles where id=t.vehicle_id for update;
 select * into t from public.trips where id=t.id for update;
 select * into b from public.bookings where id=bid for update;
 if v.driver_id is distinct from u then raise exception 'FORBIDDEN'; end if;
 if b.state<>'pending' or (b.dispatch_deadline is not null and b.dispatch_deadline<=now()) then raise exception 'REQUEST_EXPIRED'; end if;
 if not public.vehicle_ready(v.id) or t.state not in ('published','active') or t.ends_at<=now() then raise exception 'TRIP_UNAVAILABLE'; end if;
 if t.seat_limit>v.capacity then raise exception 'INVALID_CAPACITY'; end if;
 if not exists(select 1 from public.profiles where id=b.rider_id and not disabled and (suspended_until is null or suspended_until<=now())) then raise exception 'ACCOUNT_SUSPENDED'; end if;
 if t.service='shared' and (not exists(select 1 from public.vehicle_routes where vehicle_id=v.id and route_id=t.route_id) or not public.route_pair_valid(t.route_id,b.origin_stop_id,b.destination_stop_id,t.direction)) then raise exception 'PERMIT_ROUTE_MISMATCH'; end if;
 if public.available_seats(t.id)<b.seats then raise exception 'NO_SEATS'; end if;
 update public.bookings set state='confirmed',confirmed_at=now() where id=bid;
 if b.request_id is not null then update public.ride_requests set state='booked' where id=b.request_id; end if;
 perform public.notify_user(b.rider_id,'booking.confirmed','Your booking is confirmed',bid);
 perform public.log_action('booking.accept',bid);
end $$;

create function public.add_violation(bid uuid,k text) returns void language plpgsql security definer set search_path = '' as $$
declare u uuid; cnt integer;
begin
 select rider_id into u from public.bookings where id=bid;
 perform 1 from public.profiles where id=u for update;
 insert into public.violations(user_id,booking_id,kind) values(u,bid,k) on conflict(booking_id) do nothing;
 select count(*) into cnt from public.violations where user_id=u and not voided and created_at>=now()-interval '30 days';
 if cnt>=3 then
  update public.profiles set suspended_until=greatest(coalesce(suspended_until,now()),now()+interval '7 days') where id=u;
  perform public.notify_user(u,'account.suspended','Booking suspended for seven days. You can appeal.',bid);
 elsif cnt=2 then perform public.notify_user(u,'account.warning','One more late cancellation or no-show may suspend bookings.',bid); end if;
end $$;

create function public.booking_action(bid uuid,a text,reason text default null) returns void language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_user(); b public.bookings; t public.trips; d uuid; late boolean;
begin
 select * into b from public.bookings where id=bid;
 select * into t from public.trips where id=b.trip_id for update;
 select * into b from public.bookings where id=bid for update;
 select driver_id into d from public.vehicles where id=t.vehicle_id;
 if b.id is null or (u<>b.rider_id and u<>d and not public.is_staff()) then raise exception 'FORBIDDEN'; end if;
 if a='cancel' then
  if b.state not in ('pending','confirmed','reschedule_pending') then raise exception 'INVALID_BOOKING_STATE'; end if;
  late:=u=b.rider_id and b.state='confirmed' and ((t.instant and b.pickup_started_at is not null) or (not t.instant and t.starts_at<=now()+interval '1 hour'));
  update public.bookings set state='cancelled',cancellation_reason=reason where id=bid;
  if late then perform public.add_violation(bid,'late_cancel'); end if;
  if b.request_id is not null then update public.ride_requests set state='cancelled' where id=b.request_id; end if;
 elsif a='reject' and u=d and b.state='pending' then
  update public.bookings set state='rejected' where id=bid;
 elsif a='pickup' and u=d and b.state='confirmed' and t.state='active' then
  update public.bookings set pickup_started_at=coalesce(pickup_started_at,now()) where id=bid;
 elsif a='arrive' and u=d and b.state='confirmed' and t.state='active' then
  update public.bookings set arrived_at=coalesce(arrived_at,now()) where id=bid;
 elsif a='board' and u=d and b.state='confirmed' and t.state='active' then
  update public.bookings set state='boarded',boarded_at=now() where id=bid;
 elsif a='alight' and u=d and b.state='boarded' then
  update public.bookings set state='completed',completed_at=now() where id=bid;
 elsif a='no_show' and u=d and b.state='confirmed' then
  if b.arrived_at is null or b.arrived_at>now()-interval '5 minutes' or t.starts_at>now() then raise exception 'WAIT_FIVE_MINUTES'; end if;
  update public.bookings set state='no_show' where id=bid; perform public.add_violation(bid,'no_show');
 elsif a='accept_time' and u=b.rider_id and b.state='reschedule_pending' then
  update public.bookings set state='confirmed' where id=bid;
 elsif a='decline_time' and u=b.rider_id and b.state='reschedule_pending' then
  update public.bookings set state='cancelled',cancellation_reason='schedule_change' where id=bid;
 else raise exception 'INVALID_BOOKING_ACTION'; end if;
 perform public.notify_user(b.rider_id,'booking.'||a,'Booking updated: '||a,bid);
 perform public.notify_user(d,'booking.'||a,'Booking updated: '||a,bid);
 perform public.log_action('booking.'||a,bid);
end $$;

create function public.trip_action(tid uuid,a text,p jsonb default '{}'::jsonb) returns void language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_user(); t public.trips; v public.vehicles; st timestamptz; en timestamptz; b record; delta integer;
begin
 select * into t from public.trips where id=tid;
 select * into v from public.vehicles where id=t.vehicle_id for update;
 select * into t from public.trips where id=tid for update;
 if t.id is null or (v.driver_id<>u and not public.is_staff()) then raise exception 'FORBIDDEN'; end if;
 if t.state in ('completed','cancelled') then raise exception 'TRIP_FINISHED'; end if;
 if a='start' then
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

create function public.update_location(vid uuid,lat double precision,lng double precision) returns void language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_user();
begin
 if not exists(select 1 from public.vehicles where id=vid and driver_id=u and online) or not public.vehicle_ready(vid) then raise exception 'DRIVER_OFFLINE'; end if;
 insert into public.vehicle_locations(vehicle_id,latitude,longitude) values(vid,lat,lng)
 on conflict(vehicle_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,updated_at=now();
end $$;

create function public.search_trips(p jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_user(); result jsonb;
begin
 select coalesce(jsonb_agg(row_to_json(x)),'[]'::jsonb) into result from (
 select t.*,v.kind,v.plate,public.available_seats(t.id) available_seats,
 case when l.updated_at>now()-interval '2 minutes' and p ? 'latitude' then public.distance_m((p->>'latitude')::float8,(p->>'longitude')::float8,l.latitude,l.longitude) end distance_m
 from public.trips t join public.vehicles v on v.id=t.vehicle_id left join public.vehicle_locations l on l.vehicle_id=v.id
 where t.state in ('published','active') and t.ends_at>now() and public.vehicle_ready(v.id)
 and (t.service='private' or exists(select 1 from public.vehicle_routes vr where vr.vehicle_id=v.id and vr.route_id=t.route_id))
 and (not(p ? 'route_id') or t.service='private' or t.route_id=(p->>'route_id')::uuid)
 and (not(p ? 'service') or p->>'service'='both' or t.service::text=p->>'service')
 and public.available_seats(t.id)>=coalesce((p->>'seats')::integer,1)
 and (not(p ? 'instant') or t.instant=(p->>'instant')::boolean)
 and (not coalesce((p->>'instant')::boolean,false) or (v.online and l.updated_at>now()-interval '2 minutes' and t.starts_at<=now()+interval '5 minutes'))
 and (not coalesce((p->>'instant')::boolean,false) or public.trip_can_reach_pickup(t.id,(p->>'latitude')::float8,(p->>'longitude')::float8))
 and (not(p ? 'day') or (t.starts_at at time zone 'Asia/Hebron')::date=(p->>'day')::date)
 and (not(p ? 'origin_stop_id') or t.service='private' or public.route_pair_valid(t.route_id,(p->>'origin_stop_id')::uuid,(p->>'destination_stop_id')::uuid,t.direction))
 order by distance_m nulls last,t.starts_at limit 100) x;
 return result;
end $$;

create function public.dispatch_request(rid uuid) returns uuid language plpgsql security definer set search_path = '' as $$
declare r public.ride_requests; t public.trips; n uuid;
begin
 select * into r from public.ride_requests where id=rid for update;
 if r.mode<>'instant' or r.state not in ('searching','offered') then return null; end if;
 if exists(select 1 from public.bookings where request_id=rid and state='pending') then return null; end if;
 if r.created_at<=now()-interval '2 minutes' then
  update public.ride_requests set state='expired' where id=rid;
  perform public.notify_user(r.rider_id,'request.expired','No available car. Browse trips or post a request.'); return null;
 end if;
 select x.* into t from public.trips x join public.vehicles v on v.id=x.vehicle_id join public.vehicle_locations l on l.vehicle_id=v.id
 where x.instant and x.service=r.service and x.state in ('published','active') and x.starts_at<=now()+interval '5 minutes' and x.ends_at>now()
 and v.online and l.updated_at>now()-interval '2 minutes' and public.vehicle_ready(v.id) and public.available_seats(x.id)>=r.seats
 and (x.service='private' or exists(select 1 from public.vehicle_routes vr where vr.vehicle_id=v.id and vr.route_id=x.route_id))
 and (x.service='private' or (x.route_id=r.route_id and public.route_pair_valid(x.route_id,r.origin_stop_id,r.destination_stop_id,x.direction)))
 and x.price=r.quoted_price
 and public.trip_can_reach_pickup(x.id,r.latitude,r.longitude)
 and not exists(select 1 from public.bookings where request_id=rid and trip_id=x.id)
 order by public.distance_m(r.latitude,r.longitude,l.latitude,l.longitude),x.id limit 1;
 if t.id is null then update public.ride_requests set state='searching' where id=rid; return null; end if;
 insert into public.bookings(trip_id,rider_id,request_id,origin_stop_id,destination_stop_id,seats,total_price,dispatch_deadline,pickup_text,dropoff_text)
 values(t.id,r.rider_id,rid,r.origin_stop_id,r.destination_stop_id,case when t.service='private' then t.seat_limit else r.seats end,
 case when t.service='private' then t.price else t.price*r.seats end,least(now()+interval '30 seconds',r.created_at+interval '2 minutes'),r.origin,r.destination) returning id into n;
 update public.ride_requests set state='offered' where id=rid;
 perform public.notify_user((select driver_id from public.vehicles where id=t.vehicle_id),'booking.requested','New instant request',n); return n;
end $$;

create function public.post_request(p jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_rider(); n uuid; m text:=p->>'mode';
begin
 if (p->>'service')='shared' and not (public.route_pair_valid((p->>'route_id')::uuid,(p->>'origin_stop_id')::uuid,(p->>'destination_stop_id')::uuid,1)
 or public.route_pair_valid((p->>'route_id')::uuid,(p->>'origin_stop_id')::uuid,(p->>'destination_stop_id')::uuid,-1)) then raise exception 'STOP_ROUTE_MISMATCH'; end if;
 if m='instant' and (p->>'quoted_price')::numeric is null then raise exception 'PRICE_REQUIRED'; end if;
 insert into public.ride_requests(rider_id,origin,destination,origin_stop_id,destination_stop_id,route_id,service,seats,latitude,longitude,requested_at,mode,quoted_price)
 values(u,p->>'origin',p->>'destination',nullif(p->>'origin_stop_id','')::uuid,nullif(p->>'destination_stop_id','')::uuid,nullif(p->>'route_id','')::uuid,
 (p->>'service')::public.service_kind,(p->>'seats')::integer,(p->>'latitude')::float8,(p->>'longitude')::float8,(p->>'requested_at')::timestamptz,m,(p->>'quoted_price')::numeric) returning id into n;
 if m='instant' then perform public.dispatch_request(n); end if;
 perform public.log_action('request.publish',n); return n;
end $$;

create function public.offer_action(p jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_rider(); r public.ride_requests; t public.trips; o public.offers; n uuid; cnt integer;
begin
 if p->>'action'='create' then
  select * into r from public.ride_requests where id=(p->>'request_id')::uuid;
  select * into t from public.trips where id=(p->>'trip_id')::uuid;
  if r.id is null or r.mode<>'posted' or r.state not in ('searching','offered') or t.id is null or t.service<>r.service or t.state<>'published'
  or not public.vehicle_ready(t.vehicle_id) or not exists(select 1 from public.vehicles where id=t.vehicle_id and driver_id=u) then raise exception 'FORBIDDEN'; end if;
  if t.service='shared' and not public.route_pair_valid(t.route_id,r.origin_stop_id,r.destination_stop_id,t.direction) then raise exception 'PERMIT_ROUTE_MISMATCH'; end if;
  insert into public.offers(request_id,trip_id) values(r.id,t.id) returning id into n;
  perform public.notify_user(r.rider_id,'offer.created','A driver offered a trip.'); return n;
 elsif p->>'action'='accept' then
  select * into o from public.offers where id=(p->>'offer_id')::uuid;
  select * into r from public.ride_requests where id=o.request_id for update;
  select * into t from public.trips where id=o.trip_id for update;
  if r.rider_id is distinct from u or r.state not in ('searching','offered') or o.state<>'pending' or not public.vehicle_ready(t.vehicle_id) or t.state<>'published' or t.ends_at<=now() then raise exception 'OFFER_UNAVAILABLE'; end if;
  if t.service='shared' and (not exists(select 1 from public.vehicle_routes where vehicle_id=t.vehicle_id and route_id=t.route_id) or not public.route_pair_valid(t.route_id,r.origin_stop_id,r.destination_stop_id,t.direction)) then raise exception 'PERMIT_ROUTE_MISMATCH'; end if;
  cnt:=case when t.service='private' then t.seat_limit else r.seats end;
  if public.available_seats(t.id)<cnt then raise exception 'NO_SEATS'; end if;
  insert into public.bookings(trip_id,rider_id,request_id,origin_stop_id,destination_stop_id,seats,total_price,state,confirmed_at,pickup_text,dropoff_text)
  values(t.id,u,r.id,r.origin_stop_id,r.destination_stop_id,cnt,case when t.service='private' then t.price else t.price*cnt end,'confirmed',now(),r.origin,r.destination) returning id into n;
  update public.offers set state=case when id=o.id then 'accepted' else 'rejected' end where request_id=r.id;
  update public.ride_requests set state='booked' where id=r.id;
  perform public.notify_user((select driver_id from public.vehicles where id=t.vehicle_id),'offer.accepted','Your offer was accepted',n);
  perform public.log_action('offer.accept',n); return n;
 else raise exception 'INVALID_OFFER_ACTION'; end if;
end $$;
