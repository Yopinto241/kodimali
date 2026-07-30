create or replace function public.get_admin_profitability_breakdown(p_days integer default 30)
returns jsonb language sql stable security definer set search_path=public as $$
select case when public.is_admin() then jsonb_build_object(
 'categories',coalesce((select jsonb_agg(to_jsonb(x)) from (select c.name,count(*) conversions,sum(p.amount) revenue_tzs from (
   select listing_id,requested_amount amount,created_at from public.listing_contact_payments where payment_status='paid'
   union all select listing_id,requested_amount,created_at from public.listing_chat_payments where payment_status='paid'
   union all select listing_id,requested_amount,created_at from public.agent_listing_payments where payment_status='paid'
 ) p join public.listings l on l.id=p.listing_id join public.asset_categories c on c.id=l.category_id where p.created_at>now()-make_interval(days=>p_days) group by c.name order by revenue_tzs desc limit 10)x),'[]'::jsonb),
 'locations',coalesce((select jsonb_agg(to_jsonb(x)) from (select l.public_location_label location,count(*) conversions,sum(p.amount) revenue_tzs from (
   select listing_id,requested_amount amount,created_at from public.listing_contact_payments where payment_status='paid'
   union all select listing_id,requested_amount,created_at from public.listing_chat_payments where payment_status='paid'
   union all select listing_id,requested_amount,created_at from public.agent_listing_payments where payment_status='paid'
 ) p join public.listings l on l.id=p.listing_id where p.created_at>now()-make_interval(days=>p_days) group by l.public_location_label order by revenue_tzs desc limit 10)x),'[]'::jsonb)
) else '{}'::jsonb end $$;
grant execute on function public.get_admin_profitability_breakdown(integer) to authenticated;
