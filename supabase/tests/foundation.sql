-- Run with a privileged development connection. Everything is rolled back.
-- These fixtures simulate Supabase JWT identity and authenticated database role.
begin;
create temporary table foundation_test_context (
  label text primary key, id uuid, data jsonb
) on commit drop;
grant select,insert,update on foundation_test_context to authenticated;
insert into foundation_test_context(label,id) values
 ('owner_a',gen_random_uuid()),('owner_b',gen_random_uuid()),
 ('staff',gen_random_uuid()),('outsider',gen_random_uuid()),
 ('request_a',gen_random_uuid()),('request_b',gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,aud,role)
select id,label||'.'||id::text||'@example.invalid',now(),'{}','{}','authenticated','authenticated'
from foundation_test_context where label in ('owner_a','owner_b','staff','outsider');
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare response jsonb; repeated jsonb; req uuid;
begin
  select id into req from foundation_test_context where label='request_a';
  response:=public.onboard_organization(req,'Shop A','Shop A Legal','36',
    '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','unregistered',null,'INV');
  repeated:=public.onboard_organization(req,'Shop A','Shop A Legal','36',
    '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','unregistered',null,'INV');
  if response<>repeated then raise exception 'FAIL: retry returned a different organization'; end if;
  if (select count(*) from public.organizations)<>1 then raise exception 'FAIL: onboarding duplicate'; end if;
  if (select count(*) from public.organization_members)<>1 then raise exception 'FAIL: owner membership missing/duplicated'; end if;
  if (select role from public.organization_members)<>'owner' then raise exception 'FAIL: owner role'; end if;
  if (select count(*) from public.outlets)<>1 or (select count(*) from public.invoice_series)<>1
    or (select count(*) from public.business_settings)<>1 or (select count(*) from public.audit_events)<>1 then
    raise exception 'FAIL: atomic onboarding objects missing/duplicated';
  end if;
  insert into foundation_test_context(label,id,data) values('org_a',(response->>'organization_id')::uuid,response);
  begin
    perform public.onboard_organization(req,'CHANGED','Shop A Legal','36',
      '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','unregistered',null,'INV');
    raise exception 'FAIL: changed payload accepted for existing request key';
  exception when invalid_parameter_value then
    if sqlerrm<>'IDEMPOTENCY_CONFLICT' then raise; end if;
  end;
  begin
    perform public.onboard_organization(gen_random_uuid(),'Bad','Bad','36','{}','unregistered',null,'INV');
    raise exception 'FAIL: empty address accepted';
  exception when invalid_parameter_value then
    if sqlerrm<>'INVALID_ADDRESS' then raise; end if;
  end;
  begin
    perform public.onboard_organization(gen_random_uuid(),'Bad','Bad','36',
      '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','regular',null,'INV');
    raise exception 'FAIL: registered merchant without GSTIN accepted';
  exception when invalid_parameter_value then
    if sqlerrm<>'INVALID_GSTIN' then raise; end if;
  end;
  begin
    update public.organization_members set role='owner';
    raise exception 'FAIL: direct membership write allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.audit_events;
    raise exception 'FAIL: direct audit delete allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$
declare response jsonb;
begin
  if exists(select 1 from public.organizations) or exists(select 1 from public.outlets)
     or exists(select 1 from public.organization_members) or exists(select 1 from public.audit_events)
     or exists(select 1 from public.business_settings) or exists(select 1 from public.invoice_series) then
    raise exception 'FAIL: cross-tenant read before onboarding';
  end if;
  response:=public.onboard_organization((select id from foundation_test_context where label='request_b'),
    'Shop B','Shop B Legal','29','{"line1":"2 Test Street","city":"Bengaluru","postal_code":"560001"}',
    'unregistered',null,'INV');
  insert into foundation_test_context(label,id,data) values('org_b',(response->>'organization_id')::uuid,response);
  if (select count(*) from public.organizations)<>1 then raise exception 'FAIL: cross-tenant org visibility'; end if;
  if exists(select 1 from public.organizations where name='Shop A') then raise exception 'FAIL: Org B can read Org A'; end if;
  begin
    perform public.invite_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),'intruder@example.invalid','manager');
    raise exception 'FAIL: cross-org invitation accepted';
  exception when insufficient_privilege then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare response jsonb; staff_email text; req uuid:=gen_random_uuid();
