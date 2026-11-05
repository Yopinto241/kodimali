-- Read-only regression checks; run against a database with the mobile migrations.
begin read only;
do $$
begin
 if not public.marketplace_matches_search('Modern house Arusha bedrooms 2','nyumba arusha') then
   raise exception 'Swahili house/location search failed';end if;
 if not public.marketplace_matches_search('Office Dodoma','ofisi dodoma') then
   raise exception 'Bilingual office search failed';end if;
 if not public.marketplace_matches_search('Rental house','nataka nyumba ya kupanga') then
   raise exception 'Swahili rental phrase search failed';end if;
 if not public.marketplace_matches_search('Plot Mwanza','kiwanja mwanza') then
   raise exception 'Bilingual land search failed';end if;
 if public.marketplace_matches_search('House Arusha','nyumba mwanza') then
   raise exception 'Search ignored the requested location';end if;
 if public.marketplace_matches_search('Bathroom only','room') then
   raise exception 'Search matched an unrelated partial word';end if;
 if has_table_privilege('anon','public.manage_listing_directory','select') then
   raise exception 'Anonymous management access is permitted';end if;
 if has_table_privilege('authenticated','public.manage_listing_directory','update') then
   raise exception 'Directory permits listing writes';end if;
 if not exists(select 1 from pg_class where oid='public.manage_listing_directory'::regclass
   and reloptions @> array['security_invoker=true']) then
   raise exception 'Directory bypasses the underlying RLS';end if;
 if has_function_privilege('anon','public.set_admin_work_location(uuid,uuid)','execute') then
   raise exception 'Anonymous staff assignment is permitted';end if;
 if has_function_privilege('authenticated','public.wake_push_dispatcher()','execute') then
   raise exception 'Client can invoke the private worker';end if;
end $$;
rollback;
