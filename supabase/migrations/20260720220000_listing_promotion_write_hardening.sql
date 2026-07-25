begin;

-- Keep the storage contract in one final migration. Both Flutter workflows
-- upload the object first and then create the corresponding media row.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values
  (
    'listing-media',
    'listing-media',
    false,
    31457280,
    array[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'image/heic',
      'image/heif',
      'video/mp4',
      'video/quicktime',
      'video/x-m4v',
      'video/webm',
      'video/x-msvideo',
      'video/x-matroska'
    ]
  ),
  (
    'platform-promotions',
    'platform-promotions',
    false,
    31457280,
    array[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'image/heic',
      'image/heif',
      'video/mp4',
      'video/quicktime',
      'video/x-m4v',
      'video/webm',
      'video/x-msvideo',
      'video/x-matroska'
    ]
  )
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Remove historical write-policy names before installing one unambiguous
-- policy per bucket. Public/signed reads remain governed by their existing
-- visibility policies.
drop policy if exists "agents_manage_own_listing_media_files" on storage.objects;
drop policy if exists "listing_media_agent_active_insert" on storage.objects;
drop policy if exists "listing_media_agent_active_update" on storage.objects;
drop policy if exists "listing_media_agent_active_delete" on storage.objects;
drop policy if exists "listing_media_admin_manage" on storage.objects;
drop policy if exists "listing_media_active_agent_manage" on storage.objects;
drop policy if exists "listing_media_active_agent_or_admin_manage" on storage.objects;

create policy "listing_media_active_agent_or_admin_manage"
on storage.objects
for all
to authenticated
using (
  bucket_id = 'listing-media'
  and (
    public.is_admin()
    or (
      public.is_agent_active()
      and (
        name like auth.uid()::text || '/%'
        or name like 'listing-media/' || auth.uid()::text || '/%'
      )
    )
  )
)
with check (
  bucket_id = 'listing-media'
  and (
    public.is_admin()
    or (
      public.is_agent_active()
      and (
        name like auth.uid()::text || '/%'
        or name like 'listing-media/' || auth.uid()::text || '/%'
      )
    )
  )
);

drop policy if exists "platform_promotions_admin_write" on storage.objects;
drop policy if exists "promotions_admin_manage" on storage.objects;
drop policy if exists "platform_promotions_admin_manage" on storage.objects;

create policy "platform_promotions_admin_manage"
on storage.objects
for all
to authenticated
using (
  bucket_id = 'platform-promotions'
  and public.is_admin()
)
with check (
  bucket_id = 'platform-promotions'
  and public.is_admin()
);

-- A requested active insert is staged privately until its cover image exists.
-- This protects both the new two-phase client and older clients that inserted
-- an active row before uploading media.
alter table public.listings
  add column if not exists publication_requested boolean not null default false;

