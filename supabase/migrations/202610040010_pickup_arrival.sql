alter table public.routes add constraint route_path_type check(path_geojson is null or path_geojson->>'type'='LineString');
alter table public.routes add column road_path extensions.geometry(LineString,4326)
 generated always as (case when path_geojson is null then null else extensions.st_setsrid(extensions.st_geomfromgeojson(path_geojson::text),4326) end) stored;
create index routes_road_path on public.routes using gist(road_path);
create or replace function public.trip_can_reach_pickup(t uuid,lat double precision,lng double precision) returns boolean language plpgsql stable security definer set search_path = '' as $$
declare path extensions.geometry;direction integer;loc public.vehicle_locations;service public.service_kind;car_fraction double precision;pickup_fraction double precision;
begin
 select r.road_path,x.direction,x.service into path,direction,service from public.trips x left join public.routes r on r.id=x.route_id where x.id=t;
 select l.* into loc from public.vehicle_locations l join public.trips x on x.vehicle_id=l.vehicle_id where x.id=t;
 if service='private' or path is null then return true; end if;
 if loc.vehicle_id is null or lat is null or lng is null then return false; end if;
 car_fraction:=extensions.st_linelocatepoint(path,loc.position::extensions.geometry);
 pickup_fraction:=extensions.st_linelocatepoint(path,extensions.st_setsrid(extensions.st_makepoint(lng,lat),4326));
 return (pickup_fraction-car_fraction)*direction>=-least(0.02,200.0/greatest(extensions.st_length(path::extensions.geography),200.0));
end $$;

create function public.validate_pickup(r uuid,a uuid,b uuid,d integer,lat double precision,lng double precision) returns boolean language plpgsql stable security definer set search_path = '' as $$
declare path extensions.geometry; point extensions.geometry; pa double precision;pb double precision;pp double precision;
begin
 if lat is null or lng is null or lat not between -90 and 90 or lng not between -180 and 180 or not public.route_pair_valid(r,a,b,d) then return false; end if;
 if exists(select 1 from public.stops where id=a and public.distance_m(lat,lng,latitude,longitude)<=60) then return true; end if;
 select road_path into path from public.routes where id=r and active;
 if path is null then return false; end if;
 point:=extensions.st_setsrid(extensions.st_makepoint(lng,lat),4326);
 if not extensions.st_dwithin(path::extensions.geography,point::extensions.geography,60) then return false; end if;
 select extensions.st_linelocatepoint(path,position::extensions.geometry) into pa from public.stops where id=a;
 select extensions.st_linelocatepoint(path,position::extensions.geometry) into pb from public.stops where id=b;
 pp:=extensions.st_linelocatepoint(path,point);
 return (pp-pa)*d>=-0.00001 and (pb-pp)*d>0;
end $$;

