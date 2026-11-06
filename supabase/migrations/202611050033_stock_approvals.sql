create table public.stock_adjustment_requests(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 outlet_id uuid not null,product_id uuid not null,expected_version integer not null,
 counted_qty numeric(18,3) not null check(counted_qty>=0),reason text not null check(length(trim(reason)) between 3 and 500),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id),reviewed_at timestamptz,
 foreign key(outlet_id,organization_id) references public.outlets(id,organization_id),
 foreign key(product_id,organization_id) references public.products(id,organization_id)
);
create index stock_requests_org_status on public.stock_adjustment_requests(organization_id,status,created_at);
create index stock_requests_outlet on public.stock_adjustment_requests(outlet_id,organization_id);
create index stock_requests_product on public.stock_adjustment_requests(product_id,organization_id);
create index stock_requests_creator on public.stock_adjustment_requests(created_by);
create index stock_requests_reviewer on public.stock_adjustment_requests(reviewed_by);
alter table public.stock_adjustment_requests enable row level security;
revoke all on public.stock_adjustment_requests from public,anon,authenticated;
grant select on public.stock_adjustment_requests to authenticated;
create policy stock_request_read on public.stock_adjustment_requests for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create function public.request_stock_adjustment(p_request_id uuid,p_organization_id uuid,p_outlet_id uuid,
 p_product_id uuid,p_expected_version integer,p_counted_qty text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;request_id uuid:=gen_random_uuid();balance_version integer;event_key text;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'outlet_id',p_outlet_id,'product_id',p_product_id,
 'expected_version',p_expected_version,'counted_qty',p_counted_qty,'reason',p_reason);
 reply:=private.replay('request_stock_adjustment',p_request_id,payload);if reply is not null then return reply;end if;
 if p_counted_qty is null or p_counted_qty !~ '^[0-9]+([.][0-9]{1,3})?$' then raise exception 'INVALID_QUANTITY';end if;
 if p_reason is null or length(trim(p_reason)) not between 3 and 500 then raise exception 'REASON_REQUIRED';end if;
 perform 1 from public.products where id=p_product_id and organization_id=p_organization_id and active and type='product';
 if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 perform 1 from public.outlets where id=p_outlet_id and organization_id=p_organization_id and active;
 if not found then raise exception 'OUTLET_NOT_FOUND';end if;
 select version into balance_version from public.stock_balances where organization_id=p_organization_id and outlet_id=p_outlet_id and product_id=p_product_id;
 if p_expected_version is null or p_expected_version<>coalesce(balance_version,1) then raise exception 'STOCK_VERSION_CONFLICT';end if;
 insert into public.stock_adjustment_requests(id,organization_id,outlet_id,product_id,expected_version,counted_qty,reason,created_by)
 values(request_id,p_organization_id,p_outlet_id,p_product_id,p_expected_version,p_counted_qty::numeric,trim(p_reason),auth.uid());
 event_key:='stock_adjustment_request:'||request_id::text;
 insert into public.notification_outbox(organization_id,event_key,event_type,entity_type,entity_id)
 values(p_organization_id,event_key,'STOCK_ADJUST_APPROVAL','stock_adjustment_requests',request_id);
 insert into public.notifications(organization_id,recipient_user_id,event_key,type,title,body,entity_type,entity_id)
 select p_organization_id,user_id,event_key,'STOCK_ADJUST_APPROVAL','Stock count needs approval',
 'Review the requested stock change.','stock_adjustment_requests',request_id
 from public.organization_members where organization_id=p_organization_id and role='owner' and status='active';
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'stock.adjustment_requested','stock_adjustment_requests',request_id,payload,p_request_id);
 reply:=jsonb_build_object('adjustment_request_id',request_id,'status','pending');
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'request_stock_adjustment',p_request_id,payload,reply);
 return reply;
end $$;
create function public.review_stock_adjustment(p_request_id uuid,p_organization_id uuid,p_adjustment_id uuid,p_approve boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;adjustment public.stock_adjustment_requests%rowtype;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'adjustment_id',p_adjustment_id,'approve',p_approve);
 reply:=private.replay('review_stock_adjustment',p_request_id,payload);if reply is not null then return reply;end if;
 if p_approve is null then raise exception 'DECISION_REQUIRED';end if;
 select * into adjustment from public.stock_adjustment_requests where id=p_adjustment_id and organization_id=p_organization_id for update;
 if not found or adjustment.status<>'pending' then raise exception 'REQUEST_NOT_PENDING';end if;
 if p_approve then
 perform public.post_stock_count(md5('approved-stock:'||adjustment.id::text)::uuid,p_organization_id,
 adjustment.outlet_id,adjustment.product_id,adjustment.expected_version,adjustment.counted_qty::text,adjustment.reason);
 end if;
 update public.stock_adjustment_requests set status=case when p_approve then 'approved' else 'rejected' end,
 reviewed_by=auth.uid(),reviewed_at=now() where id=adjustment.id;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'stock.adjustment_reviewed','stock_adjustment_requests',adjustment.id,payload,p_request_id);
 reply:=jsonb_build_object('adjustment_request_id',adjustment.id,'status',case when p_approve then 'approved' else 'rejected' end);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'review_stock_adjustment',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.request_stock_adjustment(uuid,uuid,uuid,uuid,integer,text,text) from public,anon;
revoke all on function public.review_stock_adjustment(uuid,uuid,uuid,boolean) from public,anon;
grant execute on function public.request_stock_adjustment(uuid,uuid,uuid,uuid,integer,text,text),
 public.review_stock_adjustment(uuid,uuid,uuid,boolean) to authenticated;
