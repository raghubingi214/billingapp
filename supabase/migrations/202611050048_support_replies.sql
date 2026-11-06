alter table public.support_requests add constraint support_request_org_unique unique(id,organization_id);
create table public.support_replies (
 id uuid primary key default gen_random_uuid(),
 support_id uuid not null,
 organization_id uuid not null,
 author_id uuid not null references auth.users(id),
 body text not null check(length(trim(body)) between 1 and 4000),
 created_at timestamptz not null default now(),
 foreign key(support_id,organization_id) references public.support_requests(id,organization_id)
);
create index support_replies_thread_idx on public.support_replies(organization_id,support_id,created_at,id);
create index support_replies_author_idx on public.support_replies(author_id);
alter table public.support_replies enable row level security;
revoke all on public.support_replies from public,anon,authenticated;
grant select on public.support_replies to authenticated;
create policy support_reply_owner_read on public.support_replies for select to authenticated
 using(private.has_role(organization_id,array['owner']));

create function public.reply_to_support(p_request_id uuid,p_support_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare request public.support_requests%rowtype;payload jsonb;reply jsonb;reply_id uuid:=gen_random_uuid();begin
 if not private.is_platform_admin() then raise exception using errcode='42501',message='PLATFORM_ACCESS_DENIED';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':support_reply:'||p_request_id::text,0));
 payload:=jsonb_build_object('support_id',p_support_id,'body',trim(p_body));
 reply:=private.replay('support_reply',p_request_id,payload);
 if reply is not null then return reply;end if;
 select * into request from public.support_requests where id=p_support_id for update;
 if not found then raise exception 'SUPPORT_REQUEST_NOT_FOUND';end if;
 if request.status not in ('open','in_review') then raise exception 'SUPPORT_STATUS_CHANGED';end if;
 if p_body is null or length(trim(p_body)) not between 1 and 4000 then raise exception 'INVALID_SUPPORT_REPLY';end if;
 insert into public.support_replies(id,support_id,organization_id,author_id,body)
 values(reply_id,p_support_id,request.organization_id,auth.uid(),trim(p_body));
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(request.organization_id,auth.uid(),'support.replied','support_replies',reply_id,jsonb_build_object('support_id',p_support_id),p_request_id);
 reply:=jsonb_build_object('id',reply_id);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'support_reply',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.reply_to_support(uuid,uuid,text) from public,anon;
grant execute on function public.reply_to_support(uuid,uuid,text) to authenticated;
