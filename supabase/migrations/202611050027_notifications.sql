create table public.notification_outbox(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 event_key text not null,event_type text not null,entity_type text not null,entity_id uuid not null,
 state text not null default 'queued' check(state in ('queued','sending','delivered','failed')),
 attempts integer not null default 0,next_attempt_at timestamptz not null default now(),
 created_at timestamptz not null default now(),unique(organization_id,event_key)
);
create index notification_outbox_due on public.notification_outbox(state,next_attempt_at);
create index notification_outbox_org on public.notification_outbox(organization_id);
create table public.notifications(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 recipient_user_id uuid not null references auth.users(id),event_key text not null,
 type text not null,title text not null,body text not null,entity_type text not null,entity_id uuid not null,
 read_at timestamptz,created_at timestamptz not null default now(),
 unique(organization_id,event_key,recipient_user_id)
);
create index notification_recipient_time on public.notifications(recipient_user_id,created_at desc);
create index notification_recipient_unread on public.notifications(recipient_user_id,read_at);
create index notification_org on public.notifications(organization_id);
alter table public.notifications enable row level security;
alter table public.notification_outbox enable row level security;
revoke all on public.notifications,public.notification_outbox from public,anon,authenticated;
grant select on public.notifications to authenticated;
create policy notification_recipient_read on public.notifications for select to authenticated
 using(recipient_user_id=(select auth.uid()) and organization_id in(select private.my_organization_ids()));
create function private.notify_posted_event() returns trigger language plpgsql security definer set search_path='' as $$
declare event text;title text;key text;
begin
 event:=case tg_table_name when 'sales_invoices' then 'INVOICE_ISSUED' when 'payments' then 'PAYMENT_RECEIVED'
 when 'purchases' then 'PURCHASE_RECEIVED' when 'sales_returns' then 'SALE_RETURNED' else 'REFUND_RECORDED' end;
 title:=case tg_table_name when 'sales_invoices' then 'Invoice issued' when 'payments' then 'Customer receipt recorded'
 when 'purchases' then 'Purchase received' when 'sales_returns' then 'Sales return posted' else 'Customer refund recorded' end;
 key:=tg_table_name||':'||new.id::text;
 insert into public.notification_outbox(organization_id,event_key,event_type,entity_type,entity_id)
 values(new.organization_id,key,event,tg_table_name,new.id) on conflict do nothing;
 insert into public.notifications(organization_id,recipient_user_id,event_key,type,title,body,entity_type,entity_id)
 select new.organization_id,m.user_id,key,event,title,'Open the business record for details.',tg_table_name,new.id
 from public.organization_members m where m.organization_id=new.organization_id and m.status='active'
 and (m.role in ('owner','manager') or m.user_id=new.created_by) on conflict do nothing;
 return new;
end $$;
revoke all on function private.notify_posted_event() from public,anon,authenticated;
create trigger notify_sale after insert on public.sales_invoices for each row execute function private.notify_posted_event();
create trigger notify_receipt after insert on public.payments for each row execute function private.notify_posted_event();
create trigger notify_purchase after insert on public.purchases for each row execute function private.notify_posted_event();
create trigger notify_return after insert on public.sales_returns for each row execute function private.notify_posted_event();
create trigger notify_refund after insert on public.sales_refunds for each row execute function private.notify_posted_event();
create function public.mark_notification_read(p_organization_id uuid,p_notification_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.has_role(p_organization_id,array['owner','manager','cashier','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 update public.notifications set read_at=coalesce(read_at,now())
 where id=p_notification_id and organization_id=p_organization_id and recipient_user_id=auth.uid();
 if not found then raise exception using errcode='42501',message='NOTIFICATION_NOT_FOUND';end if;
end $$;
revoke all on function public.mark_notification_read(uuid,uuid) from public,anon;
grant execute on function public.mark_notification_read(uuid,uuid) to authenticated;
