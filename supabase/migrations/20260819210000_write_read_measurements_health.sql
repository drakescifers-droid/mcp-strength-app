-- ----------------------------------------------------------------------------
-- app_settings.write_measurements_to_health
-- app_settings.read_measurements_from_health
--
-- The reference Apple Health screen (IMG_2996.PNG) has two measurement
-- toggles, separate from iOS permission and from the workouts toggle:
-- "Sync measurements originating from Strong to Apple Health" (write)
-- and "Measurements will be read from Apple Health" (read). iOS never
-- lets an app revoke its own Health permission, so without these flags
-- there is no way to turn either direction off from inside the app.
--
-- BOOLEAN, default TRUE, matching the reference (both toggles on) and
-- so a device that never touched the setting agrees with the row the
-- next device pulls. A client default of false would silently stop a
-- direction the user has been using.
--
-- Only four of eighteen seeded types exist in HealthKit. These flags
-- do not change that; they only gate the four that can travel.
--
-- ORDERING: apply and verify remote BEFORE a client that sends these
-- columns runs against the project. `app_settings` is FIRST in the
-- push order, so PostgREST rejecting an unknown column would abort
-- the entire sync run.
-- ----------------------------------------------------------------------------

alter table public.app_settings
  add column write_measurements_to_health boolean not null default true,
  add column read_measurements_from_health boolean not null default true;
