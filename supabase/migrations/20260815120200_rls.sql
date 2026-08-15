-- ============================================================================
-- 0003 — Row Level Security
--
-- Every table in this schema is per-user data reached through PostgREST with a
-- user's own JWT. RLS is not a hardening step here, it IS the authorization
-- model: without it, one authenticated user reads every user's training
-- history with a single unfiltered GET.
--
-- Two shapes of policy, and the difference is the ownership rule from 0001:
--
--   OWNED       user_id is NOT NULL. One `for all` policy — you touch your
--               rows and no others.
--
--   REFERENCE   user_id is NULLABLE, and NULL means a seeded library row
--               shared by everyone (exercises, measurement_types). Read is
--               widened to include the shared rows; WRITE IS NOT. Seeded rows
--               are written by migration under the service role, which bypasses
--               RLS, so no client policy needs to admit them — and none does,
--               which is what stops one user editing the library out from
--               under everybody else.
--
-- auth.uid() is wrapped as (select auth.uid()) throughout. Postgres then
-- evaluates it once as an InitPlan instead of once per row; on a
-- history query over thousands of workout_sets that is the difference between
-- a scan and a scan plus a function call per row.
-- ============================================================================

alter table public.exercises             enable row level security;
alter table public.exercise_preferences  enable row level security;
alter table public.template_folders      enable row level security;
alter table public.templates             enable row level security;
alter table public.template_exercises    enable row level security;
alter table public.template_sets         enable row level security;
alter table public.workouts              enable row level security;
alter table public.workout_exercises     enable row level security;
alter table public.workout_sets          enable row level security;
alter table public.program_days          enable row level security;
alter table public.measurement_types     enable row level security;
alter table public.measurement_entries   enable row level security;


-- ----------------------------------------------------------------------------
-- Reference tables: read the shared library plus your own, write only your own
-- ----------------------------------------------------------------------------

create policy exercises_select on public.exercises
  for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));

-- `is_custom = true` is redundant with the exercises_custom_iff_owned
-- constraint, and stated anyway: this is the line that stops a client
-- inserting a row visible to every other user, and it should be readable as
-- such at the security boundary rather than inferred from a CHECK two files
-- away.
create policy exercises_insert on public.exercises
  for insert to authenticated
  with check (user_id = (select auth.uid()) and is_custom = true);

create policy exercises_update on public.exercises
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Deletes are soft (an UPDATE setting deleted_at), so this policy exists for
-- completeness rather than for the app's normal path. Hard deletes are the
-- purge job's business, and it runs as the service role.
create policy exercises_delete on public.exercises
  for delete to authenticated
  using (user_id = (select auth.uid()));


create policy measurement_types_select on public.measurement_types
  for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));

create policy measurement_types_insert on public.measurement_types
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy measurement_types_update on public.measurement_types
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy measurement_types_delete on public.measurement_types
  for delete to authenticated
  using (user_id = (select auth.uid()));


-- ----------------------------------------------------------------------------
-- Owned tables
--
-- Each gets the identical `for all` policy. Written out per table rather than
-- generated in a loop: a policy is the security boundary, and the cost of
-- reading eleven near-identical statements is much lower than the cost of a
-- loop that silently skips a table someone adds later.
--
-- Note the check is on the ROW's user_id only, never on a join to the parent.
-- A child row whose user_id disagreed with its parent's would be a bug, but a
-- policy that walked the parent chain would make every insert of a set do two
-- extra lookups, on the hottest write path in the app. The client sets user_id
-- on every row it creates; the parent chain is a data-integrity concern, not
-- an authorization one.
-- ----------------------------------------------------------------------------

create policy exercise_preferences_owner on public.exercise_preferences
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy template_folders_owner on public.template_folders
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy templates_owner on public.templates
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy template_exercises_owner on public.template_exercises
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy template_sets_owner on public.template_sets
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy workouts_owner on public.workouts
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy workout_exercises_owner on public.workout_exercises
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy workout_sets_owner on public.workout_sets
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy program_days_owner on public.program_days
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy measurement_entries_owner on public.measurement_entries
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));


-- ----------------------------------------------------------------------------
-- Grants
--
-- RLS filters rows; grants decide whether the role reaches the table at all.
-- Both are needed — RLS on a table the role has no SELECT on is moot, and a
-- grant without RLS is the leak this file exists to prevent.
--
-- `anon` is revoked explicitly. Nothing in this app is public: there is no
-- shared workout, no public profile, no unauthenticated read of the exercise
-- library. Supabase's default privileges grant anon access to new tables in
-- `public`, so leaving this out would quietly leave the seeded library, and
-- any future table added without thought, readable without a session.
-- ----------------------------------------------------------------------------

revoke all on all tables in schema public from anon;

grant select, insert, update, delete on all tables in schema public to authenticated;

-- Applies the same rule to tables added by later migrations, so a new table
-- does not arrive anon-readable by default.
alter default privileges in schema public revoke all on tables from anon;
