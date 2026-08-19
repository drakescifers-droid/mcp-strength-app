-- ============================================================================
-- app_settings — the table, its key, and the two triggers it is easy to forget
--
-- Most of this file is about the trigger registration rather than the columns.
-- The columns fail loudly if they are wrong; a MISSING TRIGGER fails silently:
--
--   * without `set_sync_metadata`, `server_updated_at` never moves off its
--     insert default, so the row never appears in a pull filtered on it, on any
--     device, forever — and nothing anywhere errors;
--   * without `reject_stale_update`, this one table loses last-write-wins and a
--     stale device overwrites a newer setting made elsewhere.
--
-- Both lists in 0002 and 0008 are explicit on purpose, so a new table has to be
-- registered deliberately. This file is what makes "deliberately" checkable.
-- ============================================================================

\set ON_ERROR_STOP on

-- User 1111… already exists (01_schema_test).

-- ----------------------------------------------------------------------------
-- The row, and the defaults
-- ----------------------------------------------------------------------------

insert into public.app_settings (user_id)
values ('11111111-1111-1111-1111-111111111111');

select tests.assert(
  (select weight_unit::text from public.app_settings
    where user_id = '11111111-1111-1111-1111-111111111111') = 'lbs',
  'app_settings.weight_unit did not default to lbs'
);

select tests.assert(
  (select default_rest_seconds from public.app_settings
    where user_id = '11111111-1111-1111-1111-111111111111') = 90,
  'app_settings.default_rest_seconds did not default to 90, which is the value '
  'hardcoded at the client creation sites — introducing this table must change '
  'no behaviour'
);

-- The three undecided fields are nullable text, mirroring `String?` on the
-- client. An enum here would commit both sides to cases nobody has chosen.
select tests.assert(
  (select count(*) from information_schema.columns
    where table_name = 'app_settings'
      and column_name in ('theme', 'language', 'previous_set_behavior')
      and data_type = 'text'
      and is_nullable = 'YES') = 3,
  'theme / language / previous_set_behavior must be NULLABLE TEXT, not enums — '
  'their case lists are deliberately undecided (docs/05-database.md)'
);

-- ----------------------------------------------------------------------------
-- ONE ROW PER USER. The natural key is the whole design.
-- ----------------------------------------------------------------------------

do $$
begin
  begin
    insert into public.app_settings (user_id)
    values ('11111111-1111-1111-1111-111111111111');
    raise exception 'a second app_settings row for one user was accepted — the '
                    'primary key must be user_id, or "which of my two settings '
                    'rows wins" becomes a real question';
  exception when unique_violation then
    null; -- expected
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- Trigger 1: set_sync_metadata maintains server_updated_at
-- ----------------------------------------------------------------------------

select tests.assert(
  exists (
    select 1 from pg_trigger
     where tgname = 'app_settings_sync_metadata'
       and tgrelid = 'public.app_settings'::regclass
  ),
  'app_settings is not registered with set_sync_metadata. Without it '
  'server_updated_at never moves and the row never appears in ANY pull — the '
  'quiet failure, because nothing errors'
);

-- Prove it rather than trusting the registration: an update must advance
-- server_updated_at even though the statement never mentions it.
do $$
declare
  before_ts timestamptz;
  after_ts  timestamptz;
begin
  select server_updated_at into before_ts from public.app_settings
    where user_id = '11111111-1111-1111-1111-111111111111';

  perform pg_sleep(0.01);

  update public.app_settings
     set weight_unit = 'kg',
         updated_at = now()
   where user_id = '11111111-1111-1111-1111-111111111111';

  select server_updated_at into after_ts from public.app_settings
    where user_id = '11111111-1111-1111-1111-111111111111';

  if after_ts <= before_ts then
    raise exception 'server_updated_at did not advance on update (% -> %)',
      before_ts, after_ts;
  end if;
end;
$$;

select tests.assert(
  (select weight_unit::text from public.app_settings
    where user_id = '11111111-1111-1111-1111-111111111111') = 'kg',
  'weight_unit did not round-trip as kg'
);

-- ----------------------------------------------------------------------------
-- Trigger 2: reject_stale_update enforces last-write-wins here too
-- ----------------------------------------------------------------------------

select tests.assert(
  exists (
    select 1 from pg_trigger
     where tgname = 'app_settings_sync_reject_stale'
       and tgrelid = 'public.app_settings'::regclass
  ),
  'app_settings is not registered with reject_stale_update. Without it a stale '
  'device silently overwrites a newer setting made on another device'
);

-- A write carrying an OLDER updated_at must not land. This is the sequence the
-- client-side push filter also guards from the other end: a device that has
-- never had its settings touched must not win against a real choice.
do $$
declare
  stale_time timestamptz := now() - interval '1 hour';
begin
  update public.app_settings
     set weight_unit = 'lbs',
         updated_at = stale_time
   where user_id = '11111111-1111-1111-1111-111111111111';
end;
$$;

select tests.assert(
  (select weight_unit::text from public.app_settings
    where user_id = '11111111-1111-1111-1111-111111111111') = 'kg',
  'a STALE update overwrote a newer value — last-write-wins is not being '
  'enforced on app_settings'
);

-- ----------------------------------------------------------------------------
-- The two new enums exist and carry exactly the client''s cases
-- ----------------------------------------------------------------------------

select tests.assert(
  (select array_agg(e.enumlabel::text order by e.enumlabel)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'distance_unit') = array['kilometers', 'miles'],
  'distance_unit enum does not match the Swift DistanceUnit cases — the client '
  'encodes its enum directly, so the spellings must agree exactly'
);

select tests.assert(
  (select array_agg(e.enumlabel::text order by e.enumlabel)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'size_unit') = array['centimeters', 'inches'],
  'size_unit enum does not match the Swift SizeUnit cases'
);

-- ----------------------------------------------------------------------------
-- Constraints
-- ----------------------------------------------------------------------------

do $$
begin
  begin
    update public.app_settings set week_start_day = 8
     where user_id = '11111111-1111-1111-1111-111111111111';
    raise exception 'week_start_day = 8 was accepted; Calendar.firstWeekday is 1-7';
  exception when check_violation then
    null; -- expected
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- Clean up, so later test files see the state they expect
-- ----------------------------------------------------------------------------

delete from public.app_settings
 where user_id = '11111111-1111-1111-1111-111111111111';
