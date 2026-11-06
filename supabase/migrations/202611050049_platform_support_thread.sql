create function public.platform_support_thread(p_support_id uuid,p_offset integer default 0)
returns table(id uuid,body text,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare org uuid;begin
 if not private.is_platform_admin() then raise exception using errcode='42501',message='PLATFORM_ACCESS_DENIED';end if;
 if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'INVALID_OFFSET';end if;
 select organization_id into org from public.support_requests where support_requests.id=p_support_id;
 if not found then raise exception 'SUPPORT_REQUEST_NOT_FOUND';end if;
 return query select r.id,r.body,r.created_at from public.support_replies r
 where r.organization_id=org and r.support_id=p_support_id
 order by r.created_at,r.id limit 50 offset p_offset;
end $$;
revoke all on function public.platform_support_thread(uuid,integer) from public,anon;
grant execute on function public.platform_support_thread(uuid,integer) to authenticated;
