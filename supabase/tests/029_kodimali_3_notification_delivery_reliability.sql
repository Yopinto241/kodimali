begin;
select plan(6);

select has_column('public','notification_delivery_outbox','last_attempt_at','push outbox records its last attempt');
select has_column('public','notification_delivery_outbox','terminal_at','push outbox records terminal delivery state');
select col_is_null('public','notification_delivery_outbox','last_attempt_at','last attempt is optional before dispatch');
select col_is_null('public','notification_delivery_outbox','terminal_at','terminal timestamp is optional while retryable');
select has_index('public','notification_delivery_outbox','idx_notification_outbox_pending','retryable push jobs have a partial scheduling index');
select function_is_definer('public','retry_recent_push_after_device_registration',array[]::text[],'device registration recovery is controlled server-side');

select * from finish();
rollback;
