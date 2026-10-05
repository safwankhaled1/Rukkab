-- Keep an expired document's account-wide hold across replacement uploads.
-- Otherwise a multi-vehicle driver could resume on another car before review.
alter table public.documents add column renewal_required boolean not null default false;
create function public.preserve_document_renewal_hold() returns trigger language plpgsql set search_path = '' as $$
begin
 if new.kind<>'vehicle_photo' and (new.storage_path is distinct from old.storage_path or new.expires_on is distinct from old.expires_on)
  and (old.renewal_required or old.expires_on<(now() at time zone 'Asia/Hebron')::date) then
  new.renewal_required:=true;
 end if;
 return new;
end $$;
revoke all on function public.preserve_document_renewal_hold() from public,anon,authenticated,service_role;
create trigger preserve_renewal_hold before update on public.documents for each row execute function public.preserve_document_renewal_hold();

-- Preserve this function's identity because RLS policies depend on it.
create or replace function public.vehicle_ready(v uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.vehicles x join public.profiles p on p.id=x.driver_id
 join public.driver_details identity on identity.user_id=p.id
 where x.id=v and x.approved and p.role='driver' and not p.disabled
 and public.driver_identity_valid(p.full_name,identity.date_of_birth,identity.phone)
 and (p.suspended_until is null or p.suspended_until<=now())
 and not exists(select 1 from public.documents expired join public.vehicles ev on ev.id=expired.vehicle_id
   where ev.driver_id=p.id and expired.kind<>'vehicle_photo' and not(ev.kind='taxi' and expired.kind='permit')
   and (expired.renewal_required or expired.expires_on is null or expired.expires_on<(now() at time zone 'Asia/Hebron')::date))
 and not exists(select 1 from (values('license'),('insurance'),('registration'),('vehicle_photo'),('permit')) required(kind)
 where not(x.kind='taxi' and required.kind='permit') and not exists(select 1 from public.documents d
 where d.vehicle_id=x.id and d.kind=required.kind and d.verified
 and (d.kind='vehicle_photo' or d.expires_on>=(now() at time zone 'Asia/Hebron')::date))))
$$;
revoke all on function public.vehicle_ready(uuid) from public,anon;
grant execute on function public.vehicle_ready(uuid) to authenticated,service_role;

alter function public.admin_action(text,jsonb) rename to admin_action_before_renewal_holds;
revoke all on function public.admin_action_before_renewal_holds(text,jsonb) from public,anon,authenticated,service_role;
create function public.admin_action(a text,p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
 result:=public.admin_action_before_renewal_holds(a,p);
 if a='approve_vehicle' then
  update public.documents set renewal_required=false where vehicle_id=(p->>'id')::uuid
    and verified and expires_on>=(now() at time zone 'Asia/Hebron')::date;
 end if;
 return result;
end $$;
revoke all on function public.admin_action(text,jsonb) from public,anon;
grant execute on function public.admin_action(text,jsonb) to authenticated,service_role;

create or replace function public.process_document_renewals() returns void language plpgsql security definer set search_path = '' as $$
declare d record; staff record; stage integer; days integer; today date:=(now() at time zone 'Asia/Hebron')::date; body jsonb;
begin
 update public.documents expiring set renewal_required=true where not expiring.renewal_required and expiring.kind<>'vehicle_photo'
  and expiring.expires_on<(now() at time zone 'Asia/Hebron')::date
  and exists(select 1 from public.vehicles v where v.id=expiring.vehicle_id and not(v.kind='taxi' and expiring.kind='permit'));
 for d in select doc.*,v.driver_id,v.plate from public.documents doc join public.vehicles v on v.id=doc.vehicle_id
  where doc.kind<>'vehicle_photo' and not(v.kind='taxi' and doc.kind='permit') and doc.expires_on<=today+30
  and not exists(select 1 from public.document_reminders reminder where reminder.document_id=doc.id
    and reminder.expires_on=doc.expires_on and reminder.stage=case when doc.expires_on<today then 0 when doc.expires_on<=today+1 then 1 when doc.expires_on<=today+7 then 7 else 30 end)
  order by doc.expires_on,doc.id limit 500
 loop
  days:=d.expires_on-today;
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
