-- All business mutations use RPCs. Clients never receive direct table write grants.
create type public.user_role as enum ('rider','driver','operator','owner');
create type public.service_kind as enum ('shared','private');
create type public.booking_state as enum ('pending','confirmed','boarded','completed','cancelled','rejected','no_show','reschedule_pending');

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null check (length(full_name) between 2 and 120),
 role public.user_role not null default 'rider', language text not null default 'ar' check (language in ('ar','en')),
 suspended_until timestamptz, disabled boolean not null default false, created_at timestamptz not null default now()
);
create table public.routes (
 id uuid primary key default gen_random_uuid(), name_ar text not null, name_en text not null,
 governorate text not null, active boolean not null default true, path_geojson jsonb, created_at timestamptz not null default now()
);
create table public.stops (
 id uuid primary key default gen_random_uuid(), route_id uuid not null references public.routes(id),
 name_ar text not null, name_en text not null, sequence integer not null check (sequence >= 0),
 latitude double precision not null check (latitude between -90 and 90),
 longitude double precision not null check (longitude between -180 and 180),
 unique(route_id, sequence)
);
create table public.vehicles (
 id uuid primary key default gen_random_uuid(), driver_id uuid not null references public.profiles(id),
 plate text not null unique, kind text not null check (kind in ('taxi','minibus','medium_bus','large_bus')),
 capacity integer not null check (capacity between 1 and 80), approved boolean not null default false,
 review_note text, online boolean not null default false, created_at timestamptz not null default now()
);
create table public.vehicle_routes (
 vehicle_id uuid not null references public.vehicles(id) on delete cascade,
 route_id uuid not null references public.routes(id), primary key(vehicle_id, route_id)
);
create table public.documents (
 id uuid primary key default gen_random_uuid(), vehicle_id uuid not null references public.vehicles(id),
 kind text not null check (kind in ('license','permit','insurance','registration','vehicle_photo')),
 storage_path text not null, expires_on date, verified boolean not null default false,
 created_at timestamptz not null default now(), unique(vehicle_id,kind)
);
create table public.trips (
 id uuid primary key default gen_random_uuid(), vehicle_id uuid not null references public.vehicles(id),
 route_id uuid references public.routes(id), service public.service_kind not null,
 direction integer not null default 1 check (direction in (-1,1)),
 origin text not null, destination text not null, starts_at timestamptz not null, ends_at timestamptz not null,
 price numeric(10,2) not null check(price > 0), seat_limit integer not null check(seat_limit > 0),
 street_passengers integer not null default 0 check(street_passengers >= 0),
 instant boolean not null default false, state text not null default 'published' check(state in ('published','active','completed','cancelled')),
 pickup_started_at timestamptz, arrived_at timestamptz, previous_starts_at timestamptz,
 created_at timestamptz not null default now(), check(ends_at > starts_at)
);
create table public.ride_requests (
 id uuid primary key default gen_random_uuid(), rider_id uuid not null references public.profiles(id),
 origin text not null, destination text not null, origin_stop_id uuid references public.stops(id), destination_stop_id uuid references public.stops(id),
 route_id uuid references public.routes(id), service public.service_kind not null, seats integer not null check(seats between 1 and 80),
 latitude double precision not null check(latitude between -90 and 90), longitude double precision not null check(longitude between -180 and 180),
 requested_at timestamptz not null, mode text not null check(mode in ('instant','posted')),
 state text not null default 'searching' check(state in ('searching','offered','booked','expired','cancelled')),
 created_at timestamptz not null default now()
);
create table public.bookings (
 id uuid primary key default gen_random_uuid(), trip_id uuid not null references public.trips(id), rider_id uuid not null references public.profiles(id),
 request_id uuid references public.ride_requests(id), origin_stop_id uuid references public.stops(id), destination_stop_id uuid references public.stops(id),
 seats integer not null check(seats > 0), total_price numeric(10,2) not null check(total_price > 0),
 state public.booking_state not null default 'pending', dispatch_deadline timestamptz,
 confirmed_at timestamptz, boarded_at timestamptz, completed_at timestamptz,
 cancellation_reason text, pickup_started_at timestamptz, arrived_at timestamptz,
 pickup_latitude double precision check(pickup_latitude between -90 and 90), pickup_longitude double precision check(pickup_longitude between -180 and 180), near_notified_at timestamptz,
 created_at timestamptz not null default now()
);
create unique index one_live_booking_per_request on public.bookings(request_id) where request_id is not null and state in ('pending','confirmed','boarded','reschedule_pending');
create unique index one_live_booking_per_trip_rider on public.bookings(trip_id,rider_id) where state in ('pending','confirmed','boarded','reschedule_pending');
create table public.offers (
 id uuid primary key default gen_random_uuid(), request_id uuid not null references public.ride_requests(id), trip_id uuid not null references public.trips(id),
 state text not null default 'pending' check(state in ('pending','accepted','rejected')), created_at timestamptz not null default now(), unique(request_id,trip_id)
);
create table public.vehicle_locations (
 vehicle_id uuid primary key references public.vehicles(id), latitude double precision not null check(latitude between -90 and 90),
 longitude double precision not null check(longitude between -180 and 180), updated_at timestamptz not null default now()
);
create table public.violations (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id), booking_id uuid not null unique references public.bookings(id),
 kind text not null check(kind in ('late_cancel','no_show')), voided boolean not null default false, created_at timestamptz not null default now()
);
create table public.appeals (
 id uuid primary key default gen_random_uuid(), violation_id uuid not null unique references public.violations(id),
 user_id uuid not null references public.profiles(id), message text not null check(length(message) between 5 and 2000),
 state text not null default 'pending' check(state in ('pending','accepted','rejected')), resolution text, created_at timestamptz not null default now()
);
create table public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id),
 kind text not null, body text not null, booking_id uuid references public.bookings(id), read_at timestamptz, created_at timestamptz not null default now()
);
create table public.device_tokens (user_id uuid not null references public.profiles(id), token text not null unique, primary key(user_id,token));
create table public.notification_jobs (
 id uuid primary key default gen_random_uuid(), notification_id uuid not null unique references public.notifications(id),
 attempts integer not null default 0, available_at timestamptz not null default now(), delivered_at timestamptz, last_error text
);
create table public.audit_log (
 id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id), action text not null, entity_id uuid,
 details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table public.settings (key text primary key, value jsonb not null);
