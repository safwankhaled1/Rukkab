create function public.admin_page(tbl text,query text default '',page integer default 0) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare source text;ordering text;result jsonb;pattern text;
begin
 if not public.is_staff() then raise exception 'ADMIN_MFA_REQUIRED'; end if;
 if tbl<>all(array['profiles','vehicles','documents','routes','stops','trips','bookings','ride_requests','offers','vehicle_locations','violations','appeals','notifications','audit_log','settings'])
 or page<0 or page>5000 or length(query)>100 then raise exception 'INVALID_PAGE_QUERY'; end if;
 source:=format('select to_jsonb(t) as record from public.%I t',tbl);
 if tbl in ('vehicles','bookings','ride_requests','violations','appeals','notifications') then
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
