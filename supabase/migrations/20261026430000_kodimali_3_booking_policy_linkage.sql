-- Instant Booking policies must point to an approved, versioned cancellation
-- matrix. This avoids silently applying short-term rules to long tenancies.

create or replace function public.validate_instant_booking_policy_link()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.booking_mode='instant_booking' and not exists(
    select 1 from public.booking_policies p
    join public.cancellation_policy_versions v on v.id=p.cancellation_policy_version_id
    where p.id=new.policy_id and p.is_active and v.is_active
      and v.effective_from<=now() and (v.effective_until is null or v.effective_until>now())
  ) then
    raise exception 'Instant Booking requires an approved versioned cancellation policy';
  end if;
  return new;
end;
$$;
drop trigger if exists validate_instant_booking_policy_link on public.booking_configurations;
create trigger validate_instant_booking_policy_link
before insert or update of booking_mode,policy_id on public.booking_configurations
for each row execute function public.validate_instant_booking_policy_link();

create or replace function public.set_booking_policy_cancellation_version(
  p_booking_policy_id uuid,
  p_cancellation_policy_version_id uuid
)
returns public.booking_policies
language plpgsql
security definer
set search_path = public
as $$
declare v_policy public.booking_policies;
begin
  if not public.has_admin_permission('bookings.manage') then
    raise exception 'Booking policy management permission required';
  end if;
  if not exists(
    select 1 from public.cancellation_policy_versions
    where id=p_cancellation_policy_version_id and is_active
      and effective_from<=now() and (effective_until is null or effective_until>now())
  ) then raise exception 'Choose an active cancellation policy version'; end if;
  update public.booking_policies set cancellation_policy_version_id=p_cancellation_policy_version_id
  where id=p_booking_policy_id returning * into v_policy;
  if v_policy.id is null then raise exception 'Booking policy not found'; end if;
  insert into public.audit_logs(actor_id,action,target_table,target_id,metadata)
  values(auth.uid(),'booking_policy_cancellation_version_linked','booking_policies',v_policy.id,
    jsonb_build_object('cancellation_policy_version_id',p_cancellation_policy_version_id));
  return v_policy;
end;
$$;

revoke all on function public.set_booking_policy_cancellation_version(uuid,uuid) from public,anon,authenticated;
grant execute on function public.set_booking_policy_cancellation_version(uuid,uuid) to authenticated,service_role;
revoke all on function public.validate_instant_booking_policy_link() from public,anon,authenticated;

comment on column public.booking_policies.cancellation_policy_version_id is
'Explicit approved cancellation matrix accepted into each immutable booking snapshot.';
