-- Manage supports a video cover with uploaded image(s) in the gallery.
-- Media rows are accepted only after guard_listing_media_object verifies the
-- uploaded object. Keep requiring an image, while allowing either cover type.
create or replace function public.listing_has_publishable_media(check_listing_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists (
   select 1 from public.listing_media
   where listing_id=check_listing_id and media_type::text='image'
 ) and exists (
   select 1 from public.listing_media
   where listing_id=check_listing_id and is_cover=true
     and media_type::text in ('image','video')
 )
$$;

grant execute on function public.listing_has_publishable_media(uuid) to service_role;
notify pgrst, 'reload schema';
