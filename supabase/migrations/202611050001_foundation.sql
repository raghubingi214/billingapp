-- Phase 1 foundation. Source: specification sections 3, 4, 7, 8 and 14.
-- Public application tables have read-only client grants. Commands own all writes.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.profiles (
  user_id uuid primary key references auth.users(id),
  display_name text not null default '',
  created_at timestamptz not null default now()
);
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 160),
  legal_name text not null check (length(trim(legal_name)) between 1 and 200),
  tax_regime text not null check (tax_regime in ('unregistered','regular','composition')),
  gstin text,
  state_code text not null check (state_code ~ '^[0-9]{2}$'),
  address jsonb not null check (jsonb_typeof(address) = 'object'),
  currency text not null default 'INR' check (currency = 'INR'),
  timezone text not null default 'Asia/Kolkata' check (timezone = 'Asia/Kolkata'),
  status text not null default 'active' check (status in ('active','suspended')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check ((tax_regime = 'unregistered' and gstin is null) or
    (tax_regime in ('regular','composition') and gstin is not null and
      gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' and left(gstin,2)=state_code))
);
create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  user_id uuid not null references auth.users(id),
  role text not null check (role in ('owner','manager','cashier','accountant')),
  status text not null default 'active' check (status in ('active','revoked')),
  invited_by uuid references auth.users(id),
  joined_at timestamptz not null default now(),
  unique (organization_id,user_id),
  unique (id,organization_id)
);
create index organization_members_user_idx on public.organization_members(user_id,organization_id) where status='active';
create index organization_members_inviter_idx on public.organization_members(invited_by);
create index organizations_creator_idx on public.organizations(created_by);
create table public.outlets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  name text not null, code text not null, state_code text not null,
  address jsonb not null, is_default boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id,code), unique (id,organization_id)
);
create unique index one_default_outlet_idx on public.outlets(organization_id) where is_default;
create table public.business_settings (
  organization_id uuid primary key references public.organizations(id),
  invoice_template text not null default 'a4',
  allow_negative_stock boolean not null default false,
  currency_rounding numeric(18,2) not null default 0.01 check(currency_rounding>0),
  receipt_footer text not null default '',
  tax_config jsonb not null default '{}',
  version integer not null default 1,
  updated_at timestamptz not null default now()
);
create table public.invoice_series (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  financial_year text not null check(financial_year ~ '^[0-9]{2}-[0-9]{2}$'),
  doc_type text not null check(doc_type in ('tax_invoice','bill_of_supply','commercial_invoice','credit_note')),
  prefix text not null check(prefix ~ '^[A-Z0-9]{1,4}$'),
  next_seq bigint not null default 1 check(next_seq between 1 and 999999),
  active boolean not null default true,
  unique(organization_id,doc_type,financial_year,prefix),
  unique(id,organization_id)
);
create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  actor_user_id uuid not null references auth.users(id),
  action text not null, table_name text not null, record_id uuid not null,
  before_data jsonb, after_data jsonb, request_id uuid not null,
  created_at timestamptz not null default now()
);
create index audit_org_time_idx on public.audit_events(organization_id,created_at desc);
create index audit_actor_idx on public.audit_events(actor_user_id);
create table public.organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  email text not null check(email=lower(trim(email)) and email ~ '^[^ @]+@[^ @]+[.][^ @]+$'),
  role text not null check(role in ('manager','cashier','accountant')),
  status text not null default 'pending' check(status in ('pending','accepted','revoked')),
  invited_by uuid not null references auth.users(id),
  accepted_by uuid references auth.users(id),
  expires_at timestamptz not null default now()+interval '7 days',
  created_at timestamptz not null default now(),
  unique(id,organization_id)
);
create unique index one_pending_invite_idx on public.organization_invitations(organization_id,email) where status='pending';
create index invites_email_idx on public.organization_invitations(email,status);
create index invites_inviter_idx on public.organization_invitations(invited_by);
create index invites_acceptor_idx on public.organization_invitations(accepted_by);

-- Internal command storage is never exposed through the Data API.
create table private.command_receipts (
  actor_id uuid not null references auth.users(id),
  command_name text not null,
  request_id uuid not null,
  payload jsonb not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key(actor_id,command_name,request_id)
);
alter table private.command_receipts enable row level security;
revoke all on private.command_receipts from public,anon,authenticated;

create function private.my_organization_ids()
returns setof uuid language sql stable security definer set search_path='' as $$
  select m.organization_id from public.organization_members m
  join public.organizations o on o.id=m.organization_id
  where m.user_id=(select auth.uid()) and m.status='active' and o.status='active';
