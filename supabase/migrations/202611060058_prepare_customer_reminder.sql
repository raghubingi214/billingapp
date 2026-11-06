-- Internal preparation only; no external delivery or delivered-state claim.
create function private.prepare_customer_reminder(p_job_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare org uuid;job public.customer_reminder_jobs%rowtype;balance numeric;eligible boolean;begin
 select organization_id into org from public.customer_reminder_jobs where id=p_job_id;
 if not found then return null;end if;
 perform 1 from public.organizations where id=org for update;
 select * into job from public.customer_reminder_jobs where id=p_job_id for update;
 if job.state<>'queued' then return null;end if;
 balance:=private.invoice_outstanding(org,job.invoice_id);
 eligible:=exists(select 1 from public.organizations where id=org and status='active')
 and exists(select 1 from public.organization_members where organization_id=org and user_id=job.requested_by and status='active' and role in ('owner','manager','accountant'))
 and exists(select 1 from public.sales_invoices where id=job.invoice_id and organization_id=org and customer_id=job.customer_id and due_date<(now() at time zone 'Asia/Kolkata')::date)
 and private.reminder_consent_is_current(org,job.customer_id,job.channel,job.consent_version)
 and exists(select 1 from public.customer_reminder_consent where organization_id=org and customer_id=job.customer_id and channel=job.channel and recipient=job.recipient)
 and coalesce(balance,0)>0;
 if not eligible then
  update public.customer_reminder_jobs set state='cancelled' where id=p_job_id;
  return null;
 end if;
 return jsonb_build_object('job_id',job.id,'organization_id',org,'invoice_id',job.invoice_id,'channel',job.channel,'recipient',job.recipient,'consent_version',job.consent_version,'balance_due',balance);
end $$;
revoke all on function private.prepare_customer_reminder(uuid) from public,anon,authenticated;
