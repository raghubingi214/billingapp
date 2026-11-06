-- Support content is explicitly submitted for operational review. This RPC
-- grants no access to invoices, customers, payments or other merchant records.
create function public.platform_support_queue(p_status text default 'open',p_offset integer default 0)
returns table(id uuid,organization_id uuid,business_name text,kind text,subject text,message text,status text,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_platform_admin() then raise exception using errcode='42501',message='PLATFORM_ACCESS_DENIED';end if;
 if p_status is null or p_status not in ('open','in_review','resolved','cancelled')
 or p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'INVALID_SUPPORT_FILTER';end if;
 return query select r.id,r.organization_id,o.name,r.kind,r.subject,r.message,r.status,r.created_at
 from public.support_requests r join public.organizations o on o.id=r.organization_id
 where r.status=p_status order by r.created_at,r.id limit 50 offset p_offset;
end $$;
revoke all on function public.platform_support_queue(text,integer) from public,anon;
grant execute on function public.platform_support_queue(text,integer) to authenticated;
create index support_requests_queue_idx on public.support_requests(status,created_at,id);
