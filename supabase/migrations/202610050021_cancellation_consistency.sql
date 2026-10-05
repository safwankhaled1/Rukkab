-- Keep a matched request consistent with its cancelled or no-show booking.
-- Pending dispatch refusals remain eligible for the next driver.
create function public.sync_cancelled_request() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.request_id is not null and old.state in ('confirmed','reschedule_pending')
  and new.state in ('cancelled','no_show') and new.state<>old.state then
  update public.ride_requests set state='cancelled' where id=new.request_id and state='booked';
 end if;
 return new;
end $$;
revoke all on function public.sync_cancelled_request() from public,anon,authenticated;
create trigger booking_request_terminal after update of state on public.bookings
 for each row execute function public.sync_cancelled_request();

-- Repair only terminal cancellations, preserving completed and still-live matches.
update public.ride_requests r set state='cancelled' where r.state='booked'
 and exists(select 1 from public.bookings b where b.request_id=r.id and b.state in ('cancelled','no_show'))
 and not exists(select 1 from public.bookings b where b.request_id=r.id and b.state in ('pending','confirmed','boarded','completed','reschedule_pending'));

create index audit_driver_cancellation_window on public.audit_log(actor_id,created_at)
 where action in ('trip.cancel','booking.cancel');
create index audit_driver_review_window on public.audit_log(entity_id,created_at)
 where action='driver.cancellation_review';

-- Three impactful driver cancellations in 30 days request staff review.
-- This is a review alert; the trigger never changes account permissions or suspensions.
create function public.review_driver_cancellations() returns trigger language plpgsql security definer set search_path='' as $$
declare driver uuid; vehicle uuid; full_name text; affected integer; cnt integer; staff record; notice jsonb;
begin
 if new.action='trip.cancel' then
  select v.driver_id,v.id into driver,vehicle from public.trips t join public.vehicles v on v.id=t.vehicle_id where t.id=new.entity_id;
  select count(*)::integer into affected from public.bookings where trip_id=new.entity_id and state='cancelled'
   and confirmed_at is not null and cancellation_reason='driver_cancelled';
 elsif new.action='booking.cancel' then
  select v.driver_id,v.id,case when b.state='cancelled' and b.confirmed_at is not null then 1 else 0 end
   into driver,vehicle,affected from public.bookings b join public.trips t on t.id=b.trip_id join public.vehicles v on v.id=t.vehicle_id where b.id=new.entity_id;
 else return new;
 end if;
 -- The actor comes from the private audit writer, never a client cancellation reason.
 if driver is null or driver is distinct from new.actor_id or coalesce(affected,0)=0 then return new; end if;
 -- Serialize only these review calculations, without taking a new profile row lock.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('driver-cancellation:'||driver::text,0));
 select count(*)::integer into cnt from public.audit_log a where a.actor_id=driver and a.created_at>=now()-interval '30 days'
  and (
   (a.action='trip.cancel' and exists(select 1 from public.trips t join public.vehicles v on v.id=t.vehicle_id
     where t.id=a.entity_id and v.driver_id=driver and exists(select 1 from public.bookings b where b.trip_id=t.id and b.state='cancelled' and b.confirmed_at is not null and b.cancellation_reason='driver_cancelled')))
   or (a.action='booking.cancel' and exists(select 1 from public.bookings b join public.trips t on t.id=b.trip_id join public.vehicles v on v.id=t.vehicle_id
     where b.id=a.entity_id and v.driver_id=driver and b.state='cancelled' and b.confirmed_at is not null))
  );
 if cnt<3 or exists(select 1 from public.audit_log where action='driver.cancellation_review' and entity_id=driver and created_at>=now()-interval '30 days') then return new; end if;
 select p.full_name into full_name from public.profiles p where p.id=driver;
 notice:=jsonb_build_object('driver_id',driver,'full_name',full_name,'count',cnt,'window_days',30,'vehicle_id',null);
 for staff in select id from public.profiles where role in ('owner','operator') and not disabled and (suspended_until is null or suspended_until<=now()) loop
  perform public.notify_user(staff.id,'driver.cancellation_review',notice::text);
 end loop;
 perform public.log_action('driver.cancellation_review',driver,notice);
 return new;
end $$;
revoke all on function public.review_driver_cancellations() from public,anon,authenticated;
create trigger driver_cancel_review after insert on public.audit_log for each row execute function public.review_driver_cancellations();
