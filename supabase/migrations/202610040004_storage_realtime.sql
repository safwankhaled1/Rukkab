insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('driver-documents','driver-documents',false,10485760,array['image/jpeg','image/png','application/pdf']) on conflict(id) do nothing;
create policy document_upload on storage.objects for insert to authenticated with check(
 bucket_id='driver-documents' and (storage.foldername(name))[1]=auth.uid()::text
 and exists(select 1 from public.vehicles where id::text=(storage.foldername(name))[2] and driver_id=auth.uid()));
create policy document_download on storage.objects for select to authenticated using(
 bucket_id='driver-documents' and (public.is_staff() or (storage.foldername(name))[1]=auth.uid()::text));
-- No client overwrite/delete: upload a fresh UUID filename, then submit it for re-review.
alter publication supabase_realtime add table public.bookings,public.trips,public.notifications,public.vehicle_locations,public.ride_requests,public.offers;
