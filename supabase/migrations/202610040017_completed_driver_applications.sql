-- Saving registration steps is a draft. Staff are notified only after the
-- driver submits a complete, server-validated application.
create function public.ascii_digits(value text) returns text language sql immutable set search_path='' as $$
 select translate(value,'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789')
$$;
create function public.normalized_driver_phone(value text) returns text language plpgsql immutable set search_path='' as $$
declare p text:=regexp_replace(public.ascii_digits(value),'[[:space:]()\-‎‏]','','g');
begin
 if p like '00%' then p:='+'||substr(p,3); end if;
 if p ~ '^05[0-9]{8}$' then p:='+970'||substr(p,2);
 elsif p ~ '^5[0-9]{8}$' then p:='+970'||p;
 elsif p ~ '^(970|972)[0-9]{9}$' then p:='+'||p; end if;
 return p;
end $$;
create or replace function public.driver_identity_valid(n text,d date,p text) returns boolean
language sql stable set search_path='' as $$
 select coalesce(length(btrim(n)) between 3 and 120 and btrim(n) ~ '\S+\s+\S+'
 and d>=date '1900-01-01' and d<(now() at time zone 'Asia/Hebron')::date
 and public.normalized_driver_phone(p) ~ '^\+[1-9][0-9]{7,14}$',false)
