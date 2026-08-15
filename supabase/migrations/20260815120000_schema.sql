-- ============================================================================
-- 0001 — Schema: enums, tables, indexes
--
-- The Postgres mirror of the SwiftData model in MCPStrength/Models/.
-- Design decisions and their reasoning live in docs/05-database.md; this file
-- carries only the reasons that must not be lost at the point of edit.
--
-- Three rules govern everything below.
--
--   1. ENUM VALUES ARE THE SWIFT RAW VALUES, VERBATIM — 'fullBody', not
--      'full_body'. Column names are snake_case because that is Postgres, but
--      enum values cross the wire to the app and to the MCP server, and a
--      translation layer between two spellings of the same value is a bug
--      generator. See docs/05-database.md § "Naming".
--
--   2. EVERY SYNCED TABLE CARRIES user_id / updated_at / deleted_at /
--      server_updated_at. Deletes are soft; `deleted_at` is the tombstone.
--      `updated_at` is the CLIENT's wall clock and is the last-write-wins
--      input. `server_updated_at` is the server's and is the pull cursor.
--      They are not interchangeable — see 0002.
--
--   3. IDS ARE CLIENT-GENERATED UUIDs, never sequences. An offline device must
--      be able to create a row and know its id before it has ever spoken to
--      the server. For SEEDED rows the id is additionally a permanent contract
--      (docs/01-data-model.md § "The seeded library").
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Enums
--
-- Native enums rather than text + CHECK, deliberately. Phase 0's failure was
-- the spike silently coercing an unrecognised set_type to "normal" and
-- returning success, which reached the user as a confident bug report about
-- the wrong feature (docs/02-architecture.md § "MCP tool failures"). A native
-- enum makes an unknown value a hard error at the database boundary, which is
-- the loud failure that lesson asks for. Adding a value later is one
-- `alter type ... add value` and is transaction-safe on PG 12+.
-- ----------------------------------------------------------------------------

create type public.body_part as enum (
  'arms', 'back', 'cardio', 'chest', 'core',
  'fullBody', 'legs', 'olympic', 'other', 'shoulders'
);

-- The polymorphic key: category determines which set columns are meaningful.
-- docs/01-data-model.md § "ExerciseCategory". Validation is at the category
-- level in application code, not here — a CHECK per category would have to be
-- rewritten every time a category is added.
create type public.exercise_category as enum (
  'barbell', 'dumbbell', 'machineOther', 'weightedBodyweight',
  'assistedBodyweight', 'repsOnly', 'cardio', 'duration'
);

create type public.focus_metric as enum (
  'totalVolume', 'volumeIncrease', 'totalReps', 'weightPerRep'
);

create type public.weight_unit as enum ('lbs', 'kg');

create type public.bar_type as enum (
  'olympicBar', 'standardBar', 'ezBar', 'trapBar', 'dumbbell', 'other'
);

create type public.folder_kind as enum ('folder', 'program');

create type public.set_type as enum ('normal', 'warmup', 'dropSet', 'failure');

create type public.measurement_group as enum ('core', 'bodyPart');

create type public.measurement_source as enum ('manual', 'healthKit');


-- ----------------------------------------------------------------------------
-- exercises — the library
--
-- OWNERSHIP IS THE WHOLE DESIGN HERE. `user_id IS NULL` means a seeded library
-- row: one copy for everyone, id fixed forever by the seed file. `user_id` set
-- means a user-created exercise. The alternative — giving every user a private
-- copy of the seeded library — would force `id` to stop being unique on its
-- own and drag a composite key through every foreign key in the schema.
--
-- The four USER-PREFERENCE fields that SwiftData keeps on Exercise
-- (weightUnitOverride, barType, focusMetric, notes) are NOT here. They live in
-- `exercise_preferences` below, because a shared row cannot hold a per-user
-- value. This split is the one place the Postgres schema deliberately diverges
-- from the SwiftData schema; ExerciseSeedImporter already draws exactly this
-- line, refreshing only name/bodyPart/category/aliases on re-seed and
-- preserving the other four as "user preferences, not library properties".
-- ----------------------------------------------------------------------------
create table public.exercises (
  id                  uuid primary key,
  user_id             uuid references auth.users (id) on delete cascade,

  name                text not null,
  -- Deliberately NOT unique across exercises. An alias landing on four
  -- exercises produces ambiguity, which the matcher already handles correctly
  -- (return candidates, write nothing). docs/01-data-model.md § "Aliases".
  aliases             text[] not null default '{}',
  body_part           public.body_part not null,
  category            public.exercise_category not null,
  is_custom           boolean not null default false,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  server_updated_at   timestamptz not null default now(),

  -- A global row is exactly a non-custom row, in both directions. Without
  -- this, a client could insert a user-owned row with is_custom = false and it
  -- would be invisible to the re-seed rules that key off that flag.
  constraint exercises_custom_iff_owned
    check ((user_id is null) = (is_custom = false)),
  constraint exercises_name_not_blank
    check (length(btrim(name)) > 0)
);

