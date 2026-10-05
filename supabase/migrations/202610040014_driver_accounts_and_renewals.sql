-- Driver identity is captured at account creation. A rider cannot promote an
-- existing account through vehicle registration or editable Auth metadata.
alter table public.vehicles add column permit_line text check(permit_line is null or length(permit_line) between 3 and 200);
create table public.driver_details (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 date_of_birth date,
 phone text check(phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.driver_details enable row level security;
create policy driver_details_read on public.driver_details for select to authenticated
 using(public.viewer_enabled() and (user_id=auth.uid() or public.is_staff()));
grant select on public.driver_details to authenticated;
grant all on public.driver_details to service_role;
-- Legacy drivers must fill in missing identity before new work is allowed.
insert into public.driver_details(user_id) select id from public.profiles where role='driver';

create function public.driver_identity_valid(n text,d date,p text) returns boolean
 language sql stable set search_path = '' as $$
 select coalesce(length(btrim(n)) between 3 and 120 and btrim(n) ~ '\S+\s+\S+'
 and d >= date '1900-01-01' and d < (now() at time zone 'Asia/Hebron')::date
 and p ~ '^\+[1-9][0-9]{7,14}$',false)
$$;
create or replace function public.on_signup() returns trigger language plpgsql security definer set search_path = '' as $$
declare driver_signup boolean; n text; dob date; phone text;
begin
 driver_signup:=coalesce(new.raw_app_meta_data->>'provider','email')='email'
   and new.raw_user_meta_data->>'account_type'='driver';
 n:=left(coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'),''),nullif(split_part(new.email,'@',1),''),'Rider'),120);
 if driver_signup then
  begin dob:=nullif(new.raw_user_meta_data->>'date_of_birth','')::date;
  exception when invalid_datetime_format or datetime_field_overflow then raise exception 'DRIVER_IDENTITY_REQUIRED'; end;
  phone:=btrim(new.raw_user_meta_data->>'phone');
  if not public.driver_identity_valid(n,dob,phone) then raise exception 'DRIVER_IDENTITY_REQUIRED'; end if;
 end if;
 insert into public.profiles(id,full_name,role) values(new.id,n,case when driver_signup then 'driver'::public.user_role else 'rider'::public.user_role end);
 if driver_signup then insert into public.driver_details(user_id,date_of_birth,phone) values(new.id,dob,phone); end if;
 return new;
end $$;

-- Social sign-in is a passenger feature, including attempts made outside the UI.
create or replace function public.require_user() returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid:=auth.uid(); role public.user_role;
begin
 select p.role into role from public.profiles p where p.id=u and not p.disabled;
 if u is null or role is null then raise exception 'ACCOUNT_UNAVAILABLE'; end if;
 if role<>'rider' and coalesce(auth.jwt()->'amr','[]'::jsonb) @> '[{"method":"oauth"}]'::jsonb then raise exception 'SOCIAL_SIGNIN_RIDERS_ONLY'; end if;
 return u;
end $$;

alter function public.account_action(text,jsonb) rename to account_action_before_driver_accounts;
revoke all on function public.account_action_before_driver_accounts(text,jsonb) from public,anon,authenticated,service_role;
create function public.account_action(a text,p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid:=public.require_user(); role public.user_role; dob date; phone text; result jsonb;
begin
 select profiles.role into role from public.profiles where id=u for update;
 if a='register_vehicle' then
  if role<>'driver' then raise exception 'DRIVER_ACCOUNT_REQUIRED'; end if;
  if p->>'kind'<>'taxi' and coalesce(length(btrim(p->>'permit_line')),0)<3 then raise exception 'PERMIT_ROUTE_REQUIRED'; end if;
  if not exists(select 1 from public.driver_details d join public.profiles pr on pr.id=d.user_id
   where d.user_id=u and public.driver_identity_valid(pr.full_name,d.date_of_birth,d.phone)) then raise exception 'DRIVER_IDENTITY_REQUIRED'; end if;
 elsif a='driver_identity' then
  if role<>'driver' then raise exception 'DRIVER_ACCOUNT_REQUIRED'; end if;
  begin dob:=nullif(p->>'date_of_birth','')::date;
  exception when invalid_datetime_format or datetime_field_overflow then raise exception 'DRIVER_IDENTITY_REQUIRED'; end;
  phone:=btrim(p->>'phone');
  if not public.driver_identity_valid(p->>'full_name',dob,phone) then raise exception 'DRIVER_IDENTITY_REQUIRED'; end if;
  update public.profiles set full_name=btrim(p->>'full_name') where id=u;
  insert into public.driver_details(user_id,date_of_birth,phone) values(u,dob,phone)
   on conflict(user_id) do update set date_of_birth=excluded.date_of_birth,phone=excluded.phone,updated_at=now();
  update public.vehicles set approved=false,online=false where driver_id=u;
  perform public.log_action('account.driver_identity',u);
  return jsonb_build_object('ok',true,'id',u);
 elsif a='profile' and role='driver' then
  if not exists(select 1 from public.driver_details where user_id=u
    and public.driver_identity_valid(p->>'full_name',date_of_birth,phone)) then raise exception 'DRIVER_IDENTITY_REQUIRED'; end if;
 elsif a='document' and p->>'kind'<>'vehicle_photo' then
  if nullif(p->>'expires_on','') is null or (p->>'expires_on')::date < (now() at time zone 'Asia/Hebron')::date then raise exception 'DOCUMENT_EXPIRY_REQUIRED'; end if;
 end if;
 result:=public.account_action_before_driver_accounts(a,p);
 if a='register_vehicle' then update public.vehicles set permit_line=nullif(btrim(p->>'permit_line'),'') where id=(result->>'id')::uuid; end if;
 return result;
end $$;
revoke all on function public.account_action(text,jsonb) from public,anon;
grant execute on function public.account_action(text,jsonb) to authenticated,service_role;

-- Expiry is checked at every operation, even if the scheduler is unavailable.
-- Login and document upload remain available so the driver can renew documents.
create or replace function public.vehicle_ready(v uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.vehicles x join public.profiles p on p.id=x.driver_id
 join public.driver_details identity on identity.user_id=p.id
 where x.id=v and x.approved and p.role='driver' and not p.disabled
 and public.driver_identity_valid(p.full_name,identity.date_of_birth,identity.phone)
 and (p.suspended_until is null or p.suspended_until<=now())
 and not exists(select 1 from public.documents expired join public.vehicles ev on ev.id=expired.vehicle_id
   where ev.driver_id=p.id and expired.kind<>'vehicle_photo' and not(ev.kind='taxi' and expired.kind='permit')
   and (expired.expires_on is null or expired.expires_on<(now() at time zone 'Asia/Hebron')::date))
 and not exists(select 1 from (values('license'),('insurance'),('registration'),('vehicle_photo'),('permit')) required(kind)
 where not(x.kind='taxi' and required.kind='permit') and not exists(select 1 from public.documents d
 where d.vehicle_id=x.id and d.kind=required.kind and d.verified
 and (d.kind='vehicle_photo' or d.expires_on>=(now() at time zone 'Asia/Hebron')::date))))
$$;

alter function public.admin_action(text,jsonb) rename to admin_action_before_driver_accounts;
revoke all on function public.admin_action_before_driver_accounts(text,jsonb) from public,anon,authenticated,service_role;
create function public.admin_action(a text,p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_staff() then raise exception 'ADMIN_MFA_REQUIRED'; end if;
 if a='approve_vehicle' and not exists(select 1 from public.vehicles v join public.profiles pr on pr.id=v.driver_id
  join public.driver_details d on d.user_id=pr.id where v.id=(p->>'id')::uuid and pr.role='driver'
  and public.driver_identity_valid(pr.full_name,d.date_of_birth,d.phone)) then raise exception 'DRIVER_IDENTITY_REQUIRED'; end if;
 if a='approve_vehicle' and exists(select 1 from public.documents d where d.vehicle_id=(p->>'id')::uuid
  and d.kind<>'vehicle_photo' and (d.expires_on is null or d.expires_on<(now() at time zone 'Asia/Hebron')::date)) then raise exception 'DOCUMENTS_INCOMPLETE'; end if;
 return public.admin_action_before_driver_accounts(a,p);
end $$;
revoke all on function public.admin_action(text,jsonb) from public,anon;
grant execute on function public.admin_action(text,jsonb) to authenticated,service_role;

create table public.document_reminders (
 document_id uuid not null references public.documents(id) on delete cascade,
 expires_on date not null, stage integer not null check(stage in (30,7,1,0)),
 created_at timestamptz not null default now(), primary key(document_id,expires_on,stage)
);
alter table public.document_reminders enable row level security;
create index document_expiry_review on public.documents(expires_on,id) where kind<>'vehicle_photo';
grant all on public.document_reminders to service_role;
create function public.process_document_renewals() returns void language plpgsql security definer set search_path = '' as $$
declare d record; staff record; stage integer; days integer; today date:=(now() at time zone 'Asia/Hebron')::date; body jsonb;
begin
 for d in select doc.*,v.driver_id,v.plate from public.documents doc join public.vehicles v on v.id=doc.vehicle_id
  where doc.kind<>'vehicle_photo' and not(v.kind='taxi' and doc.kind='permit') and doc.expires_on<=today+30
  and not exists(select 1 from public.document_reminders reminder where reminder.document_id=doc.id
    and reminder.expires_on=doc.expires_on and reminder.stage=case when doc.expires_on<today then 0 when doc.expires_on<=today+1 then 1 when doc.expires_on<=today+7 then 7 else 30 end)
  order by doc.expires_on,doc.id limit 500
 loop
  days:=d.expires_on-today;
  -- Catch the nearest milestone after downtime; do not send all old reminders.
  stage:=case when days<0 then 0 when days<=1 then 1 when days<=7 then 7 else 30 end;
  insert into public.document_reminders(document_id,expires_on,stage) values(d.id,d.expires_on,stage) on conflict do nothing;
  if not found then continue; end if;
  body:=jsonb_build_object('document_kind',d.kind,'plate',d.plate,'expires_on',d.expires_on,'days_remaining',days);
  perform public.notify_user(d.driver_id,case when stage=0 then 'document.expired' else 'document.renewal' end,body::text);
  if stage=0 then
   for staff in select id from public.profiles where role in ('owner','operator') and not disabled loop
    perform public.notify_user(staff.id,'document.expired_admin',body::text);
   end loop;
   perform public.log_action('driver.document_expired',d.vehicle_id,body);
  end if;
 end loop;
 update public.vehicles set online=false where online and not public.vehicle_ready(id);
end $$;
revoke all on function public.process_document_renewals() from public,anon,authenticated;
grant execute on function public.process_document_renewals() to service_role;
create or replace function public.process_dispatch() returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
 perform public.process_document_renewals();
 update public.bookings set state='rejected' where state='pending' and dispatch_deadline<=now();
 for r in select id from public.ride_requests where mode='instant' and state in ('searching','offered') loop perform public.dispatch_request(r.id); end loop;
 update public.vehicles set online=false where approved and not public.vehicle_ready(id);
end $$;
revoke all on function public.driver_identity_valid(text,date,text) from public,anon,authenticated;
grant execute on function public.driver_identity_valid(text,date,text) to service_role;
alter publication supabase_realtime add table public.driver_details;
create or replace function public.admin_page(tbl text,query text default '',page integer default 0) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare source text;ordering text;result jsonb;pattern text;
begin
 if not public.is_staff() then raise exception 'ADMIN_MFA_REQUIRED'; end if;
 if tbl<>all(array['profiles','vehicles','documents','routes','stops','trips','bookings','ride_requests','offers','vehicle_locations','violations','appeals','notifications','audit_log','settings'])
 or page<0 or page>5000 or length(query)>100 then raise exception 'INVALID_PAGE_QUERY'; end if;
 source:=format('select to_jsonb(t) as record from public.%I t',tbl);
 if tbl='profiles' then
  source:='select to_jsonb(t)||jsonb_build_object(''phone'',d.phone,''date_of_birth'',d.date_of_birth) as record from public.profiles t left join public.driver_details d on d.user_id=t.id';
 elsif tbl in ('vehicles','bookings','ride_requests','violations','appeals','notifications') then
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

