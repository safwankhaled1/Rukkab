-- Driver, registered vehicle owner and permit holder are independent people.
-- Names are declarations for manual document review, not route authorization.
create table public.vehicle_ownership (
 vehicle_id uuid primary key references public.vehicles(id) on delete cascade,
 vehicle_owner_name text not null, permit_holder_name text,
 created_at timestamptz not null default now()
);
alter table public.vehicle_ownership enable row level security;
create policy vehicle_ownership_read on public.vehicle_ownership for select to authenticated using (
 public.is_staff() or exists(select 1 from public.vehicles v join public.profiles p on p.id=v.driver_id
  where v.id=vehicle_id and v.driver_id=auth.uid() and not p.disabled)
);
grant select on public.vehicle_ownership to authenticated;
grant all on public.vehicle_ownership to service_role;

alter function public.account_action(text,jsonb) rename to account_action_before_ownership;
revoke all on function public.account_action_before_ownership(text,jsonb) from public,anon,authenticated,service_role;
create function public.account_action(a text,p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
 if a='register_vehicle' then
  if not exists(select 1 from public.profiles where id=public.require_user() and role='driver') then raise exception 'DRIVER_ACCOUNT_REQUIRED'; end if;
  if p->>'kind'<>'taxi' and coalesce(length(btrim(p->>'permit_line')),0)<3 then raise exception 'PERMIT_ROUTE_REQUIRED'; end if;
  if length(btrim(coalesce(p->>'vehicle_owner_name','')))<3 then raise exception 'VEHICLE_OWNER_REQUIRED'; end if;
  if p->>'kind'<>'taxi' and length(btrim(coalesce(p->>'permit_holder_name','')))<3 then raise exception 'PERMIT_HOLDER_REQUIRED'; end if;
 end if;
 result:=public.account_action_before_ownership(a,p);
 if a='register_vehicle' then
  insert into public.vehicle_ownership(vehicle_id,vehicle_owner_name,permit_holder_name)
   values((result->>'id')::uuid,btrim(p->>'vehicle_owner_name'),nullif(btrim(p->>'permit_holder_name'),''));
  perform public.notify_driver_review(auth.uid(),'driver.vehicle_submitted',(result->>'id')::uuid);
 end if;
 return result;
end $$;
revoke all on function public.account_action(text,jsonb) from public,anon;
grant execute on function public.account_action(text,jsonb) to authenticated,service_role;

create function public.notify_driver_review(driver uuid,kind text,vehicle uuid default null) returns void
language plpgsql security definer set search_path = '' as $$
declare staff record; name text;
begin
 select full_name into name from public.profiles where id=driver and role='driver';
 if name is null then return; end if;
 for staff in select id from public.profiles where role in ('owner','operator') and not disabled loop
  perform public.notify_user(staff.id,kind,jsonb_build_object('driver_id',driver,'full_name',name,'vehicle_id',vehicle)::text);
 end loop;
end $$;
revoke all on function public.notify_driver_review(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.notify_driver_review(uuid,text,uuid) to service_role;

create function public.driver_registration_alert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 perform public.notify_driver_review(new.user_id,'driver.registered');
 return new;
end $$;
revoke all on function public.driver_registration_alert() from public,anon,authenticated;
create trigger driver_registered_alert after insert on public.driver_details
for each row execute function public.driver_registration_alert();

-- Include pending signups made while this update was being deployed.
do $$ declare driver record; begin
 for driver in select d.user_id from public.driver_details d
  join public.profiles p on p.id=d.user_id where p.role='driver' and not p.disabled
  and not exists(select 1 from public.vehicles v where v.driver_id=d.user_id and v.approved)
  and not exists(select 1 from public.notifications n where n.kind='driver.registered'
    and (n.body::jsonb)->>'driver_id'=d.user_id::text)
 loop perform public.notify_driver_review(driver.user_id,'driver.registered'); end loop;
end $$;


-- Ownership identities are restricted to vehicle owners and staff; riders only see operational vehicle fields.
create or replace function public.admin_page(tbl text,query text default '',page integer default 0) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare source text;ordering text;result jsonb;pattern text;
begin
 if not public.is_staff() then raise exception 'ADMIN_MFA_REQUIRED'; end if;
 if tbl<>all(array['profiles','vehicles','documents','routes','stops','trips','bookings','ride_requests','offers','vehicle_locations','violations','appeals','notifications','audit_log','settings'])
 or page<0 or page>5000 or length(query)>100 then raise exception 'INVALID_PAGE_QUERY'; end if;
 source:=format('select to_jsonb(t) as record from public.%I t',tbl);
 if tbl='profiles' then
  source:='select to_jsonb(t)||jsonb_build_object(''phone'',d.phone,''date_of_birth'',d.date_of_birth) as record from public.profiles t left join public.driver_details d on d.user_id=t.id';
 elsif tbl='vehicles' then
  source:='select to_jsonb(t)||jsonb_build_object(''driver_id_label'',p.full_name,''vehicle_owner_name'',o.vehicle_owner_name,''permit_holder_name'',o.permit_holder_name) as record from public.vehicles t left join public.profiles p on p.id=t.driver_id left join public.vehicle_ownership o on o.vehicle_id=t.id';
 elsif tbl in ('bookings','ride_requests','violations','appeals','notifications') then
  source:=format('select to_jsonb(t)||jsonb_build_object(%L,p.full_name) as record from public.%I t left join public.profiles p on p.id=t.%I',
   case when tbl='vehicles' then 'driver_id_label' when tbl in ('bookings','ride_requests') then 'rider_id_label' else 'user_id_label' end,tbl,
   case when tbl='vehicles' then 'driver_id' when tbl in ('bookings','ride_requests') then 'rider_id' else 'user_id' end);
 elsif tbl in ('documents','trips','vehicle_locations') then
  source:=format('select to_jsonb(t)||jsonb_build_object(''vehicle_id_label'',v.plate) as record from public.%I t left join public.vehicles v on v.id=t.vehicle_id',tbl);
 elsif tbl='stops' then
  source:='select to_jsonb(t)||jsonb_build_object(''route_id_label'',r.name_ar) as record from public.stops t left join public.routes r on r.id=t.route_id';
 end if;
 ordering:=case when tbl='settings' then 'record->>''key''' when tbl='stops' then '(record->>''sequence'')::integer' when tbl='vehicle_locations' then 'record->>''updated_at'' desc' else 'record->>''created_at'' desc' end;
 ordering:=ordering||', coalesce(record->>''id'',record->>''vehicle_id'',record->>''key'')';
 pattern:='%'||replace(replace(replace(query,E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_')||'%';
 execute format('with records as (%s), filtered as (select record from records where record::text ilike %L), paged as (select record from filtered order by %s limit 20 offset %s)
 select jsonb_build_object(''rows'',coalesce((select jsonb_agg(record) from paged),''[]''::jsonb),''count'',(select count(*) from filtered))',source,pattern,ordering,page*20) into result;
 return result;
end $$;
revoke execute on function public.admin_page(text,text,integer) from public,anon;
grant execute on function public.admin_page(text,text,integer) to authenticated,service_role;

