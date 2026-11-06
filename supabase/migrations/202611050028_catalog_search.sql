create function public.search_products(p_organization_id uuid,p_query text default '',p_archived boolean default false,p_offset integer default 0)
returns setof public.products language sql stable security invoker set search_path='' as $$
 select p.* from public.products p where p.organization_id=p_organization_id and p.active=not p_archived
 and position(lower(left(coalesce(p_query,''),200)) in lower(p.name||' '||coalesce(p.sku,'')||' '||coalesce(p.barcode,'')))>0
 order by p.name,p.id limit 50 offset greatest(0,least(coalesce(p_offset,0),1000000));
$$;
revoke all on function public.search_products(uuid,text,boolean,integer) from public,anon;
grant execute on function public.search_products(uuid,text,boolean,integer) to authenticated;
