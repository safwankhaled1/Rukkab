create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
alter table public.vehicle_locations add column position extensions.geography(Point,4326)
 generated always as (extensions.st_setsrid(extensions.st_makepoint(longitude,latitude),4326)::extensions.geography) stored;
alter table public.stops add column position extensions.geography(Point,4326)
 generated always as (extensions.st_setsrid(extensions.st_makepoint(longitude,latitude),4326)::extensions.geography) stored;
create index vehicle_locations_position on public.vehicle_locations using gist(position);
create index stops_position on public.stops using gist(position);
create or replace function public.distance_m(a double precision,b double precision,c double precision,d double precision) returns double precision language sql immutable set search_path = '' as $$
 select extensions.st_distance(extensions.st_setsrid(extensions.st_makepoint(b,a),4326)::extensions.geography,
 extensions.st_setsrid(extensions.st_makepoint(d,c),4326)::extensions.geography)
$$;
-- Used for suggesting a common, approved pickup station rather than deviating from a permit.
create function public.nearest_stops(r uuid,lat double precision,lng double precision) returns jsonb language sql stable security definer set search_path = '' as $$
 select coalesce(jsonb_agg(row_to_json(s)),'[]'::jsonb) from (
 select id,name_ar,name_en,latitude,longitude,sequence,public.distance_m(lat,lng,latitude,longitude) distance_m
 from public.stops where route_id=r order by position operator(extensions.<->) extensions.st_setsrid(extensions.st_makepoint(lng,lat),4326)::extensions.geography limit 3) s
$$;
revoke execute on function public.nearest_stops(uuid,double precision,double precision) from public,anon;
grant execute on function public.nearest_stops(uuid,double precision,double precision) to authenticated,service_role;
