-- Free-mode access must not reset revocations or shorten an existing paid term.
create or replace function public.ensure_free_listing_chat_access(p_listing_id uuid,p_customer_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare agent uuid; access public.listing_chat_access; expiry timestamptz;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 if public.chat_payments_enabled() is distinct from false then raise exception 'Free chat is not enabled'; end if;
 if not public.is_listing_public(p_listing_id) then raise exception 'Listing unavailable'; end if;
 select agent_id into agent from public.listings where id=p_listing_id;
 perform pg_advisory_xact_lock(hashtextextended(p_customer_id::text||p_listing_id::text||agent::text,0));
 select * into access from public.listing_chat_access where customer_id=p_customer_id and listing_id=p_listing_id and agent_id=agent for update;
 if access.revoked_at is not null then return jsonb_build_object('blocked',true); end if;
 if access.expires_at>now() then return jsonb_build_object('expiresAt',access.expires_at); end if;
 expiry:=now()+interval '7 days';
 insert into public.listing_chat_access(listing_id,agent_id,customer_id,access_source,starts_at,expires_at)
 values(p_listing_id,agent,p_customer_id,'free',now(),expiry)
 on conflict(customer_id,listing_id,agent_id) do update set access_source='free',starts_at=now(),expires_at=excluded.expires_at,updated_at=now();
 return jsonb_build_object('expiresAt',expiry);
end $$;
revoke all on function public.ensure_free_listing_chat_access(uuid,uuid) from public,anon,authenticated;
grant execute on function public.ensure_free_listing_chat_access(uuid,uuid) to service_role;
create policy event_tasks_assigned_read on public.event_tasks for select to authenticated using(assigned_profile_id=auth.uid());
notify pgrst,'reload schema';
