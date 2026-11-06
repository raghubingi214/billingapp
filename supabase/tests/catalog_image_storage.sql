begin;
do $$ begin
 if not exists(select 1 from storage.buckets where id='catalog-images' and not public and file_size_limit=3145728 and allowed_mime_types=array['image/jpeg','image/png','image/webp']) then raise exception 'FAIL catalog bucket policy';end if;
 if has_function_privilege('anon','private.can_access_catalog_image(text,boolean)','EXECUTE') then raise exception 'FAIL anonymous helper access';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 if private.can_access_catalog_image('../../private.jpg',false) then raise exception 'FAIL unsafe path';end if;
 if private.can_access_catalog_image('------------------------------------/------------------------------------/------------------------------------.jpg',true) then raise exception 'FAIL malformed IDs';end if;
 if private.can_access_catalog_image(gen_random_uuid()::text||'/'||gen_random_uuid()::text||'/'||gen_random_uuid()::text||'.jpg',true) then raise exception 'FAIL absent membership';end if;
end $$;
reset role;
select 'Catalog image storage boundary assertions passed.' as result;
rollback;