begin
  select 'staff.'||id::text||'@example.invalid' into staff_email from foundation_test_context where label='staff';
  response:=public.invite_member(req,(select id from foundation_test_context where label='org_a'),staff_email,'cashier');
  if response<>public.invite_member(req,(select id from foundation_test_context where label='org_a'),staff_email,'cashier') then
    raise exception 'FAIL: invitation retry mismatch';
  end if;
  insert into foundation_test_context(label,id) values('invitation',(response->>'invitation_id')::uuid);
  if (select count(*) from public.organization_invitations)<>1 then raise exception 'FAIL: duplicate invitation'; end if;
  begin
    perform public.invite_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),'other@example.invalid','owner');
    raise exception 'FAIL: owner invitation accepted';
  exception when invalid_parameter_value then
    if sqlerrm<>'INVALID_ROLE' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='outsider'),true);
do $$
begin
  if exists(select 1 from public.organization_invitations) then raise exception 'FAIL: outsider sees invite'; end if;
  begin
    perform public.accept_invitation((select id from foundation_test_context where label='invitation'));
    raise exception 'FAIL: outsider accepted another email invitation';
  exception when insufficient_privilege then
    if sqlerrm<>'INVITATION_UNAVAILABLE' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='staff'),true);
do $$
declare response jsonb; member_id uuid;
begin
  if (select count(*) from public.organization_invitations)<>1 then raise exception 'FAIL: recipient cannot see own invitation'; end if;
  response:=public.accept_invitation((select id from foundation_test_context where label='invitation'));
  if response<>public.accept_invitation((select id from foundation_test_context where label='invitation')) then raise exception 'FAIL: invitation accept retry'; end if;
  select id into member_id from public.organization_members where user_id=auth.uid();
  insert into foundation_test_context(label,id) values('staff_member',member_id);
  if (select count(*) from public.organizations)<>1 or (select count(*) from public.organization_members)<>1 then
    raise exception 'FAIL: cashier membership visibility';
  end if;
  if exists(select 1 from public.audit_events) then raise exception 'FAIL: cashier sees financial audit'; end if;
  begin
    perform public.update_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),member_id,'manager','active');
    raise exception 'FAIL: cashier self-promotion';
  exception when insufficient_privilege then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
  begin
    perform public.invite_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),'x@example.invalid','manager');
    raise exception 'FAIL: cashier can invite';
  exception when insufficient_privilege then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
begin
  if (select count(*) from public.organization_members)<>2 then raise exception 'FAIL: owner cannot see team'; end if;
  perform public.update_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),
    (select id from foundation_test_context where label='staff_member'),'cashier','revoked');
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='staff'),true);
do $$
begin
  if exists(select 1 from public.organizations) or exists(select 1 from public.organization_members)
     or exists(select 1 from public.outlets) or exists(select 1 from public.invoice_series)
     or exists(select 1 from public.business_settings) then raise exception 'FAIL: revoked staff retains access'; end if;
  begin
    perform public.accept_invitation((select id from foundation_test_context where label='invitation'));
    raise exception 'FAIL: revoked staff reactivated through consumed invite';
  exception when insufficient_privilege then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub','',true);
do $$
begin
  if exists(select 1 from public.organizations) then raise exception 'FAIL: absent JWT sees org'; end if;
  begin
    perform public.onboard_organization(gen_random_uuid(),'No Auth','No Auth','36',
      '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','unregistered',null,'INV');
    raise exception 'FAIL: absent JWT onboarding allowed';
  exception when insufficient_privilege then
    if sqlerrm<>'AUTH_REQUIRED' then raise; end if;
  end;
end $$;
reset role;
select 'Foundation assertions passed; fixture data rolled back.' as result;
rollback;
