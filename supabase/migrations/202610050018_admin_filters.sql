-- Server-side filtering precedes pagination; all access still requires admin MFA.
create or replace function public.admin_page_filtered(tbl text,query text default '',page integer default 0,filters jsonb default '{}',sort text default 'newest') returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare source text;ordering text;result jsonb;pattern text;allowed text[];name_field text;date_field text;conditions text;filter_key text;date_from date;date_to date;
begin
 if not public.is_staff() then raise exception 'ADMIN_MFA_REQUIRED'; end if;
 if tbl<>all(array['profiles','vehicles','documents','routes','stops','trips','bookings','ride_requests','offers','vehicle_locations','violations','appeals','notifications','audit_log','settings'])
 or page<0 or page>5000 or length(query)>100 then raise exception 'INVALID_PAGE_QUERY'; end if;
 if jsonb_typeof(filters)<>'object' or length(filters::text)>2000 then raise exception 'INVALID_ADMIN_FILTER'; end if;
 allowed:=case tbl when 'profiles' then array['role','disabled'] when 'vehicles' then array['kind','approved','online','application_state'] when 'documents' then array['kind','verified','renewal_required'] when 'trips' then array['state','service'] when 'bookings' then array['state','service'] when 'ride_requests' then array['state','service'] when 'offers' then array['state'] when 'routes' then array['active'] when 'violations' then array['kind','voided'] when 'appeals' then array['state'] else array[]::text[] end;
 for filter_key in select jsonb_object_keys(filters) loop
  if filter_key not in ('from','to') and not filter_key=any(allowed) then raise exception 'INVALID_ADMIN_FILTER'; end if;
  if filter_key in ('approved','online','verified','disabled','active','renewal_required','voided') and jsonb_typeof(filters->filter_key)<>'boolean' then raise exception 'INVALID_ADMIN_FILTER'; end if;
 end loop;
 if coalesce(filters->>'from','')<>'' then
  if filters->>'from'!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVALID_ADMIN_DATE'; end if;
  date_from:=(filters->>'from')::date;
 end if;
 if coalesce(filters->>'to','')<>'' then
  if filters->>'to'!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVALID_ADMIN_DATE'; end if;
  date_to:=(filters->>'to')::date;
 end if;
 if date_from>date_to then raise exception 'INVALID_ADMIN_DATE'; end if;
 if tbl='settings' and (date_from is not null or date_to is not null) then raise exception 'INVALID_ADMIN_DATE'; end if;
 if sort not in ('newest','oldest','name','capacity','price') then raise exception 'INVALID_ADMIN_SORT'; end if;
 if sort='capacity' and tbl<>'vehicles' or sort='price' and tbl not in ('trips','bookings','offers') then raise exception 'INVALID_ADMIN_SORT'; end if;
 source:=format('select to_jsonb(t) as record from public.%I t',tbl);
 if tbl='profiles' then
  source:='select to_jsonb(t)||jsonb_build_object(''phone'',d.phone,''date_of_birth'',d.date_of_birth) as record from public.profiles t left join public.driver_details d on d.user_id=t.id';
 elsif tbl='vehicles' then
  source:='select to_jsonb(t)||jsonb_build_object(''driver_id_label'',p.full_name,''vehicle_owner_name'',o.vehicle_owner_name,''permit_holder_name'',o.permit_holder_name,''application_state'',a.state,''submitted_at'',a.submitted_at) as record from public.vehicles t left join public.profiles p on p.id=t.driver_id left join public.vehicle_ownership o on o.vehicle_id=t.id left join public.driver_applications a on a.vehicle_id=t.id';
 elsif tbl='bookings' then
  source:='select to_jsonb(t)||jsonb_build_object(''rider_id_label'',p.full_name,''service'',trip.service,''price'',t.total_price) as record from public.bookings t left join public.profiles p on p.id=t.rider_id left join public.trips trip on trip.id=t.trip_id';
 elsif tbl='offers' then
  source:='select to_jsonb(t)||jsonb_build_object(''price'',trip.price) as record from public.offers t left join public.trips trip on trip.id=t.trip_id';
 elsif tbl in ('bookings','ride_requests','violations','appeals','notifications') then
  source:=format('select to_jsonb(t)||jsonb_build_object(%L,p.full_name) as record from public.%I t left join public.profiles p on p.id=t.%I',
   case when tbl='vehicles' then 'driver_id_label' when tbl in ('bookings','ride_requests') then 'rider_id_label' else 'user_id_label' end,tbl,
   case when tbl='vehicles' then 'driver_id' when tbl in ('bookings','ride_requests') then 'rider_id' else 'user_id' end);
 elsif tbl in ('documents','trips','vehicle_locations') then
  source:=format('select to_jsonb(t)||jsonb_build_object(''vehicle_id_label'',v.plate) as record from public.%I t left join public.vehicles v on v.id=t.vehicle_id',tbl);
 elsif tbl='stops' then
  source:='select to_jsonb(t)||jsonb_build_object(''route_id_label'',r.name_ar) as record from public.stops t left join public.routes r on r.id=t.route_id';
 end if;
 name_field:=case tbl when 'profiles' then 'full_name' when 'vehicles' then 'plate' when 'routes' then 'name_ar' when 'stops' then 'name_ar' else 'id' end;
 date_field:=case tbl when 'documents' then 'expires_on' when 'trips' then 'starts_at' when 'vehicle_locations' then 'updated_at' else 'created_at' end;
 ordering:=case when sort='name' then format('record->>%L asc nulls last',name_field)
  when sort='capacity' then '(record->>''capacity'')::numeric desc nulls last'
  when sort='price' then '(record->>''price'')::numeric asc nulls last'
  when tbl='settings' then 'record->>''key'''
  when tbl='stops' then '(record->>''sequence'')::integer'
  when tbl='vehicle_locations' then 'record->>''updated_at'' '||case when sort='oldest' then 'asc' else 'desc' end
  else 'record->>''created_at'' '||case when sort='oldest' then 'asc' else 'desc' end end;
 ordering:=ordering||', coalesce(record->>''id'',record->>''vehicle_id'',record->>''key'')';
 conditions:=format('record @> %L::jsonb',(filters-'from'-'to')::text);
 if date_from is not null then
  conditions:=conditions||format(' and %s >= (%L::date::timestamp at time zone ''Asia/Hebron'')',case when date_field='expires_on' then '(record->>''expires_on'')::date::timestamp at time zone ''Asia/Hebron''' else format('(record->>%L)::timestamptz',date_field) end,date_from);
 end if;
 if date_to is not null then
  conditions:=conditions||format(' and %s < ((%L::date+1)::timestamp at time zone ''Asia/Hebron'')',case when date_field='expires_on' then '(record->>''expires_on'')::date::timestamp at time zone ''Asia/Hebron''' else format('(record->>%L)::timestamptz',date_field) end,date_to);
 end if;
 pattern:='%'||replace(replace(replace(query,E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_')||'%';
 execute format('with records as (%s), filtered as (select record from records where record::text ilike %L and %s), paged as (select record from filtered order by %s limit 20 offset %s)
 select jsonb_build_object(''rows'',coalesce((select jsonb_agg(record) from paged),''[]''::jsonb),''count'',(select count(*) from filtered))',source,pattern,conditions,ordering,page*20) into result;
 return result;
end $$;
revoke execute on function public.admin_page_filtered(text,text,integer,jsonb,text) from public,anon;
grant execute on function public.admin_page_filtered(text,text,integer,jsonb,text) to authenticated,service_role;