-- ----------------------------------------------------------------------------
-- exercise_preferences — per-user settings on ANY exercise, seeded or custom
--
-- Keyed on (user_id, exercise_id) rather than carrying its own uuid: there is
-- at most one preference row per user per exercise, and a natural key removes
-- the "which of my two preference rows wins" question entirely.
--
-- Nothing writes this yet — the app has no UI for editing these fields. It
-- exists now for the same reason the Program schema shipped in Phase 1:
-- additive-by-construction only helps if the columns exist before there are
-- users (docs/04-status.md).
-- ----------------------------------------------------------------------------
create table public.exercise_preferences (
  user_id               uuid not null references auth.users (id) on delete cascade,
  exercise_id           uuid not null references public.exercises (id) on delete cascade,

  weight_unit_override  public.weight_unit,
  bar_type              public.bar_type,
  focus_metric          public.focus_metric not null default 'totalVolume',
  notes                 text,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz,
  server_updated_at     timestamptz not null default now(),

  primary key (user_id, exercise_id)
);


-- ----------------------------------------------------------------------------
-- template_folders — a drawer, or a drawer that knows what day it is
--
-- `program_cursor` and `total_cycles` are meaningless when kind = 'folder' and
-- are deliberately NOT constrained to null there: flipping a program back to a
-- plain folder must leave the program data dormant, never delete it
-- (docs/01-data-model.md § "demotion must not destroy data"). A check forcing
-- them null for folders would do precisely the destroying.
--
-- Column renames from Swift, forced by Postgres reserved words:
--   order  -> sort_order       (ORDER is reserved)
--   cursor -> program_cursor   (CURSOR is reserved)
-- ----------------------------------------------------------------------------
create table public.template_folders (
  id                  uuid primary key,
  user_id             uuid not null references auth.users (id) on delete cascade,

  name                text not null,
  -- Position among folders. Distinct from templates.sort_order, which is
  -- position WITHIN a folder, not a global rank.
  sort_order          integer not null,
  is_collapsed        boolean not null default false,
  kind                public.folder_kind not null default 'folder',
  -- Position in the program_days list; the single source of truth for
  -- "what's next". "Week 3 of 8" is computed from it, never stored.
  program_cursor      integer not null default 0,
  -- Null means run indefinitely.
  total_cycles        integer,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  server_updated_at   timestamptz not null default now(),

  constraint template_folders_sort_order_nonneg check (sort_order >= 0),
  constraint template_folders_cursor_nonneg     check (program_cursor >= 0),
  constraint template_folders_cycles_positive   check (total_cycles is null or total_cycles > 0)
);

-- ----------------------------------------------------------------------------
-- templates
--
-- folder_id ON DELETE SET NULL mirrors SwiftData's .nullify: deleting a folder
-- unfiles its templates, it does not delete them.
-- ----------------------------------------------------------------------------
create table public.templates (
  id                  uuid primary key,
  user_id             uuid not null references auth.users (id) on delete cascade,

  name                text not null,
  folder_id           uuid references public.template_folders (id) on delete set null,
  note                text,
  -- Position WITHIN its folder (or within the unfiled list when folder_id is
  -- null), 0-based. This is NOT a global rank — it used to be, and the next
  -- reader will assume it still is.
  sort_order          integer not null,
  last_performed_at   timestamptz,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  server_updated_at   timestamptz not null default now(),

  constraint templates_sort_order_nonneg check (sort_order >= 0)
);

