create function public.admin_overview() returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
 if not public.is_staff() then raise exception 'ADMIN_MFA_REQUIRED'; end if;
 select jsonb_build_object(
  'riders',(select count(*) from public.profiles where role='rider'),
  'drivers',(select count(*) from public.profiles where role='driver'),
  'active_trips',(select count(*) from public.trips where state='active'),
  'pending_vehicles',(select count(*) from public.vehicles where not approved),
  'pending_appeals',(select count(*) from public.appeals where state='pending'),
  'expired_documents',(select count(*) from public.documents where expires_on<current_date),
  'today_bookings',(select count(*) from public.bookings where created_at>=date_trunc('day',now() at time zone 'Asia/Hebron') at time zone 'Asia/Hebron'),
  'week',(select jsonb_agg(jsonb_build_object('date',d.day::date,'count',(select count(*) from public.bookings b where (b.created_at at time zone 'Asia/Hebron')::date=d.day::date)))
    from generate_series((now() at time zone 'Asia/Hebron')::date-6,(now() at time zone 'Asia/Hebron')::date,interval '1 day') d(day))
 ) into result;return result;
end $$;
revoke execute on function public.admin_overview() from public,anon;
grant execute on function public.admin_overview() to authenticated,service_role;
