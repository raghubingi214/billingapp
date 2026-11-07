create function public.stock_valuation(p_organization_id uuid,p_offset integer default 0)
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
    select * from positions order by name,product_id,outlet_id limit 50 offset p_offset
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

revoke all on function public.stock_valuation(uuid,integer) from public,anon;
grant execute on function public.stock_valuation(uuid,integer) to authenticated;
