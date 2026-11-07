create function private.stock_valuation_snapshot(p_organization_id uuid,p_offset integer,p_limit integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  report jsonb;
begin
  if not private.has_role(p_organization_id,array['owner','manager','accountant']) then
    raise exception using errcode='42501',message='ACCESS_DENIED';
  end if;
  if p_offset is null or p_offset<0 or p_offset>100000 then
    raise exception 'INVALID_OFFSET';
  end if;
  with positions as (
    select b.product_id,b.outlet_id,p.name,p.sku,p.unit,o.name as outlet,
      b.quantity_on_hand as quantity,p.reorder_level,
      b.quantity_on_hand<=p.reorder_level as low_stock,
      nullif(b.average_unit_cost,0) as unit_cost,
      round(b.quantity_on_hand*nullif(b.average_unit_cost,0),2) as estimate
    from public.stock_balances b
    join public.products p on p.id=b.product_id and p.organization_id=b.organization_id
    join public.outlets o on o.id=b.outlet_id and o.organization_id=b.organization_id
    where b.organization_id=p_organization_id and b.quantity_on_hand>0
  ), page as (
    select * from positions order by name,product_id,outlet_id limit p_limit offset p_offset
  )
  select jsonb_build_object(
    'generated_at',now(),'count',count(*),
    'uncosted_count',count(*) filter (where unit_cost is null),
    'low_stock_count',count(*) filter (where low_stock),
    'total',coalesce(sum(estimate),0),
    'rows',(select coalesce(jsonb_agg(to_jsonb(page) order by name,product_id,outlet_id),'[]'::jsonb) from page)
  ) into report from positions;
  return report;
end $$;

revoke all on function private.stock_valuation_snapshot(uuid,integer,integer) from public,anon,authenticated;

create or replace function public.stock_valuation(p_organization_id uuid, p_offset integer default 0)
returns jsonb language sql stable security definer set search_path='' as $$
  select private.stock_valuation_snapshot(p_organization_id,p_offset,50);
$$;

create function public.create_stock_valuation_export(p_request_id uuid,p_organization_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  payload jsonb := jsonb_build_object('organization_id',p_organization_id);
  reply jsonb;
  export_id uuid := gen_random_uuid();
  report_date date;
begin
  if not private.has_role(p_organization_id,array['owner','manager','accountant']) then
    raise exception using errcode='42501',message='ACCESS_DENIED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':stock_valuation_export:'||p_request_id::text,0));
  if not private.has_role(p_organization_id,array['owner','manager','accountant']) then
    raise exception using errcode='42501',message='ACCESS_DENIED';
  end if;
  reply := private.replay('stock_valuation_export',p_request_id,payload);
  if reply is not null then return reply; end if;

  reply := private.stock_valuation_snapshot(p_organization_id,0,50000);
  if (reply->>'count')::bigint>50000 then
    raise exception 'EXPORT_REQUIRES_BACKGROUND_JOB';
  end if;
  report_date := (now() at time zone 'Asia/Kolkata')::date;
  reply := reply||jsonb_build_object('export_id',export_id,'as_of',report_date);
  insert into public.report_exports(id,organization_id,created_by,kind,from_date,to_date,payload)
  values(export_id,p_organization_id,auth.uid(),'stock_valuation',report_date,report_date,reply);
  insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
  values(p_organization_id,auth.uid(),'report.exported','report_exports',export_id,
    jsonb_build_object('kind','stock_valuation','as_of',report_date,'count',reply->'count'),p_request_id);
  insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
  values(auth.uid(),'stock_valuation_export',p_request_id,payload,reply);
  return reply;
end $$;

revoke all on function public.create_stock_valuation_export(uuid,uuid) from public,anon;
grant execute on function public.create_stock_valuation_export(uuid,uuid) to authenticated;
