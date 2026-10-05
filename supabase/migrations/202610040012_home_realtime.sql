-- Approval, permit and profile changes must reach clients without a manual refresh.
-- Existing row-level policies govern delivery; no private document body is published.
alter publication supabase_realtime add table
  public.profiles, public.vehicles, public.documents, public.vehicle_routes,
  public.routes, public.stops, public.violations, public.appeals;
