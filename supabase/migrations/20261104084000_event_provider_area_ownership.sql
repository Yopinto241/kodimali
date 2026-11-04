-- Qualify the outer row: the former p.id=p.profile_id compared two provider
-- columns, rather than the service area's foreign key.
alter policy event_areas_provider_manage on public.event_service_areas
using (exists(select 1 from public.event_service_profiles p
 where p.id=event_service_areas.profile_id and (p.profile_id=auth.uid() or public.has_domain_permission('event_service_areas','UPDATE'))))
with check (exists(select 1 from public.event_service_profiles p
 where p.id=event_service_areas.profile_id and (p.profile_id=auth.uid() or public.has_domain_permission('event_service_areas','UPDATE'))));
