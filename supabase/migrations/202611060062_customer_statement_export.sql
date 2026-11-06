-- Statement exports use the same immutable snapshot store as financial reports.
create policy statement_export_read on public.report_exports for select to authenticated
 using(kind='customer_statement' and private.has_role(organization_id,array['owner','manager','accountant']));

create function public.create_customer_statement_export(
 p_request_id uuid,p_organization_id uuid,p_customer_id uuid,p_from date,p_to date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;export_id uuid:=gen_random_uuid();customer_name text;
begin
 if not private.has_role(p_organization_id,array['owner','manager','accountant']) then
  raise exception using errcode='42501',message='ACCESS_DENIED';
 end if;
 if p_request_id is null or p_from is null or p_to is null or p_to<p_from then
  raise exception 'INVALID_STATEMENT_REQUEST';
 end if;
 -- Serializes matching export retries and the organization's financial commands.
 perform 1 from public.organizations where id=p_organization_id for update;
 payload:=jsonb_build_object('organization_id',p_organization_id,'customer_id',p_customer_id,'from',p_from,'to',p_to);
 reply:=private.replay('customer_statement_export',p_request_id,payload);
 if reply is not null then return reply;end if;
 select c.name into customer_name from public.customers c where c.id=p_customer_id and c.organization_id=p_organization_id;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 -- Totals, opening balance and every exported row share one SQL snapshot.
 with entries as (
  select i.id,i.invoice_date as date,i.issued_at as created_at,'invoice'::text as type,
   i.invoice_number as reference,i.grand_total as debit,0::numeric as credit,i.grand_total as delta
  from public.sales_invoices i where i.organization_id=p_organization_id and i.customer_id=p_customer_id
  union all
  select r.id,r.return_date,r.created_at,'credit_note',r.credit_note_number,0,r.total,-r.total
  from public.sales_returns r join public.sales_invoices i on i.id=r.original_invoice_id and i.organization_id=r.organization_id
  where r.organization_id=p_organization_id and i.customer_id=p_customer_id
  union all
  select r.id,r.refund_date,r.created_at,'refund',coalesce(r.reference,r.method),r.amount,0,r.amount
  from public.sales_refunds r where r.organization_id=p_organization_id and r.customer_id=p_customer_id
  union all
  select p.id,p.payment_date,p.created_at,'receipt',coalesce(p.reference,p.method),0,p.amount,-p.amount
  from public.payments p where p.organization_id=p_organization_id and p.customer_id=p_customer_id
 ), running as (
  select *,sum(delta) over(order by date,created_at,id rows unbounded preceding) as balance
  from entries where date<=p_to
 ), bounded as (
  select * from running where date>=p_from order by date,created_at,id limit 50001
 )
 select jsonb_build_object(
  'export_id',export_id,'customer_id',p_customer_id,'customer_name',customer_name,
  'from',p_from,'to',p_to,'currency','INR','generated_at',now(),
  'opening_balance',coalesce((select sum(delta) from entries where date<p_from),0),
  'closing_balance',coalesce((select sum(delta) from entries where date<=p_to),0),
  'entries',coalesce((select jsonb_agg(to_jsonb(b) order by date,created_at,id) from bounded b),'[]'::jsonb)
 ) into reply;
 if jsonb_array_length(reply->'entries')>50000 then raise exception 'EXPORT_REQUIRES_BACKGROUND_JOB';end if;
 reply:=reply||jsonb_build_object('count',jsonb_array_length(reply->'entries'));
 insert into public.report_exports(id,organization_id,created_by,kind,from_date,to_date,payload)
 values(export_id,p_organization_id,auth.uid(),'customer_statement',p_from,p_to,reply);
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'customer.statement_exported','report_exports',export_id,
  jsonb_build_object('customer_id',p_customer_id,'from',p_from,'to',p_to,'count',reply->'count'),p_request_id);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'customer_statement_export',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.create_customer_statement_export(uuid,uuid,uuid,date,date) from public,anon;
grant execute on function public.create_customer_statement_export(uuid,uuid,uuid,date,date) to authenticated;