$$;
create function private.has_role(p_org uuid,p_roles text[])
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.organization_members m
    join public.organizations o on o.id=m.organization_id
    where m.organization_id=p_org and m.user_id=(select auth.uid())
    and m.status='active' and o.status='active' and m.role=any(p_roles));
$$;
create function private.verified_email()
returns text language sql stable security definer set search_path='' as $$
  select lower(u.email) from auth.users u where u.id=(select auth.uid()) and u.email_confirmed_at is not null;
$$;
revoke all on function private.my_organization_ids() from public,anon;
revoke all on function private.has_role(uuid,text[]) from public,anon;
revoke all on function private.verified_email() from public,anon;
grant execute on function private.my_organization_ids(),private.has_role(uuid,text[]),private.verified_email() to authenticated;

do $$
declare t text;
begin
  foreach t in array array['profiles','organizations','organization_members','outlets','business_settings','invoice_series','audit_events','organization_invitations'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;
create policy profile_self on public.profiles for select to authenticated using(user_id=(select auth.uid()));
create policy organization_member_read on public.organizations for select to authenticated using(id in (select private.my_organization_ids()));
create policy membership_read on public.organization_members for select to authenticated using(
  organization_id in (select private.my_organization_ids()) and
  (user_id=(select auth.uid()) or private.has_role(organization_id,array['owner'])));
create policy outlet_member_read on public.outlets for select to authenticated using(organization_id in (select private.my_organization_ids()));
create policy settings_member_read on public.business_settings for select to authenticated using(organization_id in (select private.my_organization_ids()));
create policy series_member_read on public.invoice_series for select to authenticated using(organization_id in (select private.my_organization_ids()));
create policy audit_finance_read on public.audit_events for select to authenticated using(private.has_role(organization_id,array['owner','accountant']));
create policy invitation_read on public.organization_invitations for select to authenticated using(
  private.has_role(organization_id,array['owner']) or
  (email=(select private.verified_email()) and status='pending' and expires_at>now()));

-- Every command locks its actor/request key before checking an existing response.
-- Full JSONB input is retained: equality is exact and cannot hash-collide.
create function private.replay(p_command text,p_request uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare found_receipt private.command_receipts%rowtype; uid uuid:=auth.uid();
begin
  if uid is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  if p_request is null then raise exception using errcode='22023',message='REQUEST_ID_REQUIRED'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text||p_command||p_request::text,0));
  select * into found_receipt from private.command_receipts where actor_id=uid and command_name=p_command and request_id=p_request;
  if found then
    if found_receipt.payload<>p_payload then raise exception using errcode='22023',message='IDEMPOTENCY_CONFLICT'; end if;
    return found_receipt.response;
  end if;
  return null;
end $$;
revoke all on function private.replay(text,uuid,jsonb) from public,anon,authenticated;

