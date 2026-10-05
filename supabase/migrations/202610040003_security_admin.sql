alter table public.profiles add column manual_suspension boolean not null default false;

create function public.admin_action(a text,p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare n uuid:=nullif(p->>'id','')::uuid; v public.vehicles; s jsonb; r uuid; target public.profiles;
begin
 if not public.is_staff() then raise exception 'ADMIN_MFA_REQUIRED'; end if;
 case a
 when 'verify_document' then
  update public.documents set verified=coalesce((p->>'verified')::boolean,true) where id=n;
 when 'approve_vehicle' then
  select * into v from public.vehicles where id=n for update;
  if v.id is null then raise exception 'VEHICLE_NOT_FOUND'; end if;
  if (p->>'capacity')::integer<>v.capacity and exists(select 1 from public.trips where vehicle_id=n and state in ('published','active')) then raise exception 'VEHICLE_HAS_ACTIVE_TRIPS'; end if;
  if exists(select 1 from (values('license'),('insurance'),('registration'),('vehicle_photo'),('permit')) req(kind)
   where not(v.kind='taxi' and req.kind='permit') and not exists(select 1 from public.documents d where d.vehicle_id=n and d.kind=req.kind and d.verified and
    (d.kind='vehicle_photo' or d.expires_on>=current_date))) then raise exception 'DOCUMENTS_INCOMPLETE'; end if;
  if v.kind<>'taxi' and not exists(select 1 from public.vehicle_routes where vehicle_id=n) then raise exception 'PERMIT_ROUTE_REQUIRED'; end if;
  update public.vehicles set approved=true,capacity=(p->>'capacity')::integer,review_note=p->>'note' where id=n;
 when 'reject_vehicle' then update public.vehicles set approved=false,online=false,review_note=p->>'note' where id=n;
 when 'assign_route' then
  insert into public.vehicle_routes(vehicle_id,route_id) values((p->>'vehicle_id')::uuid,(p->>'route_id')::uuid) on conflict do nothing;
 when 'remove_route' then delete from public.vehicle_routes where vehicle_id=(p->>'vehicle_id')::uuid and route_id=(p->>'route_id')::uuid;
 when 'save_route' then
  if n is null then
   insert into public.routes(name_ar,name_en,governorate,path_geojson) values(p->>'name_ar',p->>'name_en',p->>'governorate',nullif(p->'path_geojson','null'::jsonb)) returning id into n;
  else update public.routes set name_ar=p->>'name_ar',name_en=p->>'name_en',governorate=p->>'governorate',active=coalesce((p->>'active')::boolean,true),path_geojson=case when p?'path_geojson' then nullif(p->'path_geojson','null'::jsonb) else path_geojson end where id=n; end if;
 when 'save_stop' then
  if n is null then
   insert into public.stops(route_id,name_ar,name_en,sequence,latitude,longitude) values((p->>'route_id')::uuid,p->>'name_ar',p->>'name_en',(p->>'sequence')::integer,(p->>'latitude')::float8,(p->>'longitude')::float8) returning id into n;
  else update public.stops set name_ar=p->>'name_ar',name_en=p->>'name_en',latitude=(p->>'latitude')::float8,longitude=(p->>'longitude')::float8 where id=n; end if;
 when 'suspend_user' then
  if not public.is_owner() then raise exception 'OWNER_REQUIRED'; end if;
  if (p->>'until')::timestamptz is null or (p->>'until')::timestamptz<=now() then raise exception 'INVALID_SUSPENSION_TIME'; end if;
  select * into target from public.profiles where id=n for update;
  if target.role='owner' then raise exception 'OWNER_PROTECTED'; end if;
  update public.profiles set suspended_until=(p->>'until')::timestamptz,manual_suspension=true where id=n;
  update public.vehicles set online=false where driver_id=n;
 when 'restore_user' then update public.profiles set suspended_until=null,manual_suspension=false where id=n;
 when 'disable_user' then
  if not public.is_owner() then raise exception 'OWNER_REQUIRED'; end if;
  if exists(select 1 from public.profiles where id=n and role='owner') then raise exception 'OWNER_PROTECTED'; end if;
  update public.profiles set disabled=coalesce((p->>'disabled')::boolean,true) where id=n;
  update public.vehicles set online=false where driver_id=n;
 when 'set_role' then
  if not public.is_owner() then raise exception 'OWNER_REQUIRED'; end if;
  if exists(select 1 from public.profiles where id=n and role='owner') then raise exception 'OWNER_PROTECTED'; end if;
  update public.profiles set role=(p->>'role')::public.user_role where id=n;
 when 'resolve_appeal' then
  update public.appeals set state=case when (p->>'accepted')::boolean then 'accepted' else 'rejected' end,resolution=p->>'resolution' where id=n and state='pending';
  if not found then raise exception 'APPEAL_ALREADY_RESOLVED'; end if;
  if (p->>'accepted')::boolean then
   update public.violations set voided=true where id=(select violation_id from public.appeals where id=n) returning user_id into r;
   if (select count(*) from public.violations where user_id=r and not voided and created_at>now()-interval '30 days')<3 then
    update public.profiles set suspended_until=null where id=r and not manual_suspension;
   end if;
  end if;
 when 'notify_user' then perform public.notify_user(n,'admin.message',p->>'body');
 when 'save_setting' then
  if not public.is_owner() then raise exception 'OWNER_REQUIRED'; end if;
  if p->>'key'='policy' then raise exception 'POLICY_REQUIRES_MIGRATION'; end if;
  insert into public.settings(key,value) values(p->>'key',p->'value') on conflict(key) do update set value=excluded.value;
 else raise exception 'INVALID_ADMIN_ACTION';
 end case;
 perform public.log_action('admin.'||a,n,p- 'storage_path');
 return jsonb_build_object('id',n,'ok',true);
end $$;

create function public.account_action(a text,p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
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

create function public.process_dispatch() returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
 update public.bookings set state='rejected' where state='pending' and dispatch_deadline<=now();
 for r in select id from public.ride_requests where mode='instant' and state in ('searching','offered') loop perform public.dispatch_request(r.id); end loop;
 update public.vehicles set online=false where approved and not public.vehicle_ready(id);
end $$;

-- No caller-supplied identity or role is trusted. Role checks read private database rows.
create function public.driver_can_read_rider(r uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.bookings b join public.trips t on t.id=b.trip_id join public.vehicles v on v.id=t.vehicle_id
 where b.rider_id=r and v.driver_id=auth.uid() and b.state in ('pending','confirmed','boarded','reschedule_pending'))
$$;
create function public.owns_trip(tid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.trips t join public.vehicles v on v.id=t.vehicle_id where t.id=tid and v.driver_id=auth.uid())
$$;
create function public.has_booking(tid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.bookings where trip_id=tid and rider_id=auth.uid())
$$;
create function public.can_track(vid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.bookings b join public.trips t on t.id=b.trip_id join public.vehicles v on v.id=t.vehicle_id where t.vehicle_id=vid and b.rider_id=auth.uid() and b.state in ('confirmed','boarded') and (t.state='active' or (t.instant and t.state='published' and v.online)))
$$;
alter table public.profiles enable row level security;
alter table public.routes enable row level security;
alter table public.stops enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_routes enable row level security;
alter table public.documents enable row level security;
alter table public.trips enable row level security;
alter table public.bookings enable row level security;
alter table public.ride_requests enable row level security;
alter table public.offers enable row level security;
alter table public.vehicle_locations enable row level security;
alter table public.violations enable row level security;
alter table public.appeals enable row level security;
alter table public.notifications enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notification_jobs enable row level security;
alter table public.audit_log enable row level security;
alter table public.settings enable row level security;

create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_staff() or public.driver_can_read_rider(id));
create policy routes_read on public.routes for select to authenticated using(active or public.is_staff());
create policy stops_read on public.stops for select to authenticated using(true);
create policy vehicles_read on public.vehicles for select to authenticated using(driver_id=auth.uid() or public.is_staff());
create policy vehicle_routes_read on public.vehicle_routes for select to authenticated using(public.is_staff() or exists(select 1 from public.vehicles where id=vehicle_id and driver_id=auth.uid()));
create policy documents_read on public.documents for select to authenticated using(public.is_staff() or exists(select 1 from public.vehicles where id=vehicle_id and driver_id=auth.uid()));
create policy trips_read on public.trips for select to authenticated using(public.is_staff() or state in ('published','active') or public.owns_trip(id) or public.has_booking(id));
create policy bookings_read on public.bookings for select to authenticated using(public.is_staff() or rider_id=auth.uid() or public.owns_trip(trip_id));
create policy requests_read on public.ride_requests for select to authenticated using(public.is_staff() or rider_id=auth.uid() or (mode='posted' and state in ('searching','offered') and exists(
 select 1 from public.vehicles v where v.driver_id=auth.uid() and public.vehicle_ready(v.id) and ((service='private' and v.kind='taxi') or exists(select 1 from public.vehicle_routes vr where vr.vehicle_id=v.id and vr.route_id=ride_requests.route_id)))));
create policy offers_read on public.offers for select to authenticated using(public.is_staff() or exists(select 1 from public.ride_requests where id=request_id and rider_id=auth.uid()) or exists(select 1 from public.trips t join public.vehicles v on v.id=t.vehicle_id where t.id=trip_id and v.driver_id=auth.uid()));
create policy locations_read on public.vehicle_locations for select to authenticated using(public.is_staff() or exists(select 1 from public.vehicles where id=vehicle_id and driver_id=auth.uid()) or public.can_track(vehicle_id));
create policy violations_read on public.violations for select to authenticated using(user_id=auth.uid() or public.is_staff());
create policy appeals_read on public.appeals for select to authenticated using(user_id=auth.uid() or public.is_staff());
create policy notifications_read on public.notifications for select to authenticated using(user_id=auth.uid() or public.is_staff());
create policy audit_read on public.audit_log for select to authenticated using(public.is_staff());
create policy settings_read on public.settings for select to authenticated using(public.is_staff());

revoke all on all tables in schema public from anon,authenticated;
grant select on public.profiles,public.routes,public.stops,public.vehicles,public.vehicle_routes,public.documents,public.trips,public.bookings,public.ride_requests,public.offers,public.vehicle_locations,public.violations,public.appeals,public.notifications,public.audit_log,public.settings to authenticated;
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.is_staff(),public.is_owner(),public.vehicle_ready(uuid),public.available_seats(uuid) to authenticated;
grant execute on function public.driver_can_read_rider(uuid),public.owns_trip(uuid),public.has_booking(uuid),public.can_track(uuid) to authenticated;
grant execute on function public.publish_trip(jsonb),public.request_booking(jsonb),public.accept_booking(uuid),public.booking_action(uuid,text,text),public.trip_action(uuid,text,jsonb),public.update_location(uuid,double precision,double precision),public.search_trips(jsonb),public.post_request(jsonb),public.offer_action(jsonb),public.admin_action(text,jsonb),public.account_action(text,jsonb) to authenticated;
grant execute on function public.process_dispatch() to service_role;
grant all on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
revoke create on schema public from public,anon,authenticated;