-- ----------------------------------------------------------------------------
-- template_exercises
-- ----------------------------------------------------------------------------
create table public.template_exercises (
  id                    uuid primary key,
  user_id               uuid not null references auth.users (id) on delete cascade,

  template_id           uuid not null references public.templates (id) on delete cascade,
  -- SET NULL, not CASCADE: deleting a custom exercise should empty the slot,
  -- not silently shorten the plan.
  exercise_id           uuid references public.exercises (id) on delete set null,
  sort_order            integer not null,
  -- Exercises sharing a group id are performed round-robin. Nullable because
  -- most exercises are not in one. Not a foreign key — the group has no row of
  -- its own, it is just a shared token.
  superset_group_id     uuid,
  note                  text,
  sticky_note           text,
  -- Rest is per-set; this is the default new sets inherit.
  default_rest_seconds  integer not null default 90,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz,
  server_updated_at     timestamptz not null default now(),

  constraint template_exercises_sort_order_nonneg check (sort_order >= 0),
  constraint template_exercises_rest_nonneg       check (default_rest_seconds >= 0)
);

-- ----------------------------------------------------------------------------
-- template_sets — the prescription
--
-- weight has NO non-negative constraint, on purpose: assisted bodyweight sets
-- carry ASSISTANCE weight, which is negative (docs/01-data-model.md
-- § "ExerciseCategory"). A `weight >= 0` check here would reject a whole
-- category of legitimate sets.
-- ----------------------------------------------------------------------------
create table public.template_sets (
  id                    uuid primary key,
  user_id               uuid not null references auth.users (id) on delete cascade,

  template_exercise_id  uuid not null references public.template_exercises (id) on delete cascade,
  sort_order            integer not null,
  set_type              public.set_type not null default 'normal',

  weight                double precision,
  reps                  integer,
  rep_range_start       integer,
  rep_range_end         integer,
  rpe                   double precision,
  distance              double precision,
  duration_seconds      integer,
  rest_seconds          integer not null default 90,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz,
  server_updated_at     timestamptz not null default now(),

  constraint template_sets_sort_order_nonneg check (sort_order >= 0),
  constraint template_sets_reps_positive     check (reps is null or reps > 0),
  constraint template_sets_rest_nonneg       check (rest_seconds >= 0),
  constraint template_sets_distance_nonneg   check (distance is null or distance >= 0),
  constraint template_sets_duration_nonneg   check (duration_seconds is null or duration_seconds >= 0),

  -- A range is both ends or neither.
  constraint template_sets_rep_range_paired
    check ((rep_range_start is null) = (rep_range_end is null)),
  constraint template_sets_rep_range_ordered
    check (rep_range_start is null or (rep_range_start > 0 and rep_range_end >= rep_range_start)),
  -- A set uses a fixed target OR a range, never both. Matches RepRangeParser,
  -- which treats the two as alternatives rather than as a value plus a hint.
  constraint template_sets_reps_xor_range
    check (reps is null or rep_range_start is null),

  -- Prescribed effort: 6-10 in half steps. Every legal value (x.0 / x.5) is
  -- exactly representable in binary floating point, so this comparison is
  -- exact rather than approximately true.
  constraint template_sets_rpe_half_step
    check (rpe is null or (rpe >= 6 and rpe <= 10 and (rpe * 2) = trunc(rpe * 2)))
);


-- ----------------------------------------------------------------------------
-- workouts — the performance
--
-- template_id is nullable for two different reasons and both matter: a quick
-- workout never had a template, and ON DELETE SET NULL means deleting a
-- template later does not delete the history performed from it. `name` is a
-- COPY taken at start, never read through template_id, so renaming or deleting
-- a template never rewrites the history of workouts already performed from it.
--
-- total_volume and pr_count are computed values cached for list performance.
-- ----------------------------------------------------------------------------
create table public.workouts (
  id                  uuid primary key,
  user_id             uuid not null references auth.users (id) on delete cascade,

  name                text not null,
  template_id         uuid references public.templates (id) on delete set null,
  started_at          timestamptz not null,
  completed_at        timestamptz,
  duration_seconds    integer not null default 0,
  note                text,
  total_volume        double precision not null default 0,
  pr_count            integer not null default 0,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  server_updated_at   timestamptz not null default now(),

  constraint workouts_duration_nonneg check (duration_seconds >= 0),
  constraint workouts_pr_count_nonneg check (pr_count >= 0),
  constraint workouts_completed_after_start
    check (completed_at is null or completed_at >= started_at)
);