$$;
create or replace function public.on_signup() returns trigger language plpgsql security definer set search_path='' as $$
declare driver_signup boolean; n text; dob date; phone text;
begin
 driver_signup:=coalesce(new.raw_app_meta_data->>'provider','email')='email' and new.raw_user_meta_data->>'account_type'='driver';
 n:=left(coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'),''),nullif(split_part(new.email,'@',1),''),'Rider'),120);
 if driver_signup then
  begin dob:=nullif(public.ascii_digits(new.raw_user_meta_data->>'date_of_birth'),'')::date;
  exception when invalid_datetime_format or datetime_field_overflow then raise exception 'DRIVER_IDENTITY_REQUIRED'; end;
  phone:=public.normalized_driver_phone(new.raw_user_meta_data->>'phone');
  if not public.driver_identity_valid(n,dob,phone) then raise exception 'DRIVER_IDENTITY_REQUIRED'; end if;
 end if;
 insert into public.profiles(id,full_name,role) values(new.id,n,case when driver_signup then 'driver'::public.user_role else 'rider'::public.user_role end);
 if driver_signup then insert into public.driver_details(user_id,date_of_birth,phone) values(new.id,dob,phone); end if;
 return new;
end $$;
drop trigger driver_registered_alert on public.driver_details;
create or replace function public.notify_driver_review(driver uuid,kind text,vehicle uuid default null) returns void
language plpgsql security definer set search_path='' as $$
declare staff record; name text;
begin
 -- Legacy draft-save calls remain harmless. They never send application alerts.
 if kind<>'driver.application_submitted' then return; end if;
 select full_name into name from public.profiles where id=driver and role='driver';
 for staff in select id from public.profiles where role in ('owner','operator') and not disabled loop
  perform public.notify_user(staff.id,kind,jsonb_build_object('driver_id',driver,'full_name',name,'vehicle_id',vehicle)::text);
 end loop;
end $$;

create table public.driver_applications (
 vehicle_id uuid primary key references public.vehicles(id) on delete cascade,
 driver_id uuid not null references public.profiles(id),
 state text not null default 'draft' check(state in ('draft','submitted','approved','rejected')),
 revision integer not null default 0, submitted_at timestamptz, review_note text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.driver_applications enable row level security;
create policy driver_application_read on public.driver_applications for select to authenticated using (
 public.is_staff() or driver_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and not disabled)
);
grant select on public.driver_applications to authenticated;
grant all on public.driver_applications to service_role;
insert into public.driver_applications(vehicle_id,driver_id,state)
 select id,driver_id,case when approved then 'approved' else 'draft' end from public.vehicles;
alter publication supabase_realtime add table public.driver_applications;

-- A private outbox records receipt-email work exactly once per submission.
-- A mail worker must be configured; queued is not equivalent to delivered.
create table public.driver_application_emails (
 id uuid primary key default gen_random_uuid(), vehicle_id uuid not null references public.driver_applications(vehicle_id),
 user_id uuid not null references public.profiles(id), revision integer not null,
 template text not null default 'application_received', attempts integer not null default 0,
 available_at timestamptz not null default now(), delivered_at timestamptz, last_error text,
 created_at timestamptz not null default now(), unique(vehicle_id,revision,template)
);
alter table public.driver_application_emails enable row level security;
grant all on public.driver_application_emails to service_role;

alter function public.account_action(text,jsonb) rename to account_action_before_applications;
revoke all on function public.account_action_before_applications(text,jsonb) from public,anon,authenticated,service_role;
create function public.account_action(a text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=public.require_user(); result jsonb; v public.vehicles; capacity integer;
begin
 if a in ('driver_identity','profile') and exists(select 1 from public.driver_applications where driver_id=u and state='submitted') then raise exception 'APPLICATION_ALREADY_SUBMITTED'; end if;
 if a='document' and exists(select 1 from public.driver_applications where vehicle_id=(p->>'vehicle_id')::uuid and driver_id=u and state='submitted') then raise exception 'APPLICATION_ALREADY_SUBMITTED'; end if;
 if a='driver_identity' then
  p:=p||jsonb_build_object('phone',public.normalized_driver_phone(p->>'phone'),'date_of_birth',public.ascii_digits(p->>'date_of_birth'));
 end if;
 if a in ('register_vehicle','update_vehicle_draft') then
  if not exists(select 1 from public.profiles where id=u and role='driver') then raise exception 'DRIVER_ACCOUNT_REQUIRED'; end if;
  begin capacity:=public.ascii_digits(p->>'capacity')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'VALID_CAPACITY_REQUIRED'; end;
  if capacity is null or capacity not between 1 and 80 then raise exception 'VALID_CAPACITY_REQUIRED'; end if;
  p:=p||jsonb_build_object('capacity',capacity,'plate',public.ascii_digits(btrim(p->>'plate')));
 end if;
 if a='update_vehicle_draft' then
  select * into v from public.vehicles where id=(p->>'vehicle_id')::uuid and driver_id=u for update;
  if v.id is null then raise exception 'VEHICLE_NOT_FOUND'; end if;
  if v.approved or exists(select 1 from public.driver_applications where vehicle_id=v.id and state='submitted')
   or exists(select 1 from public.trips where vehicle_id=v.id) then raise exception 'APPLICATION_ALREADY_SUBMITTED'; end if;
  if nullif(btrim(p->>'plate'),'') is null then raise exception 'VEHICLE_PLATE_REQUIRED'; end if;
  if length(btrim(coalesce(p->>'vehicle_owner_name','')))<3 then raise exception 'VEHICLE_OWNER_REQUIRED'; end if;
  if p->>'kind'<>'taxi' and (length(btrim(coalesce(p->>'permit_holder_name','')))<3 or length(btrim(coalesce(p->>'permit_line','')))<3) then raise exception 'PERMIT_DETAILS_REQUIRED'; end if;
  update public.vehicles set plate=p->>'plate',kind=p->>'kind',capacity=capacity,permit_line=nullif(btrim(p->>'permit_line'),'') where id=v.id;
  insert into public.vehicle_ownership(vehicle_id,vehicle_owner_name,permit_holder_name)
   values(v.id,btrim(p->>'vehicle_owner_name'),nullif(btrim(p->>'permit_holder_name'),''))
   on conflict(vehicle_id) do update set vehicle_owner_name=excluded.vehicle_owner_name,permit_holder_name=excluded.permit_holder_name;
  update public.driver_applications set state='draft',updated_at=now() where vehicle_id=v.id;
  perform public.log_action('driver.application_draft',v.id);
  return jsonb_build_object('ok',true,'id',v.id);
 end if;
 result:=public.account_action_before_applications(a,p);
 if a='register_vehicle' then
  insert into public.driver_applications(vehicle_id,driver_id) values((result->>'id')::uuid,u);
 elsif a='driver_identity' then
  update public.driver_applications set state='draft',updated_at=now() where driver_id=u and state in ('approved','rejected');
 end if;
 return result;
end $$;
revoke all on function public.account_action(text,jsonb) from public,anon;
grant execute on function public.account_action(text,jsonb) to authenticated,service_role;

create function public.submit_driver_application(vehicle uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=public.require_user(); v public.vehicles; application public.driver_applications; ownership public.vehicle_ownership; today date:=(now() at time zone 'Asia/Hebron')::date;
begin
 if not exists(select 1 from public.profiles p join public.driver_details d on d.user_id=p.id
  where p.id=u and p.role='driver' and public.driver_identity_valid(p.full_name,d.date_of_birth,d.phone)) then raise exception 'DRIVER_IDENTITY_REQUIRED'; end if;
 if not exists(select 1 from auth.users where id=u and email_confirmed_at is not null) then raise exception 'EMAIL_CONFIRMATION_REQUIRED'; end if;
 select * into v from public.vehicles where id=vehicle and driver_id=u for update;
 if v.id is null then raise exception 'VEHICLE_NOT_FOUND'; end if;
 select * into application from public.driver_applications where vehicle_id=vehicle for update;
 if application.state in ('submitted','approved') then return jsonb_build_object('ok',true,'state',application.state,'already_submitted',true); end if;
 if application.vehicle_id is null then raise exception 'APPLICATION_DRAFT_REQUIRED'; end if;
 select * into ownership from public.vehicle_ownership where vehicle_id=vehicle;
 if coalesce(length(btrim(ownership.vehicle_owner_name)),0)<3 then raise exception 'VEHICLE_OWNER_REQUIRED'; end if;
 if v.kind<>'taxi' and (coalesce(length(btrim(ownership.permit_holder_name)),0)<3 or coalesce(length(btrim(v.permit_line)),0)<3) then raise exception 'PERMIT_DETAILS_REQUIRED'; end if;
 if exists(select 1 from (values('license'),('insurance'),('registration'),('vehicle_photo'),('permit')) required(kind)
  where not(v.kind='taxi' and required.kind='permit') and not exists(select 1 from public.documents d
   join storage.objects object on object.bucket_id='driver-documents' and object.name=d.storage_path
   where d.vehicle_id=vehicle and d.kind=required.kind and (d.kind='vehicle_photo' or d.expires_on>=today))) then raise exception 'DOCUMENTS_INCOMPLETE'; end if;
 update public.driver_applications set state='submitted',submitted_at=now(),updated_at=now(),revision=revision+1 where vehicle_id=vehicle returning * into application;
 perform public.notify_driver_review(u,'driver.application_submitted',vehicle);
 perform public.notify_user(u,'driver.application_received',jsonb_build_object('vehicle_id',vehicle,'plate',v.plate)::text);
 insert into public.driver_application_emails(vehicle_id,user_id,revision) values(vehicle,u,application.revision);
 perform public.log_action('driver.application_submitted',vehicle);
 return jsonb_build_object('ok',true,'state','submitted','email_status','queued');
end $$;
revoke all on function public.submit_driver_application(uuid) from public,anon;
grant execute on function public.submit_driver_application(uuid) to authenticated,service_role;

alter function public.admin_action(text,jsonb) rename to admin_action_before_applications;
revoke all on function public.admin_action_before_applications(text,jsonb) from public,anon,authenticated,service_role;
create function public.admin_action(a text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not public.is_staff() then raise exception 'ADMIN_MFA_REQUIRED'; end if;
 if a='approve_vehicle' and exists(select 1 from public.driver_applications where vehicle_id=(p->>'id')::uuid and state in ('draft','rejected')) then raise exception 'APPLICATION_NOT_SUBMITTED'; end if;
 result:=public.admin_action_before_applications(a,p);
 if a in ('approve_vehicle','reject_vehicle') then
  update public.driver_applications set state=case when a='approve_vehicle' then 'approved' else 'rejected' end,
   review_note=p->>'note',updated_at=now() where vehicle_id=(p->>'id')::uuid;
 end if;
 return result;
end $$;
revoke all on function public.admin_action(text,jsonb) from public,anon;
grant execute on function public.admin_action(text,jsonb) to authenticated,service_role;

alter function public.admin_overview() rename to admin_overview_before_applications;
revoke all on function public.admin_overview_before_applications() from public,anon,authenticated,service_role;
create function public.admin_overview() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.is_staff() then raise exception 'ADMIN_MFA_REQUIRED'; end if;
 return public.admin_overview_before_applications()||jsonb_build_object('pending_vehicles',
  (select count(*) from public.driver_applications a join public.vehicles v on v.id=a.vehicle_id where a.state='submitted' and not v.approved));
end $$;
revoke all on function public.admin_overview() from public,anon;
grant execute on function public.admin_overview() to authenticated,service_role;
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
  source:='select to_jsonb(t)||jsonb_build_object(''driver_id_label'',p.full_name,''vehicle_owner_name'',o.vehicle_owner_name,''permit_holder_name'',o.permit_holder_name,''application_state'',a.state,''submitted_at'',a.submitted_at) as record from public.vehicles t left join public.profiles p on p.id=t.driver_id left join public.vehicle_ownership o on o.vehicle_id=t.id left join public.driver_applications a on a.vehicle_id=t.id';
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

-- Workers lease jobs atomically. Clients cannot read recipients or acknowledge mail.
alter table public.driver_application_emails add column lease uuid;
create function public.claim_driver_application_emails() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 with picked as (
  select id from public.driver_application_emails where delivered_at is null and attempts<6
   and available_at<=now() order by created_at for update skip locked limit 20
 ), leased as (
  update public.driver_application_emails e set attempts=e.attempts+1,
   available_at=now()+interval '5 minutes',lease=gen_random_uuid()
   from picked where e.id=picked.id returning e.*
 ) select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'lease',e.lease,'email',u.email,
  'plate',v.plate,'attempts',e.attempts)), '[]'::jsonb) into result
 from leased e join auth.users u on u.id=e.user_id join public.vehicles v on v.id=e.vehicle_id;
 return result;
end $$;
create function public.finish_driver_application_email(job uuid,token uuid,success boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.driver_application_emails set delivered_at=case when success then now() else null end,
  last_error=case when success then null else 'MAIL_PROVIDER_FAILED' end,
  available_at=now()+make_interval(secs=>least(3600,60*power(2,attempts)::integer)),lease=null
 where id=job and lease=token and delivered_at is null;
end $$;
revoke all on function public.claim_driver_application_emails() from public,anon,authenticated;
revoke all on function public.finish_driver_application_email(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.claim_driver_application_emails() to service_role;
grant execute on function public.finish_driver_application_email(uuid,uuid,boolean) to service_role;


