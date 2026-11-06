-- Platform access is separate from merchant membership. Provision the first
-- admin only through a trusted database operator after verifying auth.users.id.
create table private.platform_admins (
 user_id uuid primary key references auth.users(id),
 active boolean not null default true,
 granted_by uuid references auth.users(id),
 granted_at timestamptz not null default now(),
 revoked_at timestamptz
);
create index platform_admins_active_idx on private.platform_admins(user_id) where active;
alter table private.platform_admins enable row level security;
revoke all on private.platform_admins from public,anon,authenticated;

create function private.is_platform_admin()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.platform_admins
  where user_id=auth.uid() and active and revoked_at is null);
$$;
revoke all on function private.is_platform_admin() from public,anon;
grant execute on function private.is_platform_admin() to authenticated;

create function public.platform_admin_status()
returns boolean language sql stable security definer set search_path='' as $$
 select private.is_platform_admin();
$$;
revoke all on function public.platform_admin_status() from public,anon;
grant execute on function public.platform_admin_status() to authenticated;

create function public.platform_overview()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_platform_admin() then
  raise exception using errcode='42501',message='PLATFORM_ACCESS_DENIED';
 end if;
 return jsonb_build_object(
  'businesses',(select count(*) from public.organizations),
  'active_businesses',(select count(*) from public.organizations where status='active'),
  'suspended_businesses',(select count(*) from public.organizations where status='suspended'),
  'active_staff_members',(select count(*) from public.organization_members where status='active'));
end $$;
revoke all on function public.platform_overview() from public,anon;
grant execute on function public.platform_overview() to authenticated;

create function public.platform_businesses(p_offset integer default 0)
returns table(id uuid,name text,status text,created_at timestamptz,staff_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_platform_admin() then
  raise exception using errcode='42501',message='PLATFORM_ACCESS_DENIED';
 end if;
 if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'INVALID_OFFSET';end if;
 return query select o.id,o.name,o.status,o.created_at,
  (select count(*) from public.organization_members m where m.organization_id=o.id and m.status='active')
 from public.organizations o order by o.created_at desc,o.id limit 50 offset p_offset;
end $$;
revoke all on function public.platform_businesses(integer) from public,anon;
grant execute on function public.platform_businesses(integer) to authenticated;