create or replace function public.normalized_storage_object_name(
  check_bucket_id text,
  check_path text
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when check_path is null then null
    when check_path like check_bucket_id || '/%'
      then substr(check_path, char_length(check_bucket_id) + 2)
    else check_path
  end;
$$;

create or replace function public.storage_object_exists(
  check_bucket_id text,
  check_path text
)
returns boolean
language sql
stable
security definer
set search_path = public, storage
as $$
  select exists (
    select 1
    from storage.objects as storage_object
    where storage_object.bucket_id = check_bucket_id
      and (
        storage_object.name = check_path
        or storage_object.name = public.normalized_storage_object_name(
          check_bucket_id,
          check_path
        )
        or storage_object.name = check_bucket_id || '/' ||
          public.normalized_storage_object_name(check_bucket_id, check_path)
      )
  );
$$;

create or replace function public.listing_has_publishable_media(
  check_listing_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, storage
as $$
  select exists (
    select 1
    from public.listing_media as listing_media_row
    join storage.objects as storage_object
      on storage_object.bucket_id = 'listing-media'
     and (
       storage_object.name = listing_media_row.storage_path
       or storage_object.name = public.normalized_storage_object_name(
         'listing-media',
         listing_media_row.storage_path
       )
       or storage_object.name = 'listing-media/' ||
         public.normalized_storage_object_name(
           'listing-media',
           listing_media_row.storage_path
         )
     )
    where listing_media_row.listing_id = check_listing_id
      and listing_media_row.media_type::text = 'image'
      and listing_media_row.is_cover = true
  );
$$;

revoke all on function public.normalized_storage_object_name(text, text)
from public, anon;
revoke all on function public.storage_object_exists(text, text)
from public, anon, authenticated;
revoke all on function public.listing_has_publishable_media(uuid)
from public, anon, authenticated;

grant execute on function public.normalized_storage_object_name(text, text)
to authenticated, service_role;
grant execute on function public.storage_object_exists(text, text)
to service_role;
grant execute on function public.listing_has_publishable_media(uuid)
to service_role;

create or replace function public.guard_listing_media_object()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_agent_profile_id uuid;
  v_object_name text;
begin
  v_object_name := public.normalized_storage_object_name(
    'listing-media',
    new.storage_path
  );

  if not public.storage_object_exists('listing-media', new.storage_path) then
    raise exception
      'Listing media upload is missing. Upload the file before saving its media record.';
  end if;

  select agent.profile_id
  into v_agent_profile_id
  from public.listings as listing
  join public.agents as agent on agent.id = listing.agent_id
  where listing.id = new.listing_id;

  if v_agent_profile_id is null then
    raise exception 'Listing owner could not be resolved for this media file.';
  end if;

  if not public.is_admin()
    and split_part(v_object_name, '/', 1) <> v_agent_profile_id::text
  then
    raise exception 'Listing media must use the owning agent storage path.';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_listing_media_object on public.listing_media;
create trigger guard_listing_media_object
before insert or update of listing_id, storage_path
on public.listing_media
for each row execute function public.guard_listing_media_object();

create or replace function public.guard_platform_promotion_media_object()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if not public.storage_object_exists(
    'platform-promotions',
    new.media_path
  ) then
    raise exception
      'Promotion media upload is missing. Upload the file before saving its media record.';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_platform_promotion_media_object
on public.platform_promotion_media;
create trigger guard_platform_promotion_media_object
before insert or update of media_path
on public.platform_promotion_media
for each row execute function public.guard_platform_promotion_media_object();

create or replace function public.guard_listing_workflow()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_agent_id uuid;
  v_owner_agent_id uuid;
  v_category_active boolean;
  v_category_slug text;
  v_legacy_category text;
  v_is_admin boolean := public.is_admin();
begin
  select category.is_active, category.slug
  into v_category_active, v_category_slug
  from public.asset_categories as category
  where category.id = new.category_id;

  if not found then
    raise exception 'Selected category does not exist.';
  end if;

  if not public.is_valid_listing_location(new.location_id) then
    raise exception
      'Choose an active ward, area, or street with a valid region and district.';
  end if;

  new.listing_attributes := public.sanitize_listing_attributes(
    new.category_id,
    coalesce(new.listing_attributes, '{}'::jsonb)
  );
  new.public_location_label := public.build_public_location_label(new.location_id);

  v_legacy_category := case v_category_slug
    when 'house' then 'house'
    when 'car' then 'car'
    when 'motorcycle' then 'motorcycle'
    when 'office' then 'office'
    when 'meeting-hall' then 'meeting_hall'
    when 'ceremony-hall' then 'ceremony_hall'
    when 'equipment' then 'equipment'
    else 'other_asset'
  end;

  -- Some historical development schemas still have approval_status, while
  -- the live schema does not. jsonb_populate_record safely ignores absent
  -- record fields and keeps both schema histories usable.
  new := jsonb_populate_record(
    new,
    jsonb_build_object(
      'category', v_legacy_category,
      'approval_status', 'approved'
    )
  );

  if new.owner_id is not null then
    select owner.agent_id
    into v_owner_agent_id
    from public.owners as owner
    where owner.id = new.owner_id;
  end if;

  if v_is_admin then
    if new.removed_reason is not null
      and new.removed_reason not in ('admin_removed', 'suspended', 'rented')
    then
      raise exception
        'Admin removal reason must be admin_removed, suspended, or rented.';
    end if;
  else
    v_agent_id := public.current_agent_id();

    if v_agent_id is null or not public.is_agent_active() then
      raise exception 'Only active agents can manage listings.';
    end if;

    if not v_category_active then
      raise exception 'Only active categories may be used.';
    end if;

    if tg_op = 'INSERT' then
      new.agent_id := v_agent_id;
    elsif old.agent_id <> v_agent_id then
      raise exception 'Agents can edit only their own listings.';
    else
      new.agent_id := old.agent_id;
    end if;

    if new.removed_reason is not null
      and new.removed_reason not in ('agent_removed', 'rented')
    then
      raise exception 'Agent removal reason must be agent_removed or rented.';
    end if;

    if new.status in (
      'suspended'::public.listing_status,
      'expired'::public.listing_status
    ) then
      raise exception 'Only admin can suspend or expire listings.';
    end if;
  end if;

  if new.owner_id is not null
    and v_owner_agent_id is distinct from new.agent_id
  then
    raise exception 'The selected owner must belong to the listing agent.';
  end if;

  if tg_op = 'INSERT' and new.status = 'active'::public.listing_status then
    new.status := 'inactive'::public.listing_status;
    new.publication_requested := true;
    new.published_at := null;
  elsif tg_op = 'INSERT' then
    new.publication_requested := false;
    new.published_at := null;
  end if;

  if new.removed_reason is not null then
    new.status := 'inactive'::public.listing_status;
    new.publication_requested := false;
    new.removed_from_market_at := coalesce(
      new.removed_from_market_at,
      case when tg_op = 'UPDATE' then old.removed_from_market_at else null end,
      timezone('utc', now())
    );
    if new.removed_reason = 'rented' then
      new.availability_status := 'rented'::public.availability_status;
    end if;
  elsif new.status = 'active'::public.listing_status then
    if tg_op = 'UPDATE'
      and old.status is distinct from 'active'::public.listing_status
      and not public.listing_has_publishable_media(new.id)
    then
      raise exception
        'Upload a cover image successfully before publishing this listing.';
    end if;

    new.publication_requested := false;
    new.removed_from_market_at := null;
    new.removed_reason := null;
    if new.availability_status = 'rented'::public.availability_status then
      new.availability_status := 'available'::public.availability_status;
    end if;
    if tg_op = 'UPDATE' then
      new.published_at := coalesce(
        old.published_at,
        new.published_at,
        timezone('utc', now())
      );
    else
      new.published_at := coalesce(new.published_at, timezone('utc', now()));
    end if;
  elsif tg_op = 'UPDATE'
    and old.status = 'active'::public.listing_status
  then
    new.published_at := old.published_at;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_listing_workflow on public.listings;
create trigger guard_listing_workflow
before insert or update on public.listings
for each row execute function public.guard_listing_workflow();

create or replace function public.publish_staged_listing_after_media()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if new.media_type::text = 'image'
    and new.is_cover = true
    and public.storage_object_exists('listing-media', new.storage_path)
  then
    update public.listings
    set
      status = 'active'::public.listing_status,
      publication_requested = false
    where id = new.listing_id
      and status = 'inactive'::public.listing_status
      and publication_requested = true
      and removed_reason is null;
  end if;

  return new;
end;
$$;

drop trigger if exists publish_staged_listing_after_media
on public.listing_media;
create trigger publish_staged_listing_after_media
after insert or update of media_type, storage_path, is_cover
on public.listing_media
for each row execute function public.publish_staged_listing_after_media();

comment on column public.listings.publication_requested is
  'True only while a legacy active insert is staged privately until its cover image is stored.';

commit;
