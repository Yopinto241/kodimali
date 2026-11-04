-- Apply the same active-assignment check to direct RPC calls as to Edge calls.
create or replace function public.manage_update_booking_status(p_booking_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 perform 1 from public.booking_requests where id=p_booking_id for update;
 if not found then raise exception 'Request not found'; end if;
 if not public.has_domain_permission('booking_requests','UPDATE') and not public.is_booking_assigned_agent(p_booking_id) then
   raise exception 'Booking permission or active assigned agent required' using errcode='42501';
 end if;
 update public.booking_requests set booking_status=p_status::public.booking_status where id=p_booking_id;
end $$;
notify pgrst,'reload schema';
