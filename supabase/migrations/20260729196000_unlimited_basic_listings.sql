-- Once Free is unlimited, a paid Basic plan must never reduce capacity. Its
-- value is the lower publication fee and analytics access.
update public.agent_subscription_plans
set listing_limit=null,
    features='["Unlimited listings","500 TZS per published listing","Basic analytics"]'::jsonb,
    updated_at=now()
where id='basic';
