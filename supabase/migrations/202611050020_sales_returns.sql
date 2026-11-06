create table public.sales_returns(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 original_invoice_id uuid not null,credit_note_number text not null,return_date date not null,
 reason text not null check(length(trim(reason)) between 3 and 500),
 total numeric(18,2) not null check(total>0),created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),unique(id,organization_id),unique(organization_id,credit_note_number),
 foreign key(original_invoice_id,organization_id) references public.sales_invoices(id,organization_id)
);
alter table public.sales_invoice_items add constraint invoice_item_tenant_key unique(id,organization_id);
create table public.sales_return_items(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 return_id uuid not null,original_invoice_item_id uuid not null,qty numeric(18,3) not null check(qty>0),
 taxable_value numeric(18,2) not null,cgst numeric(18,2) not null,sgst numeric(18,2) not null,igst numeric(18,2) not null,
 total numeric(18,2) not null check(total=taxable_value+cgst+sgst+igst),restock boolean not null,
 foreign key(return_id,organization_id) references public.sales_returns(id,organization_id),
 foreign key(original_invoice_item_id,organization_id) references public.sales_invoice_items(id,organization_id),
 unique(return_id,original_invoice_item_id)
);
create index returns_invoice on public.sales_returns(original_invoice_id,organization_id);
create index returns_org_date on public.sales_returns(organization_id,return_date);
create index returns_actor on public.sales_returns(created_by);
create index return_items_parent on public.sales_return_items(return_id,organization_id);
create index return_items_original on public.sales_return_items(original_invoice_item_id,organization_id);
create index return_items_org on public.sales_return_items(organization_id);
alter table public.sales_returns enable row level security;
alter table public.sales_return_items enable row level security;
revoke all on public.sales_returns,public.sales_return_items from public,anon,authenticated;
grant select on public.sales_returns,public.sales_return_items to authenticated;
create policy return_finance_read on public.sales_returns for select to authenticated using(private.has_role(organization_id,array['owner','manager','accountant']));
create policy return_line_finance_read on public.sales_return_items for select to authenticated using(private.has_role(organization_id,array['owner','manager','accountant']));
create function public.return_sale(p_request_id uuid,p_organization_id uuid,p_invoice_id uuid,p_reason text,p_items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare invoice public.sales_invoices%rowtype;original public.sales_invoice_items%rowtype;
 payload jsonb;reply jsonb;item jsonb;previous record;quantity numeric;net numeric;cgst numeric;sgst numeric;igst numeric;
 lines jsonb:='[]';line jsonb;total numeric:=0;return_id uuid:=gen_random_uuid();restock boolean;balance public.stock_balances%rowtype;
 series public.invoice_series%rowtype;today date:=(now() at time zone 'Asia/Kolkata')::date;fy_start integer;fy text;number text;grouped record;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'invoice_id',p_invoice_id,'reason',p_reason,'items',p_items);
 reply:=private.replay('return_sale',p_request_id,payload);if reply is not null then return reply;end if;
 if p_reason is null or length(trim(p_reason)) not between 3 and 500 then raise exception 'REASON_REQUIRED';end if;
 select * into invoice from public.sales_invoices where id=p_invoice_id and organization_id=p_organization_id for update;
 if not found then raise exception 'INVOICE_NOT_FOUND';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'INVALID_RETURN_ITEMS';end if;
 if jsonb_array_length(p_items) not between 1 and 100 then raise exception 'INVALID_RETURN_ITEMS';end if;
 if (select count(distinct value->>'invoice_item_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then raise exception 'DUPLICATE_RETURN_LINE';end if;
 for item in select value from jsonb_array_elements(p_items) loop
 if coalesce(item->>'qty','') !~ '^[0-9]+([.][0-9]{1,3})?$' then raise exception 'INVALID_QUANTITY';end if;
 quantity:=(item->>'qty')::numeric;if quantity<=0 then raise exception 'INVALID_QUANTITY';end if;
 select * into original from public.sales_invoice_items where id=(item->>'invoice_item_id')::uuid and invoice_id=p_invoice_id and organization_id=p_organization_id;
 if not found then raise exception 'INVOICE_ITEM_NOT_FOUND';end if;
 select coalesce(sum(qty),0) as qty,coalesce(sum(taxable_value),0) as net,coalesce(sum(r.cgst),0) as cgst,
 coalesce(sum(r.sgst),0) as sgst,coalesce(sum(r.igst),0) as igst into previous
 from public.sales_return_items r where original_invoice_item_id=original.id and organization_id=p_organization_id;
 if quantity+previous.qty>original.qty then raise exception 'RETURN_EXCEEDS_SOLD';end if;
 net:=round(original.taxable_value*(previous.qty+quantity)/original.qty,2)-previous.net;
 cgst:=round(original.cgst*(previous.qty+quantity)/original.qty,2)-previous.cgst;
 sgst:=round(original.sgst*(previous.qty+quantity)/original.qty,2)-previous.sgst;
 igst:=round(original.igst*(previous.qty+quantity)/original.qty,2)-previous.igst;
 restock:=coalesce((item->>'restock')::boolean,false);
 if restock and original.snapshot->>'type'<>'product' then raise exception 'SERVICE_HAS_NO_STOCK';end if;
 line:=jsonb_build_object('item_id',original.id,'product_id',original.product_id,'qty',quantity,'taxable_value',net,
 'cgst',cgst,'sgst',sgst,'igst',igst,'total',net+cgst+sgst+igst,'restock',restock);
 lines:=lines||jsonb_build_array(line);total:=total+net+cgst+sgst+igst;
 end loop;
 fy_start:=extract(year from today)::integer;if extract(month from today)<4 then fy_start:=fy_start-1;end if;
 fy:=right(fy_start::text,2)||'-'||right((fy_start+1)::text,2);
 insert into public.invoice_series(organization_id,financial_year,doc_type,prefix) values(p_organization_id,fy,'credit_note','CN') on conflict do nothing;
 select * into series from public.invoice_series where organization_id=p_organization_id and financial_year=fy and doc_type='credit_note' and prefix='CN' for update;
 if series.next_seq>=999999 then raise exception 'SERIES_EXHAUSTED';end if;
 number:='CN/'||replace(fy,'-','')||'/'||lpad(series.next_seq::text,6,'0');
 insert into public.sales_returns(id,organization_id,original_invoice_id,credit_note_number,return_date,reason,total,created_by)
 values(return_id,p_organization_id,p_invoice_id,number,today,trim(p_reason),total,auth.uid());
 for line in select value from jsonb_array_elements(lines) loop
 insert into public.sales_return_items(organization_id,return_id,original_invoice_item_id,qty,taxable_value,cgst,sgst,igst,total,restock)
 values(p_organization_id,return_id,(line->>'item_id')::uuid,(line->>'qty')::numeric,(line->>'taxable_value')::numeric,
 (line->>'cgst')::numeric,(line->>'sgst')::numeric,(line->>'igst')::numeric,(line->>'total')::numeric,(line->>'restock')::boolean);
 end loop;
 for grouped in select (value->>'product_id')::uuid as product_id,sum((value->>'qty')::numeric) as qty
 from jsonb_array_elements(lines) where (value->>'restock')::boolean group by value->>'product_id' loop
 select * into balance from public.stock_balances where organization_id=p_organization_id and outlet_id=invoice.outlet_id and product_id=grouped.product_id for update;
 insert into public.stock_movements(organization_id,outlet_id,product_id,movement_type,signed_qty,before_qty,after_qty,reason,source_id,request_id,created_by)
 values(p_organization_id,invoice.outlet_id,grouped.product_id,'sale_return',grouped.qty,balance.quantity_on_hand,
 balance.quantity_on_hand+grouped.qty,trim(p_reason),return_id,p_request_id,auth.uid());
 update public.stock_balances set quantity_on_hand=quantity_on_hand+grouped.qty,version=version+1,updated_at=now()
 where organization_id=p_organization_id and outlet_id=invoice.outlet_id and product_id=grouped.product_id;
 end loop;
 update public.invoice_series set next_seq=next_seq+1 where id=series.id;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'sale.returned','sales_returns',return_id,jsonb_build_object('total',total),p_request_id);
 reply:=jsonb_build_object('return_id',return_id,'credit_note_number',number,'total',total);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'return_sale',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.return_sale(uuid,uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.return_sale(uuid,uuid,uuid,text,jsonb) to authenticated;
