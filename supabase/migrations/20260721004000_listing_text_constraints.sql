-- Keep application validation and clean database replays aligned with the
-- listing text constraints already enforced in production.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.listings'::regclass
      and conname = 'listings_title_check'
  ) then
    alter table public.listings
      add constraint listings_title_check
      check (
        char_length(btrim(title)) >= 3
        and char_length(btrim(title)) <= 180
      ) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.listings'::regclass
      and conname = 'listings_description_check'
  ) then
    alter table public.listings
      add constraint listings_description_check
      check (char_length(btrim(description)) >= 10) not valid;
  end if;
end;
$$;

alter table public.listings
  validate constraint listings_title_check;

alter table public.listings
  validate constraint listings_description_check;
