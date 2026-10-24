-- One-time administrator recovery requested after listing lifecycle repair.
-- Only listings with a real attached image are publishable.

do $$
declare
  v_reactivated integer := 0;
  v_without_images integer := 0;
begin
  -- Prevent per-row publication hooks from running while the batch repairs
  -- cover markers and marketplace state as one atomic migration.
  alter table public.listing_media disable trigger publish_staged_listing_after_media;
  alter table public.listing_media disable trigger release_listing_after_image_attach;
  alter table public.listings disable trigger guard_listing_workflow;
  alter table public.listings disable trigger enforce_agent_listing_payment_before_publish;

  with preferred_cover as (
    select distinct on (lm.listing_id) lm.listing_id, lm.id
    from public.listing_media lm
    where lm.media_type::text = 'image'
    order by lm.listing_id, lm.is_cover desc, lm.display_order asc, lm.created_at asc
  )
  update public.listing_media lm
  set is_cover = (lm.id = pc.id)
  from preferred_cover pc
  where lm.listing_id = pc.listing_id;

  update public.listings l
  set status = 'active'::public.listing_status,
      availability_status = 'available'::public.availability_status,
      publication_requested = false,
      removed_from_market_at = null,
      removed_reason = null,
      published_at = timezone('utc', now())
  where exists (
    select 1 from public.listing_media lm
    where lm.listing_id = l.id and lm.media_type::text = 'image'
  );
  get diagnostics v_reactivated = row_count;

  select count(*) into v_without_images
  from public.listings l
  where not exists (
    select 1 from public.listing_media lm
    where lm.listing_id = l.id and lm.media_type::text = 'image'
  );

  alter table public.listings enable trigger enforce_agent_listing_payment_before_publish;
  alter table public.listings enable trigger guard_listing_workflow;
  alter table public.listing_media enable trigger release_listing_after_image_attach;
  alter table public.listing_media enable trigger publish_staged_listing_after_media;

  insert into public.audit_logs(action, target_table, metadata)
  values (
    'admin_batch_reactivate_listings',
    'listings',
    jsonb_build_object(
      'reactivatedCount', v_reactivated,
      'skippedWithoutImages', v_without_images,
      'requestedAt', timezone('utc', now())
    )
  );

  raise notice 'Reactivated % listings; % listings have no image and remain private.',
    v_reactivated, v_without_images;
end;
$$;

