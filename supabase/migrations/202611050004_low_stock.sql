create function public.inventory_positions(p_organization_id uuid,p_outlet_id uuid,p_offset integer default 0,p_low_only boolean default false)
returns table(product_id uuid,name text,unit text,quantity_on_hand numeric,reorder_level numeric,version integer)
language sql stable security invoker set search_path='' as $$
 select p.id,p.name,p.unit,coalesce(b.quantity_on_hand,0),p.reorder_level,coalesce(b.version,1)
 from public.products p
 join public.outlets o on o.id=p_outlet_id and o.organization_id=p.organization_id and o.active
 left join public.stock_balances b on b.organization_id=p.organization_id and b.product_id=p.id and b.outlet_id=o.id
 where p.organization_id=p_organization_id and p.active and p.type='product'
 and (not p_low_only or coalesce(b.quantity_on_hand,0)<=p.reorder_level)
 order by p.name,p.id limit 50 offset greatest(0,least(coalesce(p_offset,0),1000000));
$$;
revoke all on function public.inventory_positions(uuid,uuid,integer,boolean) from public,anon;
grant execute on function public.inventory_positions(uuid,uuid,integer,boolean) to authenticated;
