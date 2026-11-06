set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ declare product public.products%rowtype;path text;req uuid:=gen_random_uuid();reply jsonb;begin
 select * into strict product from public.products;
 path:=product.organization_id::text||'/'||product.id::text||'/'||gen_random_uuid()::text||'.jpg';
 begin perform public.set_product_image(req,product.organization_id,product.id,product.version,path);raise exception 'FAIL missing upload accepted';
 exception when raise_exception then if sqlerrm<>'IMAGE_UPLOAD_REQUIRED' then raise;end if;end;
 reply:=public.set_product_image(req,product.organization_id,product.id,product.version,null);
 if reply<>public.set_product_image(req,product.organization_id,product.id,product.version,null) then raise exception 'FAIL image retry';end if;
 begin perform public.set_product_image(gen_random_uuid(),product.organization_id,product.id,product.version,null);raise exception 'FAIL stale image write';
 exception when raise_exception then if sqlerrm<>'PRODUCT_VERSION_CONFLICT' then raise;end if;end;
end $$;
reset role;
select 'Image attachment assertions passed; fixtures rolled back.' as result;
