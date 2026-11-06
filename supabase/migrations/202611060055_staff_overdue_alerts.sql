create function private.invoice_outstanding(p_org uuid,p_invoice uuid)
returns numeric language sql stable security definer set search_path='' as $$
 select greatest(0,i.grand_total
  -coalesce((select sum(a.amount) from public.payment_allocations a where a.organization_id=p_org and a.invoice_id=i.id),0)
  -coalesce((select sum(r.total) from public.sales_returns r where r.organization_id=p_org and r.original_invoice_id=i.id),0)
  +coalesce((select sum(r.amount) from public.sales_refunds r where r.organization_id=p_org and r.invoice_id=i.id),0))
 from public.sales_invoices i where i.id=p_invoice and i.organization_id=p_org;
$$;
revoke all on function private.invoice_outstanding(uuid,uuid) from public,anon,authenticated;
create index notification_outbox_entity_cooldown_idx on public.notification_outbox(organization_id,event_type,entity_id,created_at desc);

-- Trusted scheduler entry point; p_as_of permits deterministic backfill/testing.
-- No customer recipients or external provider calls occur here.
create function private.build_staff_overdue_alerts(p_org uuid,p_as_of date default (now() at time zone 'Asia/Kolkata')::date)
returns integer language plpgsql security definer set search_path='' as $$
declare invoice record;key text;created integer:=0;begin
 if p_as_of is null then raise exception 'INVALID_ALERT_DATE';end if;
 perform 1 from public.organizations where id=p_org and status='active' for update;
 if not found then return 0;end if;
 for invoice in select i.id from public.sales_invoices i
 where i.organization_id=p_org and i.due_date<p_as_of
 and private.invoice_outstanding(p_org,i.id)>0
 and not exists(select 1 from public.notification_outbox o where o.organization_id=p_org and o.event_type='INVOICE_OVERDUE' and o.entity_id=i.id and o.created_at>now()-interval '24 hours')
 order by i.due_date,i.id limit 500 loop
  key:='overdue:'||invoice.id::text||':'||p_as_of::text;
  insert into public.notification_outbox(organization_id,event_key,event_type,entity_type,entity_id)
  values(p_org,key,'INVOICE_OVERDUE','sales_invoices',invoice.id) on conflict do nothing;
  if not found then continue;end if;
  insert into public.notifications(organization_id,recipient_user_id,event_key,type,title,body,entity_type,entity_id)
  select p_org,m.user_id,key,'INVOICE_OVERDUE','Invoice overdue','Open the invoice to review the current balance.','sales_invoices',invoice.id
  from public.organization_members m where m.organization_id=p_org and m.status='active' and m.role in ('owner','manager','accountant') on conflict do nothing;
  created:=created+1;
 end loop;
 return created;
end $$;
revoke all on function private.build_staff_overdue_alerts(uuid,date) from public,anon,authenticated;
