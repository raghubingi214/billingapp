-- Queue only. Delivery requires configured providers and fresh dispatch checks.
create table public.customer_reminder_jobs (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 customer_id uuid not null,
 invoice_id uuid not null,
 channel text not null check(channel in ('email','sms','whatsapp')),
 consent_version integer not null check(consent_version>0),
 recipient text not null,
 balance_snapshot numeric(18,2) not null check(balance_snapshot>0),
 state text not null default 'queued' check(state in ('queued','processing','delivered','failed','cancelled')),
 requested_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 foreign key(customer_id,organization_id) references public.customers(id,organization_id),
 foreign key(invoice_id,organization_id) references public.sales_invoices(id,organization_id)
);
create index reminder_jobs_cooldown_idx on public.customer_reminder_jobs(organization_id,customer_id,channel,created_at desc);
create index reminder_jobs_invoice_idx on public.customer_reminder_jobs(invoice_id,organization_id);
create index reminder_jobs_actor_idx on public.customer_reminder_jobs(requested_by);
alter table public.customer_reminder_jobs enable row level security;
revoke all on public.customer_reminder_jobs from public,anon,authenticated;
grant select on public.customer_reminder_jobs to authenticated;
create policy reminder_jobs_finance_read on public.customer_reminder_jobs for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));

create function public.queue_customer_reminder(p_request_id uuid,p_organization_id uuid,p_invoice_id uuid,p_channel text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare invoice public.sales_invoices%rowtype;consent public.customer_reminder_consent%rowtype;
 payload jsonb;reply jsonb;balance numeric;job uuid:=gen_random_uuid();begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('org',p_organization_id,'invoice',p_invoice_id,'channel',p_channel);
 reply:=private.replay('customer_reminder',p_request_id,payload);
 if reply is not null then return reply;end if;
 if p_channel is null or p_channel not in ('email','sms','whatsapp') then raise exception 'INVALID_REMINDER_CHANNEL';end if;
 select * into invoice from public.sales_invoices where id=p_invoice_id and organization_id=p_organization_id;
 if not found or invoice.customer_id is null then raise exception 'REMINDER_INVOICE_UNAVAILABLE';end if;
 if invoice.due_date>=(now() at time zone 'Asia/Kolkata')::date then raise exception 'INVOICE_NOT_OVERDUE';end if;
 balance:=private.invoice_outstanding(p_organization_id,p_invoice_id);
 if balance<=0 then raise exception 'INVOICE_ALREADY_SETTLED';end if;
 select * into consent from public.customer_reminder_consent where organization_id=p_organization_id and customer_id=invoice.customer_id and channel=p_channel;
 if not found or not private.reminder_consent_is_current(p_organization_id,invoice.customer_id,p_channel,consent.version) then raise exception 'REMINDER_CONSENT_REQUIRED';end if;
 if exists(select 1 from public.customer_reminder_jobs where organization_id=p_organization_id and customer_id=invoice.customer_id and channel=p_channel and created_at>now()-interval '24 hours') then raise exception 'REMINDER_COOLDOWN';end if;
 insert into public.customer_reminder_jobs(id,organization_id,customer_id,invoice_id,channel,consent_version,recipient,balance_snapshot,requested_by)
 values(job,p_organization_id,invoice.customer_id,p_invoice_id,p_channel,consent.version,consent.recipient,balance,auth.uid());
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'reminder.queued','customer_reminder_jobs',job,jsonb_build_object('invoice_id',p_invoice_id,'channel',p_channel,'consent_version',consent.version),p_request_id);
 reply:=jsonb_build_object('id',job,'state','queued');
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'customer_reminder',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.queue_customer_reminder(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.queue_customer_reminder(uuid,uuid,uuid,text) to authenticated;