insert into public.settings values ('policy','{"late_cancel_minutes":60,"no_show_minutes":5,"violation_limit":3,"window_days":30,"suspension_days":7}'::jsonb);

create index trips_route_time on public.trips(route_id,starts_at) where state in ('published','active');
create index trips_vehicle_time on public.trips(vehicle_id,starts_at,ends_at);
create index bookings_trip_state on public.bookings(trip_id,state);
create index bookings_rider on public.bookings(rider_id,created_at desc);
create index requests_match on public.ride_requests(route_id,service,requested_at) where state in ('searching','offered');
create index violations_window on public.violations(user_id,created_at) where not voided;
create index notifications_user on public.notifications(user_id,created_at desc);
create index audit_recent on public.audit_log(created_at desc);

create function public.on_signup() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,full_name) values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1),'Rider'),120));
 return new;
end $$;
create trigger new_account after insert on auth.users for each row execute function public.on_signup();

create function public.is_staff() returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role in ('owner','operator') and not disabled
 and (suspended_until is null or suspended_until <= now())) and coalesce(auth.jwt()->>'aal','')='aal2'
$$;
create function public.is_owner() returns boolean language sql stable security definer set search_path = '' as $$
 select public.is_staff() and exists(select 1 from public.profiles where id=auth.uid() and role='owner')
$$;
create function public.require_user() returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
 if u is null or not exists(select 1 from public.profiles where id=u and not disabled) then raise exception 'ACCOUNT_UNAVAILABLE'; end if;
 return u;
end $$;
create function public.require_rider() returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid := public.require_user();
begin
 if exists(select 1 from public.profiles where id=u and suspended_until > now()) then raise exception 'ACCOUNT_SUSPENDED'; end if;
 return u;
end $$;
create function public.vehicle_ready(v uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.vehicles x join public.profiles p on p.id=x.driver_id where x.id=v and x.approved and p.role='driver' and not p.disabled
 and (p.suspended_until is null or p.suspended_until <= now()) and
 not exists(select 1 from (values('license'),('insurance'),('registration'),('vehicle_photo'),('permit')) required(kind)
 where not (x.kind='taxi' and required.kind='permit') and not exists(select 1 from public.documents d where d.vehicle_id=x.id
 and d.kind=required.kind and d.verified and (d.expires_on is null and d.kind='vehicle_photo' or d.expires_on>=current_date))))
$$;
create function public.available_seats(t uuid) returns integer language sql stable security definer set search_path = '' as $$
 select greatest(0,x.seat_limit-x.street_passengers-coalesce((select sum(b.seats)::integer from public.bookings b where b.trip_id=x.id and
 (b.state in ('confirmed','boarded','reschedule_pending') or (not x.instant and b.state='completed'))),0)) from public.trips x where x.id=t
$$;
create function public.route_pair_valid(r uuid,a uuid,b uuid,d integer) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.stops s join public.stops e on e.route_id=s.route_id join public.routes x on x.id=s.route_id and x.active where s.id=a and e.id=b and s.route_id=r and (e.sequence-s.sequence)*d>0)
$$;
create function public.distance_m(a double precision,b double precision,c double precision,d double precision) returns double precision language sql immutable as $$
 select 6371000*2*asin(least(1,sqrt(power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2))))
$$;
-- The PostGIS migration replaces this fallback once approved road geometry is available.
create function public.trip_can_reach_pickup(t uuid,lat double precision,lng double precision) returns boolean language sql stable as $$select true$$;
create function public.notify_user(u uuid,k text,m text,b uuid default null) returns void language plpgsql security definer set search_path = '' as $$
declare n uuid;
begin
 insert into public.notifications(user_id,kind,body,booking_id) values(u,k,m,b) returning id into n;
 insert into public.notification_jobs(notification_id) values(n);
end $$;
create function public.log_action(a text,e uuid,d jsonb default '{}'::jsonb) returns void language sql security definer set search_path = '' as $$
 insert into public.audit_log(actor_id,action,entity_id,details) values(auth.uid(),a,e,d)
$$;
