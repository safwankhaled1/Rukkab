create extension if not exists pg_cron with schema pg_catalog;
-- 10-second ticks respect 30-second dispatch leases without trusting a user's app to stay open.
select cron.schedule('rukkab-dispatch','10 seconds','select public.process_dispatch()');