create table public.workout_exercises (
  id                  uuid primary key,
  user_id             uuid not null references auth.users (id) on delete cascade,

  workout_id          uuid not null references public.workouts (id) on delete cascade,
  exercise_id         uuid references public.exercises (id) on delete set null,
  sort_order          integer not null,
  superset_group_id   uuid,
  note                text,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  server_updated_at   timestamptz not null default now(),

  constraint workout_exercises_sort_order_nonneg check (sort_order >= 0)
);

-- ----------------------------------------------------------------------------
-- workout_sets
--
-- Same shape as template_sets MINUS rep_range_start/rep_range_end — a
-- performance is a number, not a range — PLUS completion state. rpe IS here as
-- well as on template_sets, and that asymmetry is the point: prescribed effort
-- on the plan and actual effort on the performance makes the delta computable.
-- ----------------------------------------------------------------------------
create table public.workout_sets (
  id                    uuid primary key,
  user_id               uuid not null references auth.users (id) on delete cascade,

  workout_exercise_id   uuid not null references public.workout_exercises (id) on delete cascade,
  sort_order            integer not null,
  set_type              public.set_type not null default 'normal',

  weight                double precision,
  reps                  integer,
  rpe                   double precision,
  distance              double precision,
  duration_seconds      integer,
  rest_seconds          integer not null default 90,
  -- The checkmark. A set can exist unchecked.
  is_completed          boolean not null default false,
  -- Enables true rest-interval analysis, which is why it is a timestamp rather
  -- than a boolean's shadow.
  completed_at          timestamptz,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz,
  server_updated_at     timestamptz not null default now(),

  constraint workout_sets_sort_order_nonneg check (sort_order >= 0),
  constraint workout_sets_reps_positive     check (reps is null or reps > 0),
  constraint workout_sets_rest_nonneg       check (rest_seconds >= 0),
  constraint workout_sets_distance_nonneg   check (distance is null or distance >= 0),
  constraint workout_sets_duration_nonneg   check (duration_seconds is null or duration_seconds >= 0),
  constraint workout_sets_rpe_half_step
    check (rpe is null or (rpe >= 6 and rpe <= 10 and (rpe * 2) = trunc(rpe * 2)))
);


-- ----------------------------------------------------------------------------
-- program_days — an ordered list of POINTERS to templates
--
-- Not the folder's own template ordering, and this is load-bearing: real
-- programs repeat templates (A/B/A then B/A/B). A folder holds each template
-- once, so "folder order = day order" cannot express it.
--
-- folder_id CASCADE (the days belong to the program), template_id SET NULL
-- (deleting a template empties a slot, it does not delete the program).
-- ----------------------------------------------------------------------------
create table public.program_days (
  id                  uuid primary key,
  user_id             uuid not null references auth.users (id) on delete cascade,

  folder_id           uuid not null references public.template_folders (id) on delete cascade,
  template_id         uuid references public.templates (id) on delete set null,
  sort_order          integer not null,
  -- Advisory only. Nothing in this model binds a day to a weekday or a date;
  -- it is a rotation, not a schedule (docs/01-data-model.md).
  label               text,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  server_updated_at   timestamptz not null default now(),

  constraint program_days_sort_order_nonneg check (sort_order >= 0)
);


-- ----------------------------------------------------------------------------
-- measurement_types — seeded reference data, same ownership rule as exercises
--
-- user_id IS NULL is a seeded type. The column exists (rather than the table
-- being purely global) so user-defined measurement types can land later
-- without changing the ownership model.
--
-- Column rename from Swift: group -> group_kind (GROUP is reserved).
-- ----------------------------------------------------------------------------
create table public.measurement_types (
  id                  uuid primary key,
  user_id             uuid references auth.users (id) on delete cascade,

  name                text not null,
  group_kind          public.measurement_group not null,
  -- Seeded, anatomical, not alphabetical — that order becomes muscle memory.
  sort_order          integer not null default 0,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  server_updated_at   timestamptz not null default now(),

  constraint measurement_types_sort_order_nonneg check (sort_order >= 0)
);

