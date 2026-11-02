-- Read-only availability preview. Only published, verified catalog records are exposed.
-- This does not reserve inventory or replace provider confirmation at booking time.
create function public.check_public_event_selection(p_items jsonb, p_start_at timestamptz, p_end_at timestamptz, p_location_id uuid)
returns table(kind text,id uuid,is_available boolean,available_quantity integer)
language plpgsql stable security definer set search_path=public as $$
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)>100 then raise exception 'Select up to 100 items'; end if;
  if p_start_at is null or p_end_at is null or p_end_at<=p_start_at or p_start_at<=now() then raise exception 'Valid future event period required'; end if;
  return query
  with entries as (select x->>'kind' k,(x->>'id')::uuid item_id,case when x->>'kind'='equipment' then (x->>'quantity')::integer else 1 end qty from jsonb_array_elements(p_items) x),
  equipment as (
    select e.id,greatest(0,e.total_quantity-coalesce((select sum(a.quantity)::integer from public.event_equipment_allocations a where a.equipment_id=e.id and a.status in ('held','confirmed') and a.occupied_period && tstzrange(p_start_at-make_interval(mins=>e.setup_minutes),p_end_at+make_interval(mins=>e.return_buffer_minutes),'[)') and (a.expires_at is null or a.expires_at>now())),0)) quantity
    from public.event_equipment_items e
    where e.id in (select item_id from entries where k='equipment') and e.verification_status='verified' and e.publication_status='published' and e.is_active
    and (p_location_id is null or public.location_is_within(e.location_id,p_location_id))
  ), services as (
    select o.id,not exists(select 1 from public.event_provider_unavailability u where u.provider_id=s.id and u.unavailable_period && tstzrange(p_start_at,p_end_at,'[)'))
    and not exists(select 1 from public.event_service_bookings b where b.provider_id=s.id and b.status in ('held','confirmed') and b.service_period && tstzrange(p_start_at,p_end_at,'[)') and (b.expires_at is null or b.expires_at>now())) available
    from public.event_service_offerings o join public.event_service_profiles s on s.id=o.provider_id
    where o.id in (select item_id from entries where k='service') and o.is_active and o.publication_status='published' and s.is_active and s.verification_status='verified'
    and (p_location_id is null or exists(select 1 from public.event_service_areas a where a.profile_id=s.id and (public.location_is_within(a.location_id,p_location_id) or public.location_is_within(p_location_id,a.location_id))))
  )
  select x.k,x.item_id,coalesce(case when x.k='equipment' then x.qty>0 and x.qty<=e.quantity when x.k='service' then s.available else false end,false),case when x.k='equipment' then coalesce(e.quantity,0) else null::integer end
  from entries x left join equipment e on x.k='equipment' and e.id=x.item_id left join services s on x.k='service' and s.id=x.item_id;
end $$;
revoke all on function public.check_public_event_selection(jsonb,timestamptz,timestamptz,uuid) from public;
grant execute on function public.check_public_event_selection(jsonb,timestamptz,timestamptz,uuid) to anon,authenticated,service_role;
