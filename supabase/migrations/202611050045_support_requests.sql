-- Requests record intent; account closure never immediately deletes tax records.
create table public.support_requests (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 requested_by uuid not null references auth.users(id),
 kind text not null check(kind in ('help','feedback','export','account_closure')),
 subject text not null check(length(trim(subject)) between 3 and 160),
 message text not null check(length(trim(message)) between 10 and 4000),
 status text not null default 'open' check(status in ('open','in_review','resolved','cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index support_requests_org_time_idx on public.support_requests(organization_id,created_at desc,id);
create index support_requests_actor_idx on public.support_requests(requested_by);
alter table public.support_requests enable row level security;
revoke all on public.support_requests from public,anon,authenticated;
grant select on public.support_requests to authenticated;
create policy support_owner_read on public.support_requests for select to authenticated
 using(private.has_role(organization_id,array['owner']));

create function public.submit_support_request(p_request_id uuid,p_organization_id uuid,p_kind text,p_subject text,p_message text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;request_id uuid:=gen_random_uuid();begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'kind',p_kind,'subject',trim(p_subject),'message',trim(p_message));
 reply:=private.replay('support_request',p_request_id,payload);
 if reply is not null then return reply;end if;
 if p_kind is null or p_kind not in ('help','feedback','export','account_closure')
 or p_subject is null or length(trim(p_subject)) not between 3 and 160
 or p_message is null or length(trim(p_message)) not between 10 and 4000 then raise exception 'INVALID_SUPPORT_REQUEST';end if;
 if (select count(*) from public.support_requests where organization_id=p_organization_id and created_at>now()-interval '1 hour')>=10 then raise exception 'SUPPORT_RATE_LIMIT';end if;
 insert into public.support_requests(id,organization_id,requested_by,kind,subject,message)
 values(request_id,p_organization_id,auth.uid(),p_kind,trim(p_subject),trim(p_message));
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'support.requested','support_requests',request_id,jsonb_build_object('kind',p_kind),p_request_id);
 reply:=jsonb_build_object('id',request_id,'status','open');
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'support_request',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.submit_support_request(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.submit_support_request(uuid,uuid,text,text,text) to authenticated;
