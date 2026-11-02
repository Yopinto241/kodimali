-- Expose a boolean only. Contact numbers remain in the existing paid/unlocked flow.
create function public.normalize_whatsapp_number(p_phone text) returns text
language plpgsql immutable set search_path=public as $$
declare digits text; begin
 if p_phone is null or btrim(p_phone)='' or p_phone !~ '^[+0-9 ().-]+$' then return null; end if;
 digits:=regexp_replace(p_phone,'[^0-9]','','g');
 if digits ~ '^0+$' then return null; end if;
 if left(digits,2)='00' then digits:=substr(digits,3); end if;
 if length(digits)=10 and left(digits,1)='0' then digits:='255'||substr(digits,2);
 elsif length(digits)=9 and left(digits,1) in ('6','7') then digits:='255'||digits; end if;
 if digits !~ '^[1-9][0-9]{7,14}$' or (left(digits,3)='255' and length(digits)<>12) then return null; end if;
 return digits;
end $$;
create or replace function public.get_public_listing_booking_capabilities(p_listing_ids uuid[])
returns table(listing_id uuid,capability jsonb) language sql stable security definer set search_path=public as $$
 select l.id,resolved.capability||jsonb_build_object('has_whatsapp',public.normalize_whatsapp_number(a.phone_number) is not null)
 from (select distinct id from unnest(coalesce(p_listing_ids,'{}'::uuid[])) id limit 100) requested
 join public.listings l on l.id=requested.id join public.agents a on a.id=l.agent_id
 cross join lateral (select public.get_public_listing_booking_capability(l.id) capability) resolved
 where public.is_listing_public(l.id) and resolved.capability is not null
$$;
revoke all on function public.normalize_whatsapp_number(text),public.get_public_listing_booking_capabilities(uuid[]) from public;
grant execute on function public.normalize_whatsapp_number(text),public.get_public_listing_booking_capabilities(uuid[]) to anon,authenticated,service_role;
notify pgrst,'reload schema';