-- ----------------------------------------------------------------------------
-- measurement_entries — time series; the main screen shows only the latest
--
-- `source` is load-bearing rather than informational: Apple Health sync is
-- bidirectional, so entries this app wrote to HealthKit must be tagged to be
-- skipped on import, or every write echoes back as a duplicate.
--
-- `unit` is stored per entry, matching the app today. Whether to move to
-- canonical storage is an open question — see docs/05-database.md.
-- ----------------------------------------------------------------------------
create table public.measurement_entries (
  id                  uuid primary key,
  user_id             uuid not null references auth.users (id) on delete cascade,

  type_id             uuid references public.measurement_types (id) on delete set null,
  value               double precision not null,
  unit                text not null,
  recorded_at         timestamptz not null,
  source              public.measurement_source not null default 'manual',

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  server_updated_at   timestamptz not null default now()
);


-- ----------------------------------------------------------------------------
-- Indexes
--
-- Two families:
--   * (user_id, server_updated_at) — the pull cursor, hit by every sync on
--     every table. This is the one index the sync engine cannot work without.
--   * foreign keys — Postgres does not index these automatically, and an
--     unindexed FK makes every parent delete a sequential scan of the child.
--
-- Deliberately ABSENT: a unique index on (parent_id, sort_order). Reordering
-- renumbers densely and transiently collides mid-move, which a non-deferrable
-- unique constraint would reject. Ordering is enforced by ListOrdering /
-- TemplateOrdering in the app, which is where it is already tested.
-- ----------------------------------------------------------------------------

create index exercises_sync_idx             on public.exercises (user_id, server_updated_at);
create index exercise_preferences_sync_idx  on public.exercise_preferences (user_id, server_updated_at);
create index template_folders_sync_idx      on public.template_folders (user_id, server_updated_at);
create index templates_sync_idx             on public.templates (user_id, server_updated_at);
create index template_exercises_sync_idx    on public.template_exercises (user_id, server_updated_at);
create index template_sets_sync_idx         on public.template_sets (user_id, server_updated_at);
create index workouts_sync_idx              on public.workouts (user_id, server_updated_at);
create index workout_exercises_sync_idx     on public.workout_exercises (user_id, server_updated_at);
create index workout_sets_sync_idx          on public.workout_sets (user_id, server_updated_at);
create index program_days_sync_idx          on public.program_days (user_id, server_updated_at);
create index measurement_types_sync_idx     on public.measurement_types (user_id, server_updated_at);
create index measurement_entries_sync_idx   on public.measurement_entries (user_id, server_updated_at);

create index exercise_preferences_exercise_idx on public.exercise_preferences (exercise_id);
create index templates_folder_idx              on public.templates (folder_id);
create index template_exercises_template_idx   on public.template_exercises (template_id);
create index template_exercises_exercise_idx   on public.template_exercises (exercise_id);
create index template_sets_parent_idx          on public.template_sets (template_exercise_id);
create index workouts_template_idx             on public.workouts (template_id);
create index workout_exercises_workout_idx     on public.workout_exercises (workout_id);
create index workout_exercises_exercise_idx    on public.workout_exercises (exercise_id);
create index workout_sets_parent_idx           on public.workout_sets (workout_exercise_id);
create index program_days_folder_idx           on public.program_days (folder_id);
create index program_days_template_idx         on public.program_days (template_id);
create index measurement_entries_type_idx      on public.measurement_entries (type_id);

-- History and per-exercise progress are the two read paths the MCP server
-- serves most (get_workout_history, get_exercise_progress). Partial on
-- deleted_at because neither ever wants tombstones.
create index workouts_history_idx
  on public.workouts (user_id, started_at desc)
  where deleted_at is null;

create index workout_exercises_progress_idx
  on public.workout_exercises (user_id, exercise_id)
  where deleted_at is null;

create index measurement_entries_series_idx
  on public.measurement_entries (user_id, type_id, recorded_at desc)
  where deleted_at is null;

-- Tombstone sweep (see 0002's purge_tombstones) scans by deleted_at.
create index workouts_tombstone_idx on public.workouts (deleted_at) where deleted_at is not null;
create index templates_tombstone_idx on public.templates (deleted_at) where deleted_at is not null;
