-- ----------------------------------------------------------------------------
-- app_settings — the user's global preferences, the Postgres half
--
-- Designed in docs/06-sync.md § "Syncing the two singleton-ish tables"; the
-- reasoning is there and is not repeated here. What this file needs to say is
-- the part a later reader will get wrong.
--
-- ORDERING. This migration must be applied and VERIFIED REMOTE before any
-- client that conforms `AppSettings` to `Syncable` runs against the project.
-- Pushing to a table the server does not have makes PostgREST reject the batch,
-- and a rejected batch aborts the WHOLE sync run — the pull stops too, and every
-- later sync fails identically until somebody works out why. That is exactly
-- what the 18 seeded measurement types did on the first real round trip
-- (docs/04-status.md).
--
-- **This is not defended by the paragraph above.** The ordering rule on
-- 20260818120000 was accurate, prominent, sitting in the file being applied, and
-- was broken within the hour. What defends this one is that the client
-- conformance is a SEPARATE COMMIT, with `supabase migration list` as the gate
-- between them.
--
-- KEYED ON user_id, WITH NO id COLUMN, exactly like exercise_preferences. There
-- is at most one settings row per user, so a natural key removes the "which of
-- my two settings rows wins" question entirely — and that question is not
-- hypothetical here: the client's local row predates sync and carries a random
-- UUID, which is why the engine resolves settings through
-- `AppSettings.current(in:)` rather than by matching ids. See 06-sync.md.
-- ----------------------------------------------------------------------------

-- Two new enums. `weight_unit` already exists (0001) and is reused for both of
-- the weight rows — training loads and body weight are the same vocabulary, and
-- the reference app separates the SETTINGS, not the units.
--
-- Spelled to match the Swift raw values character for character, which is the
-- whole reason docs/05-database.md insisted the enums agree: the client encodes
-- its Swift enum directly and there is no mapping table in between to get wrong.
create type public.distance_unit as enum ('miles', 'kilometers');
create type public.size_unit     as enum ('inches', 'centimeters');

create table public.app_settings (
  user_id                 uuid not null references auth.users (id) on delete cascade,

  -- Units. The reason this table exists: storage is canonical KILOGRAMS, so a
  -- stored weight means nothing without knowing which unit to render it in.
  weight_unit             public.weight_unit   not null default 'lbs',
  measurement_weight_unit public.weight_unit   not null default 'lbs',
  distance_unit           public.distance_unit not null default 'miles',
  size_unit               public.size_unit     not null default 'inches',

  -- Settled behaviour. Defaults match the values hardcoded at the client's
  -- creation sites, so introducing this table changes no behaviour.
  default_rest_seconds    integer not null default 90,
  week_start_day          integer not null default 1,

  -- SHAPE NOT DECIDED — text, deliberately NOT enums.
  --
  -- Their case lists are the part nobody has chosen: there is no light palette
  -- designed, the app is not localised, and exactly ONE Previous behaviour
  -- exists. An enum here would commit BOTH sides to cases that do not exist
  -- yet, and changing it later is an enum migration on the server and a Swift
  -- enum migration on the client — the position `bar_type` is now in.
  -- Mirrors `String?` on AppSettings. See Models/Settings.swift.
  theme                   text,
  language                text,
  previous_set_behavior   text,

  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  deleted_at              timestamptz,
  server_updated_at       timestamptz not null default now(),

  primary key (user_id),

  constraint app_settings_week_start_day_valid
    check (week_start_day between 1 and 7),
  constraint app_settings_default_rest_nonnegative
    check (default_rest_seconds >= 0)
);

-- The pull filter, matching every other synced table: `user_id` scopes it and
-- `server_updated_at` is the cursor. One row per user makes this close to
-- pointless for selectivity, and it is here anyway so the shape does not become
-- the one table a later reader has to think about.
create index app_settings_sync_idx on public.app_settings (user_id, server_updated_at);

-- ----------------------------------------------------------------------------
-- RLS — owner only, same policy shape as every other user-owned table
-- ----------------------------------------------------------------------------

alter table public.app_settings enable row level security;

create policy app_settings_owner on public.app_settings
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ----------------------------------------------------------------------------
-- BOTH trigger lists. Not one.
--
-- The lists in 0002 and 0008 are explicit rather than a loop over
-- information_schema, so that a table added later has to be added DELIBERATELY.
-- The cost of that choice is this block: a new table gets no triggers unless
-- somebody writes them.
--
-- Missing `set_sync_metadata` is the quiet one — `server_updated_at` would then
-- only ever hold its insert default, so the row would never appear in a pull
-- filtered on it, on any device, forever. Nothing errors.
--
-- Missing `reject_stale_update` loses last-write-wins for this table only: a
-- stale device would overwrite a newer setting made elsewhere.
--
-- `_sync_reject_stale` sorts after `_sync_metadata` and that is not decorative
-- — the guard has to see the far-future clamp the first trigger applies.
-- ----------------------------------------------------------------------------

create trigger app_settings_sync_metadata
  before insert or update on public.app_settings
  for each row execute function public.set_sync_metadata();

create trigger app_settings_sync_reject_stale
  before update on public.app_settings
  for each row execute function public.reject_stale_update();
