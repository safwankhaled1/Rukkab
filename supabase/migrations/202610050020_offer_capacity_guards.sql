-- Enforce passenger group size for every offer path. A private taxi reserves the whole vehicle.
create or replace function public.offer_action(p jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_rider(); r public.ride_requests; t public.trips; o public.offers; n uuid; cnt integer;
begin
 if p->>'action'='create' then
  select * into r from public.ride_requests where id=(p->>'request_id')::uuid;
  select * into t from public.trips where id=(p->>'trip_id')::uuid;
  if r.id is null or r.mode<>'posted' or r.state not in ('searching','offered') or t.id is null or t.service<>r.service or t.state<>'published'
  or not public.vehicle_ready(t.vehicle_id) or not exists(select 1 from public.vehicles where id=t.vehicle_id and driver_id=u) then raise exception 'FORBIDDEN'; end if;
  if t.service='shared' and not public.route_pair_valid(t.route_id,r.origin_stop_id,r.destination_stop_id,t.direction) then raise exception 'PERMIT_ROUTE_MISMATCH'; end if;
  if r.rider_id=u then raise exception 'CANNOT_BOOK_OWN_VEHICLE'; end if;
  if r.seats>t.seat_limit then raise exception 'INVALID_CAPACITY'; end if;
  cnt:=case when t.service='private' then t.seat_limit else r.seats end;
  if t.ends_at<=now() then raise exception 'OFFER_UNAVAILABLE'; end if;
  if public.available_seats(t.id)<cnt then raise exception 'NO_SEATS'; end if;
  insert into public.offers(request_id,trip_id) values(r.id,t.id) returning id into n;
  perform public.log_action('offer.create',n);
  perform public.notify_user(r.rider_id,'offer.created','A driver offered a trip.'); return n;
 elsif p->>'action'='accept' then
  select * into o from public.offers where id=(p->>'offer_id')::uuid;
  select * into r from public.ride_requests where id=o.request_id for update;
  select * into t from public.trips where id=o.trip_id for update;
  if r.rider_id is distinct from u or r.state not in ('searching','offered') or o.state<>'pending' or not public.vehicle_ready(t.vehicle_id) or t.state<>'published' or t.ends_at<=now() then raise exception 'OFFER_UNAVAILABLE'; end if;
  if exists(select 1 from public.vehicles where id=t.vehicle_id and driver_id=u) then raise exception 'CANNOT_BOOK_OWN_VEHICLE'; end if;
  if r.seats>t.seat_limit then raise exception 'INVALID_CAPACITY'; end if;
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

revoke all on function public.offer_action(jsonb) from public,anon;
grant execute on function public.offer_action(jsonb) to authenticated,service_role;
