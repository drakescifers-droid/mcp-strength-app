-- ----------------------------------------------------------------------------
-- app_settings.write_workouts_to_health — the in-app switch for Health writes
--
-- The reference app's Apple Health screen has an explicit toggle, "Sync
-- workouts originating from Strong to Apple Health", separate from iOS's
-- permission. HealthStore.swift used to argue there should be no stored flag
-- because authorization already answers it. That reasoning is wrong for the
-- reference's model: iOS never lets an app revoke its own permission, so
-- without a toggle there is no way to turn the feature off from inside the
-- app at all. `None` on the calorie rate turns off energy, not workouts.
--
-- BOOLEAN, default TRUE, matching current behaviour and the reference (the
-- toggle is on). A client default of false against a server default of true
-- would mean a device that never touched the setting disagrees with the row
-- the next device pulls, and would silently stop writing workouts the user
-- has been sending.
--
-- ORDERING: apply and verify remote BEFORE a client that sends this column
-- runs against the project. `app_settings` is FIRST in the push order, so
-- PostgREST rejecting an unknown column would abort the entire sync run.
-- ----------------------------------------------------------------------------

alter table public.app_settings
  add column write_workouts_to_health boolean not null default true;