create function public.onboard_organization(
  p_request_id uuid,p_name text,p_legal_name text,p_state_code text,
  p_address jsonb,p_tax_regime text,p_gstin text,p_prefix text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  uid uuid:=auth.uid(); org_id uuid; outlet_id uuid; reply jsonb; payload jsonb;
  fy_start integer; fy text; document_type text;
begin
  payload:=jsonb_build_object('name',p_name,'legal_name',p_legal_name,'state',p_state_code,'address',p_address,'tax_regime',p_tax_regime,'gstin',p_gstin,'prefix',p_prefix);
  reply:=private.replay('onboard',p_request_id,payload);
  if reply is not null then
    if not private.has_role((reply->>'organization_id')::uuid,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
    return reply;
  end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>160 or nullif(trim(p_legal_name),'') is null or length(trim(p_legal_name))>200 then
    raise exception using errcode='22023',message='INVALID_BUSINESS_NAME';
  end if;
  if p_state_code is null or p_state_code !~ '^[0-9]{2}$' or p_state_code::int not between 1 and 38 then
    raise exception using errcode='22023',message='INVALID_STATE';
  end if;
  if p_address is null or jsonb_typeof(p_address)<>'object' or length(p_address::text)>4000
    or nullif(trim(p_address->>'line1'),'') is null or nullif(trim(p_address->>'city'),'') is null
    or coalesce(p_address->>'postal_code','') !~ '^[1-9][0-9]{5}$' then
    raise exception using errcode='22023',message='INVALID_ADDRESS';
  end if;
  if p_tax_regime is null or p_tax_regime not in ('unregistered','regular','composition') then
    raise exception using errcode='22023',message='INVALID_TAX_REGIME';
  end if;
  if p_prefix is null or p_prefix !~ '^[A-Z0-9]{1,4}$' then raise exception using errcode='22023',message='INVALID_PREFIX'; end if;
  if p_tax_regime='unregistered' and nullif(trim(p_gstin),'') is not null then
    raise exception using errcode='22023',message='UNREGISTERED_GSTIN_NOT_ALLOWED';
  end if;
  if p_tax_regime<>'unregistered' and (p_gstin is null or p_gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' or left(p_gstin,2)<>p_state_code) then
    raise exception using errcode='22023',message='INVALID_GSTIN';
  end if;
  insert into public.profiles(user_id) values(uid) on conflict(user_id) do nothing;
  insert into public.organizations(name,legal_name,state_code,address,tax_regime,gstin,created_by)
  values(trim(p_name),trim(p_legal_name),p_state_code,p_address,p_tax_regime,nullif(trim(p_gstin),''),uid) returning id into org_id;
  insert into public.organization_members(organization_id,user_id,role) values(org_id,uid,'owner');
  insert into public.outlets(organization_id,name,code,state_code,address,is_default)
  values(org_id,trim(p_name),'MAIN',p_state_code,p_address,true) returning id into outlet_id;
  insert into public.business_settings(organization_id) values(org_id);
  fy_start:=extract(year from now() at time zone 'Asia/Kolkata')::integer;
  if extract(month from now() at time zone 'Asia/Kolkata')<4 then fy_start:=fy_start-1; end if;
  fy:=right(fy_start::text,2)||'-'||right((fy_start+1)::text,2);
  document_type:=case p_tax_regime when 'regular' then 'tax_invoice' when 'composition' then 'bill_of_supply' else 'commercial_invoice' end;
  insert into public.invoice_series(organization_id,financial_year,doc_type,prefix) values(org_id,fy,document_type,p_prefix);
  insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
  values(org_id,uid,'organization.created','organizations',org_id,jsonb_build_object('name',trim(p_name),'tax_regime',p_tax_regime),p_request_id);
  reply:=jsonb_build_object('organization_id',org_id,'outlet_id',outlet_id);
  insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(uid,'onboard',p_request_id,payload,reply);
  return reply;
end $$;

create function public.invite_member(p_request_id uuid,p_organization_id uuid,p_email text,p_role text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb; reply jsonb; invite_id uuid; normalized_email text:=lower(trim(p_email));
begin
  -- Serialize role changes and invitations per organization; recheck after locking.
  perform 1 from public.organizations where id=p_organization_id for update;
  if not private.has_role(p_organization_id,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
  payload:=jsonb_build_object('organization_id',p_organization_id,'email',normalized_email,'role',p_role);
  reply:=private.replay('invite',p_request_id,payload);
  if reply is not null then return reply; end if;
  if normalized_email is null or length(normalized_email)>254 or normalized_email !~ '^[^ @]+@[^ @]+[.][^ @]+$' then raise exception using errcode='22023',message='INVALID_EMAIL'; end if;
  if p_role is null or p_role not in ('manager','cashier','accountant') then raise exception using errcode='22023',message='INVALID_ROLE'; end if;
  if exists(select 1 from public.organization_members m join auth.users u on u.id=m.user_id where m.organization_id=p_organization_id and lower(u.email)=normalized_email and m.status='active') then
    raise exception using errcode='22023',message='ALREADY_MEMBER';
  end if;
  update public.organization_invitations set status='revoked' where organization_id=p_organization_id and email=normalized_email and status='pending' and expires_at<=now();
  insert into public.organization_invitations(organization_id,email,role,invited_by)
  values(p_organization_id,normalized_email,p_role,auth.uid()) returning id into invite_id;
  insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
  values(p_organization_id,auth.uid(),'member.invited','organization_invitations',invite_id,jsonb_build_object('role',p_role),p_request_id);
  reply:=jsonb_build_object('invitation_id',invite_id);
  insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'invite',p_request_id,payload,reply);
  return reply;
end $$;

create function public.accept_invitation(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare invitation public.organization_invitations%rowtype; member_id uuid; org_id uuid; uid uuid:=auth.uid();
begin
  if uid is null or private.verified_email() is null then raise exception using errcode='42501',message='VERIFIED_EMAIL_REQUIRED'; end if;
  select organization_id into org_id from public.organization_invitations where id=p_invitation_id and email=private.verified_email();
  if org_id is null then raise exception using errcode='42501',message='INVITATION_UNAVAILABLE'; end if;
  perform 1 from public.organizations where id=org_id and status='active' for update;
  if not found then raise exception using errcode='42501',message='INVITATION_UNAVAILABLE'; end if;
  select * into invitation from public.organization_invitations where id=p_invitation_id for update;
  if invitation.status='accepted' and invitation.accepted_by=uid then
    if not private.has_role(org_id,array['owner','manager','cashier','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
    return jsonb_build_object('organization_id',org_id);
  end if;
  if invitation.status<>'pending' or invitation.expires_at<=now() or invitation.email<>private.verified_email() then
    raise exception using errcode='42501',message='INVITATION_UNAVAILABLE';
  end if;
  -- A stale invite must not demote/promote a current member.
  if exists(select 1 from public.organization_members where organization_id=org_id and user_id=uid and status='active') then
    raise exception using errcode='22023',message='ALREADY_MEMBER';
  end if;
  insert into public.organization_members(organization_id,user_id,role,invited_by)
  values(org_id,uid,invitation.role,invitation.invited_by)
  on conflict(organization_id,user_id) do update set role=excluded.role,status='active',invited_by=excluded.invited_by,joined_at=now()
  returning id into member_id;
  update public.organization_invitations set status='accepted',accepted_by=uid where id=p_invitation_id;
  insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
  values(org_id,uid,'member.joined','organization_members',member_id,jsonb_build_object('role',invitation.role),p_invitation_id);
  return jsonb_build_object('organization_id',org_id);
end $$;

create function public.update_member(p_request_id uuid,p_organization_id uuid,p_member_id uuid,p_role text,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare member public.organization_members%rowtype; payload jsonb; reply jsonb;
begin
  perform 1 from public.organizations where id=p_organization_id for update;
  if not private.has_role(p_organization_id,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
  payload:=jsonb_build_object('organization_id',p_organization_id,'member_id',p_member_id,'role',p_role,'status',p_status);
  reply:=private.replay('update_member',p_request_id,payload);
  if reply is not null then return reply; end if;
  select * into member from public.organization_members where id=p_member_id and organization_id=p_organization_id for update;
  if not found then raise exception using errcode='42501',message='MEMBER_NOT_FOUND'; end if;
  if member.role='owner' or member.user_id=auth.uid() then raise exception using errcode='42501',message='OWNER_CHANGE_NOT_ALLOWED'; end if;
  if p_role is null or p_role not in ('manager','cashier','accountant') or p_status is null or p_status not in ('active','revoked') then
    raise exception using errcode='22023',message='INVALID_MEMBERSHIP';
  end if;
  update public.organization_members set role=p_role,status=p_status where id=p_member_id;
  if p_status='revoked' then
    update public.organization_invitations set status='revoked'
    where organization_id=p_organization_id and email=(select lower(email) from auth.users where id=member.user_id) and status='pending';
  end if;
  insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
  values(p_organization_id,auth.uid(),'member.updated','organization_members',p_member_id,
    jsonb_build_object('role',member.role,'status',member.status),jsonb_build_object('role',p_role,'status',p_status),p_request_id);
  reply:=jsonb_build_object('member_id',p_member_id,'status',p_status,'role',p_role);
  insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'update_member',p_request_id,payload,reply);
  return reply;
end $$;

create function public.revoke_invitation(p_request_id uuid,p_organization_id uuid,p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb; reply jsonb;
begin
  perform 1 from public.organizations where id=p_organization_id for update;
  if not private.has_role(p_organization_id,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
  payload:=jsonb_build_object('organization_id',p_organization_id,'invitation_id',p_invitation_id);
  reply:=private.replay('revoke_invitation',p_request_id,payload);
  if reply is not null then return reply; end if;
  update public.organization_invitations set status='revoked' where id=p_invitation_id and organization_id=p_organization_id and status='pending';
  if not found then raise exception using errcode='22023',message='INVITATION_UNAVAILABLE'; end if;
  insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,request_id)
  values(p_organization_id,auth.uid(),'invitation.revoked','organization_invitations',p_invitation_id,p_request_id);
  reply:=jsonb_build_object('invitation_id',p_invitation_id,'status','revoked');
  insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'revoke_invitation',p_request_id,payload,reply);
  return reply;
end $$;

revoke all on function public.onboard_organization(uuid,text,text,text,jsonb,text,text,text) from public,anon;
revoke all on function public.invite_member(uuid,uuid,text,text) from public,anon;
revoke all on function public.accept_invitation(uuid) from public,anon;
revoke all on function public.update_member(uuid,uuid,uuid,text,text) from public,anon;
revoke all on function public.revoke_invitation(uuid,uuid,uuid) from public,anon;
grant execute on function public.onboard_organization(uuid,text,text,text,jsonb,text,text,text),
 public.invite_member(uuid,uuid,text,text),public.accept_invitation(uuid),
 public.update_member(uuid,uuid,uuid,text,text),public.revoke_invitation(uuid,uuid,uuid) to authenticated;
