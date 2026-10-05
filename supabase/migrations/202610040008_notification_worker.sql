alter table public.notification_jobs add column claimed_until timestamptz;
create index notification_jobs_ready on public.notification_jobs(available_at) where delivered_at is null and attempts<5;
create function public.claim_notifications() returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
 with ready as (select id from public.notification_jobs where delivered_at is null and attempts<5 and available_at<=now()
  and (claimed_until is null or claimed_until<=now()) order by available_at for update skip locked limit 30),
 claimed as (update public.notification_jobs j set claimed_until=now()+interval '2 minutes',attempts=attempts+1 from ready where ready.id=j.id returning j.*)
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'attempts',c.attempts,'kind',n.kind,'body',n.body,'booking_id',n.booking_id,
 'language',p.language,'tokens',(select coalesce(jsonb_agg(token),'[]'::jsonb) from public.device_tokens where user_id=n.user_id))),'[]'::jsonb)
 into result from claimed c join public.notifications n on n.id=c.notification_id join public.profiles p on p.id=n.user_id;
 return result;
end $$;
create function public.finish_notification(jid uuid,success boolean,err text default null) returns void language sql security definer set search_path = '' as $$
 update public.notification_jobs set delivered_at=case when success then now() else null end,claimed_until=null,
 last_error=left(err,300),available_at=now()+make_interval(secs=>least(3600,30*power(2,attempts)::integer)) where id=jid
$$;
revoke execute on function public.claim_notifications(),public.finish_notification(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_notifications(),public.finish_notification(uuid,boolean,text) to service_role;