create function public.propose_pickup(r uuid,lat double precision,lng double precision,destination uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare path extensions.geometry; point extensions.geometry;fraction double precision;dest_fraction double precision;grid double precision;direction integer;anchor public.stops;
begin
 perform public.require_user();
 select road_path into path from public.routes where id=r and active;
 if path is null then
  select * into anchor from public.stops where route_id=r and id<>destination order by position operator(extensions.<->) extensions.st_setsrid(extensions.st_makepoint(lng,lat),4326)::extensions.geography limit 1;
  if anchor.id is null then raise exception 'PICKUP_UNAVAILABLE'; end if;
  return jsonb_build_object('origin_stop_id',anchor.id,'latitude',anchor.latitude,'longitude',anchor.longitude,'name_ar',anchor.name_ar,'name_en',anchor.name_en,'station',true);
 end if;
 point:=extensions.st_setsrid(extensions.st_makepoint(lng,lat),4326);
 if not extensions.st_dwithin(path::extensions.geography,point::extensions.geography,250) then raise exception 'PICKUP_TOO_FAR_FROM_ROUTE'; end if;
 select extensions.st_linelocatepoint(path,position::extensions.geometry) into dest_fraction from public.stops where id=destination and route_id=r;
 if dest_fraction is null then raise exception 'STOP_ROUTE_MISMATCH'; end if;
 fraction:=extensions.st_linelocatepoint(path,point);direction:=case when dest_fraction>fraction then 1 else -1 end;
 -- Stable 200-metre meeting points group nearby riders without changing the road corridor.
 grid:=least(1.0,200.0/greatest(extensions.st_length(path::extensions.geography),200.0));
 fraction:=greatest(0,least(1,round((fraction/grid)::numeric)::double precision*grid));
 point:=extensions.st_lineinterpolatepoint(path,fraction);
 select * into anchor from public.stops s where route_id=r and id<>destination
 and (fraction-extensions.st_linelocatepoint(path,s.position::extensions.geometry))*direction>=-0.00001
 and exists(select 1 from public.stops ds where ds.id=destination and (ds.sequence-s.sequence)*direction>0)
 order by abs(fraction-extensions.st_linelocatepoint(path,s.position::extensions.geometry)) limit 1;
 if anchor.id is null or not public.validate_pickup(r,anchor.id,destination,direction,extensions.st_y(point),extensions.st_x(point)) then raise exception 'PICKUP_UNAVAILABLE'; end if;
 return jsonb_build_object('origin_stop_id',anchor.id,'latitude',extensions.st_y(point),'longitude',extensions.st_x(point),'name_ar','نقطة على خط '||anchor.name_ar,'name_en','Pickup on route near '||anchor.name_en,'station',false);
end $$;

create function public.check_request_pickup() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if new.service='shared' and not(public.validate_pickup(new.route_id,new.origin_stop_id,new.destination_stop_id,1,new.latitude,new.longitude)
 or public.validate_pickup(new.route_id,new.origin_stop_id,new.destination_stop_id,-1,new.latitude,new.longitude)) then raise exception 'PICKUP_OUTSIDE_PERMIT_ROUTE'; end if;
 return new;
end $$;
create trigger request_pickup before insert on public.ride_requests for each row execute function public.check_request_pickup();
create function public.check_booking_pickup() returns trigger language plpgsql security definer set search_path = '' as $$
declare t public.trips;req public.ride_requests;
begin
 select * into t from public.trips where id=new.trip_id;
 if new.request_id is not null then select * into req from public.ride_requests where id=new.request_id;new.pickup_latitude:=req.latitude;new.pickup_longitude:=req.longitude;end if;
 if new.pickup_latitude is null and new.origin_stop_id is not null then select latitude,longitude into new.pickup_latitude,new.pickup_longitude from public.stops where id=new.origin_stop_id; end if;
 if t.service='shared' and not public.validate_pickup(t.route_id,new.origin_stop_id,new.destination_stop_id,t.direction,new.pickup_latitude,new.pickup_longitude) then raise exception 'PICKUP_OUTSIDE_PERMIT_ROUTE'; end if;
 return new;
end $$;
create trigger booking_pickup before insert on public.bookings for each row execute function public.check_booking_pickup();

create function public.check_near_arrival() returns trigger language plpgsql security definer set search_path = '' as $$
declare b record;
begin
 for b in select x.id,x.rider_id from public.bookings x join public.trips t on t.id=x.trip_id
 where t.vehicle_id=new.vehicle_id and (t.state='active' or (t.instant and t.state='published')) and x.state='confirmed' and x.near_notified_at is null
 and x.pickup_latitude is not null and public.distance_m(new.latitude,new.longitude,x.pickup_latitude,x.pickup_longitude)<=300 loop
  update public.bookings set near_notified_at=now() where id=b.id and near_notified_at is null;
  if found then perform public.notify_user(b.rider_id,'booking.near','Your car is approaching the pickup point',b.id);end if;
 end loop;
 return new;
end $$;
create trigger near_arrival after insert or update on public.vehicle_locations for each row execute function public.check_near_arrival();

create table public.arrival_estimates(booking_id uuid primary key references public.bookings(id),target_state public.booking_state not null,minutes integer not null check(minutes>=0),distance_m integer not null check(distance_m>=0),created_at timestamptz not null default now());
alter table public.arrival_estimates enable row level security;
create policy estimate_read on public.arrival_estimates for select to authenticated using(public.viewer_enabled() and exists(select 1 from public.bookings where id=booking_id and rider_id=auth.uid() and state in ('confirmed','boarded')));
revoke all on public.arrival_estimates from anon,authenticated;
grant select on public.arrival_estimates to authenticated;
grant all on public.arrival_estimates to service_role;
revoke execute on function public.validate_pickup(uuid,uuid,uuid,integer,double precision,double precision),public.propose_pickup(uuid,double precision,double precision,uuid),public.check_request_pickup(),public.check_booking_pickup(),public.check_near_arrival() from public,anon,authenticated;
grant execute on function public.propose_pickup(uuid,double precision,double precision,uuid) to authenticated,service_role;
