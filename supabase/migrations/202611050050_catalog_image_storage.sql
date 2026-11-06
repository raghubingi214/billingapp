insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('catalog-images','catalog-images',false,3145728,array['image/jpeg','image/png','image/webp']);

-- Paths are organization UUID/product UUID/asset UUID.extension. Missing or
-- malformed IDs return false rather than raising a UUID cast error.
create function private.can_access_catalog_image(p_path text,p_write boolean)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare org uuid;product uuid;begin
 if p_path is null or p_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|png|webp)$' then return false;end if;
 begin
  org:=split_part(p_path,'/',1)::uuid;
  product:=split_part(p_path,'/',2)::uuid;
  perform split_part(split_part(p_path,'/',3),'.',1)::uuid;
 exception when invalid_text_representation then return false;end;
 if not private.has_role(org,case when p_write then array['owner','manager'] else array['owner','manager','cashier','accountant'] end) then return false;end if;
 return exists(select 1 from public.products where id=product and organization_id=org);
end $$;
revoke all on function private.can_access_catalog_image(text,boolean) from public,anon;
grant execute on function private.can_access_catalog_image(text,boolean) to authenticated;
create policy catalog_image_read on storage.objects for select to authenticated
 using(bucket_id='catalog-images' and private.can_access_catalog_image(name,false));
create policy catalog_image_insert on storage.objects for insert to authenticated
 with check(bucket_id='catalog-images' and private.can_access_catalog_image(name,true));
-- Immutable object paths: replacement uploads use a fresh asset UUID.
create policy catalog_image_delete on storage.objects for delete to authenticated
 using(bucket_id='catalog-images' and private.can_access_catalog_image(name,true));
