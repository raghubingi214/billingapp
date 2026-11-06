create function private.cancel_stale_customer_reminders()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.customer_reminder_jobs set state='cancelled'
 where organization_id=new.organization_id and customer_id=new.customer_id
 and channel=new.channel and state='queued' and consent_version<>new.version;
 return new;
end $$;
revoke all on function private.cancel_stale_customer_reminders() from public,anon,authenticated;
create trigger cancel_stale_reminders after update on public.customer_reminder_consent
for each row when(old.version is distinct from new.version)
execute function private.cancel_stale_customer_reminders();
