create or replace function public.agent_trust_summary(p_agent_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare a public.agents%rowtype; v_response numeric; v_completed bigint; v_total bigint; v_responded bigint; v_rating numeric; v_reviews bigint; v_complaints bigint; v_plan text;
begin
 select * into a from public.agents where id=p_agent_id;
 if not found then return '{}'::jsonb; end if;
 select round(avg(extract(epoch from(first_agent_response_at-created_at))/60)::numeric,1),count(*),count(first_agent_response_at) into v_response,v_total,v_responded from public.booking_requests where agent_id=p_agent_id;
 select count(*) into v_completed from public.booking_requests where agent_id=p_agent_id and booking_status='completed';
 select round(avg(r.rating)::numeric,2),count(*) into v_rating,v_reviews from public.reviews r join public.booking_requests b on b.id=r.booking_request_id where b.agent_id=p_agent_id and r.moderation_status='visible';
 select count(*) into v_complaints from public.reports rp join public.listings l on l.id=rp.listing_id where l.agent_id=p_agent_id and rp.status in ('open','in_review');
 select s.plan_id into v_plan from public.agent_subscriptions s where s.agent_id=p_agent_id and s.status='active' and (s.expires_at is null or s.expires_at>now()) limit 1;
 return jsonb_build_object('verified',a.verification_status='approved','account_age_days',floor(extract(epoch from(now()-a.created_at))/86400),'response_minutes',coalesce(v_response,a.average_response_minutes),'completed',v_completed,'response_rate',case when v_total=0 then 0 else round(100.0*v_responded/v_total,1) end,'rating',coalesce(v_rating,0),'reviews',v_reviews,'complaints',v_complaints,'plan',coalesce(v_plan,'free'));
end $$;
grant execute on function public.agent_trust_summary(uuid) to anon,authenticated;

create or replace function public.notify_price_drop()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.price_amount < old.price_amount then
  insert into public.notifications(user_id,type,title,body,payload)
  select pa.user_id,'announcement','Price dropped',new.title||' is now '||new.price_amount||' TZS',jsonb_build_object('listing_id',new.id,'old_price',old.price_amount,'new_price',new.price_amount)
  from public.price_alerts pa left join public.notification_preferences np on np.user_id=pa.user_id
  where pa.listing_id=new.id and pa.is_active and (pa.target_price is null or new.price_amount<=pa.target_price) and coalesce(np.promotions_enabled,true);
  update public.price_alerts set last_seen_price=new.price_amount,updated_at=now() where listing_id=new.id;
 end if; return new;
end $$;
drop trigger if exists notify_listing_price_drop on public.listings;
create trigger notify_listing_price_drop after update of price_amount on public.listings for each row execute function public.notify_price_drop();
