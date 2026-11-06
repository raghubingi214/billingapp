-- Internal dispatch-time check. A queued job must carry the consent version.
-- Revocation, renewed consent, inactive customers and changed contacts invalidate
-- an old job. No delivery or job scheduling is enabled by this migration.
create function private.reminder_consent_is_current(p_organization_id uuid,p_customer_id uuid,p_channel text,p_consent_version integer)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.customer_reminder_consent c
  join public.customers customer on customer.id=c.customer_id and customer.organization_id=c.organization_id
  where c.organization_id=p_organization_id and c.customer_id=p_customer_id
   and c.channel=p_channel and c.allowed and c.version=p_consent_version and customer.active
   and c.recipient=case when c.channel='email' then lower(trim(customer.email)) else trim(customer.phone) end
 );
$$;
revoke all on function private.reminder_consent_is_current(uuid,uuid,text,integer) from public,anon,authenticated;
