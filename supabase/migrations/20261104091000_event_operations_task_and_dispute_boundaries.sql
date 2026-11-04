-- Narrow operations on existing Events records; no new role or workflow tables.
create or replace function public.update_event_fulfillment_task(p_task_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
declare task public.event_tasks;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into task from public.event_tasks where id=p_task_id for update;
 if task.id is null or (task.assigned_profile_id is distinct from auth.uid() and not public.has_admin_permission('events.manage')) then
   raise exception 'Assigned provider or coordinator required' using errcode='42501';
 end if;
 if p_status not in ('in_progress','blocked','completed') then raise exception 'Invalid task state'; end if;
 if task.status=p_status then return; end if;
 if task.status in ('completed','cancelled') then raise exception 'This task is already closed'; end if;
 update public.event_tasks set status=p_status,completed_at=case when p_status='completed' then now() else null end,updated_at=now() where id=task.id;
 insert into public.event_audit_log(plan_id,actor_id,action,details)
 values(task.plan_id,auth.uid(),'fulfillment_task_updated',jsonb_build_object('task_id',task.id,'before',task.status,'after',p_status));
end $$;
revoke all on function public.update_event_fulfillment_task(uuid,text) from public,anon;
grant execute on function public.update_event_fulfillment_task(uuid,text) to authenticated;

create or replace function public.resolve_event_dispute(p_dispute_id uuid,p_resolution text,p_status text default 'resolved')
returns void language plpgsql security definer set search_path=public as $$
declare dispute public.event_disputes;
begin
 if auth.uid() is null or not public.has_admin_permission('events.manage') then raise exception 'Event coordinator required' using errcode='42501'; end if;
 if p_status not in ('investigating','resolved','rejected') or length(trim(coalesce(p_resolution,'')))<3 then raise exception 'Valid status and resolution required'; end if;
 select * into dispute from public.event_disputes where id=p_dispute_id for update;
 if dispute.id is null then raise exception 'Dispute unavailable'; end if;
 update public.event_disputes set status=p_status,resolution=trim(p_resolution),updated_at=now() where id=dispute.id;
 insert into public.event_audit_log(plan_id,actor_id,action,details)
 values(dispute.plan_id,auth.uid(),'event_dispute_reviewed',jsonb_build_object('dispute_id',dispute.id,'before',dispute.status,'after',p_status,'resolution',trim(p_resolution)));
end $$;
revoke all on function public.resolve_event_dispute(uuid,text,text) from public,anon;
grant execute on function public.resolve_event_dispute(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
