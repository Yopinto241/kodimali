-- A listing_media row is inserted only after guard_listing_media_object verifies
-- the Storage object, so it is a durable and path-format-independent proof that
-- the listing has a real cover image.
create or replace function public.listing_has_publishable_media(check_listing_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.listing_media where listing_id=check_listing_id and media_type::text='image' and is_cover=true)
$$;
grant execute on function public.listing_has_publishable_media(uuid) to service_role;

create or replace function public.reconcile_free_agent_listings()
returns integer language plpgsql security definer set search_path=public as $$
declare v_listing record;v_count integer:=0;
begin
 if public.agent_listing_payments_enabled() then return 0;end if;
 for v_listing in select id from public.listings where status='inactive' and removed_from_market_at is null and removed_reason is null and public.listing_has_publishable_media(id)
 loop
  begin
   if public.release_agent_listing_if_eligible(v_listing.id) then v_count:=v_count+1;end if;
  exception when others then
   -- A legacy malformed listing must not block every other eligible listing or
   -- prevent an administrator from saving the free-publication setting.
   raise warning 'Could not reconcile free listing %: %',v_listing.id,sqlerrm;
  end;
 end loop;
 return v_count;
end $$;
grant execute on function public.reconcile_free_agent_listings() to authenticated,service_role;

create or replace function public.release_free_agent_listings_after_toggle()
returns trigger language plpgsql security definer set search_path=public as $$
begin if new.agent_listing_payments_enabled=false then perform public.reconcile_free_agent_listings();end if;return new;end $$;

-- Reconcile immediately for the current free session, even when it was already
-- free before this migration.
select public.reconcile_free_agent_listings();
