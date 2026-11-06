create function public.begin_support_review(p_request_id uuid,p_support_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare request public.support_requests%rowtype;payload jsonb;reply jsonb;begin
 if not private.is_platform_admin() then raise exception using errcode='42501',message='PLATFORM_ACCESS_DENIED';end if;
 -- Serialize a retry before looking up its command receipt.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':support_review:'||p_request_id::text,0));
 payload:=jsonb_build_object('support_id',p_support_id);
 reply:=private.replay('support_review',p_request_id,payload);
 if reply is not null then return reply;end if;
 select * into request from public.support_requests where id=p_support_id for update;
 if not found then raise exception 'SUPPORT_REQUEST_NOT_FOUND';end if;
 if request.status<>'open' then raise exception 'SUPPORT_STATUS_CHANGED';end if;
 update public.support_requests set status='in_review',updated_at=now() where id=p_support_id;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
 values(request.organization_id,auth.uid(),'support.review_started','support_requests',p_support_id,
  jsonb_build_object('status','open'),jsonb_build_object('status','in_review'),p_request_id);
 reply:=jsonb_build_object('id',p_support_id,'status','in_review');
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'support_review',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.begin_support_review(uuid,uuid) from public,anon;
grant execute on function public.begin_support_review(uuid,uuid) to authenticated;
