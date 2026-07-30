-- Reconcile listings that became stuck before the reliable release function
-- was installed. Only listings with valid publishable media are released.
do $$
declare
  v_listing_id uuid;
begin
  for v_listing_id in
    select distinct p.listing_id
    from public.agent_listing_payments p
    where p.payment_status = 'paid'
  loop
    begin
      perform public.release_agent_listing_if_eligible(v_listing_id);
    exception when others then
      raise notice 'Could not reconcile paid listing %: %', v_listing_id, sqlerrm;
    end;
  end loop;

  if not public.agent_listing_payments_enabled() then
    for v_listing_id in
      select l.id
      from public.listings l
      where l.status = 'inactive'::public.listing_status
        and l.removed_from_market_at is null
        and l.removed_reason is null
        and public.listing_has_publishable_media(l.id)
    loop
      begin
        perform public.release_agent_listing_if_eligible(v_listing_id);
      exception when others then
        raise notice 'Could not reconcile free listing %: %', v_listing_id, sqlerrm;
      end;
    end loop;
  end if;
end $$;
