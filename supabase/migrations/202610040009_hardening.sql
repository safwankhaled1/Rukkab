create function public.viewer_enabled() returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and not disabled)
$$;
revoke execute on function public.viewer_enabled() from public,anon;
grant execute on function public.viewer_enabled() to authenticated,service_role;
-- Disabled accounts retain access to their own status, but lose all operational data.
alter policy profiles_read on public.profiles using(id=auth.uid() or (public.viewer_enabled() and (public.is_staff() or public.driver_can_read_rider(id))));
do $$ declare policy record;begin
 for policy in select policyname,tablename,qual from pg_catalog.pg_policies where schemaname='public' and tablename<>'profiles' loop
  execute format('alter policy %I on public.%I using (public.viewer_enabled() and (%s))',policy.policyname,policy.tablename,policy.qual);
 end loop;
end $$;
alter policy document_download on storage.objects using(bucket_id='driver-documents' and public.viewer_enabled() and (public.is_staff() or (storage.foldername(name))[1]=auth.uid()::text));
alter policy document_upload on storage.objects with check(bucket_id='driver-documents' and public.viewer_enabled() and (storage.foldername(name))[1]=auth.uid()::text
 and exists(select 1 from public.vehicles where id::text=(storage.foldername(name))[2] and driver_id=auth.uid()));
-- Prevent internal notification helpers from ever becoming callable through future default grants.
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public revoke all on tables from anon,authenticated;
