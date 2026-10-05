-- Keep migration 017 immutable. Disambiguate the capacity variable when a driver edits a draft.
create or replace function public.account_action(a text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=public.require_user(); result jsonb; v public.vehicles; requested_capacity integer;
begin
 if a in ('driver_identity','profile') and exists(select 1 from public.driver_applications where driver_id=u and state='submitted') then raise exception 'APPLICATION_ALREADY_SUBMITTED'; end if;
 if a='document' and exists(select 1 from public.driver_applications where vehicle_id=(p->>'vehicle_id')::uuid and driver_id=u and state='submitted') then raise exception 'APPLICATION_ALREADY_SUBMITTED'; end if;
 if a='driver_identity' then
  p:=p||jsonb_build_object('phone',public.normalized_driver_phone(p->>'phone'),'date_of_birth',public.ascii_digits(p->>'date_of_birth'));
 end if;
 if a in ('register_vehicle','update_vehicle_draft') then
  if not exists(select 1 from public.profiles where id=u and role='driver') then raise exception 'DRIVER_ACCOUNT_REQUIRED'; end if;
  begin requested_capacity:=public.ascii_digits(p->>'capacity')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'VALID_CAPACITY_REQUIRED'; end;
  if requested_capacity is null or requested_capacity not between 1 and 80 then raise exception 'VALID_CAPACITY_REQUIRED'; end if;
  p:=p||jsonb_build_object('capacity',requested_capacity,'plate',public.ascii_digits(btrim(p->>'plate')));
 end if;
 if a='update_vehicle_draft' then
  select * into v from public.vehicles where id=(p->>'vehicle_id')::uuid and driver_id=u for update;
  if v.id is null then raise exception 'VEHICLE_NOT_FOUND'; end if;
  if v.approved or exists(select 1 from public.driver_applications where vehicle_id=v.id and state='submitted')
   or exists(select 1 from public.trips where vehicle_id=v.id) then raise exception 'APPLICATION_ALREADY_SUBMITTED'; end if;
  if nullif(btrim(p->>'plate'),'') is null then raise exception 'VEHICLE_PLATE_REQUIRED'; end if;
  if length(btrim(coalesce(p->>'vehicle_owner_name','')))<3 then raise exception 'VEHICLE_OWNER_REQUIRED'; end if;
  if p->>'kind'<>'taxi' and (length(btrim(coalesce(p->>'permit_holder_name','')))<3 or length(btrim(coalesce(p->>'permit_line','')))<3) then raise exception 'PERMIT_DETAILS_REQUIRED'; end if;
  update public.vehicles set plate=p->>'plate',kind=p->>'kind',capacity=requested_capacity,permit_line=nullif(btrim(p->>'permit_line'),'') where id=v.id;
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

