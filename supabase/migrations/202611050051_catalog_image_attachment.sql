alter table public.products add column image_path text;
create function public.set_product_image(p_request_id uuid,p_organization_id uuid,p_product_id uuid,p_version integer,p_path text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare product public.products%rowtype;payload jsonb;reply jsonb;begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'product_id',p_product_id,'version',p_version,'path',p_path);
 reply:=private.replay('product_image',p_request_id,payload);
 if reply is not null then return reply;end if;
 select * into product from public.products where id=p_product_id and organization_id=p_organization_id for update;
 if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if p_version is null or product.version<>p_version then raise exception 'PRODUCT_VERSION_CONFLICT';end if;
 if p_path is not null then
  if not private.can_access_catalog_image(p_path,true)
   or split_part(p_path,'/',1)<>p_organization_id::text or split_part(p_path,'/',2)<>p_product_id::text then raise exception 'INVALID_IMAGE_PATH';end if;
  perform 1 from storage.objects where bucket_id='catalog-images' and name=p_path for share;
  if not found then raise exception 'IMAGE_UPLOAD_REQUIRED';end if;
 end if;
 update public.products set image_path=p_path,version=version+1,updated_at=now() where id=p_product_id;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
 values(p_organization_id,auth.uid(),'product.image_changed','products',p_product_id,jsonb_build_object('image_path',product.image_path),jsonb_build_object('image_path',p_path),p_request_id);
 reply:=jsonb_build_object('id',p_product_id,'version',product.version+1,'image_path',p_path);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'product_image',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.set_product_image(uuid,uuid,uuid,integer,text) from public,anon;
grant execute on function public.set_product_image(uuid,uuid,uuid,integer,text) to authenticated;
