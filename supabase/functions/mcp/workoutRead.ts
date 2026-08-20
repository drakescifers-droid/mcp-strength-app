// Shared read-side helpers for the two history tools.
// Notes, sticky notes, and workout.summary all travel — a history response
// that omits them has thrown away the explanation for its own numbers
// (docs/03-mcp-tools.md). Weights are kilograms, the stored unit.
// set_type is dropSet / restPause, never drop_set / rest_pause.

import type { SupabaseClient } from "npm:@supabase/supabase-js";
import {
  type BodyPart,
  type ExerciseCategory,
  type SetType,
} from "./types.ts";

export const DEFAULT_LIMIT = 20;
export const MAX_LIMIT = 50;

export type WorkoutRow = {
  id: string;
  name: string;
  template_id: string | null;
  started_at: string;
  completed_at: string | null;
  duration_seconds: number;
  note: string | null;
  summary: string | null;
  total_volume: number;
  deleted_at: string | null;
};

export type WorkoutExerciseRow = {
  id: string;
  workout_id: string;
  exercise_id: string | null;
  sort_order: number;
  superset_group_id: string | null;
  note: string | null;
  sticky_note: string | null;
  deleted_at: string | null;
};

export type WorkoutSetRow = {
  id: string;
  workout_exercise_id: string;
  sort_order: number;
  set_type: SetType;
  weight: number | null;
  reps: number | null;
  rpe: number | null;
  distance: number | null;
  duration_seconds: number | null;
  rest_seconds: number;
  is_completed: boolean;
  deleted_at: string | null;
};

export type LibraryRow = {
  id: string;
  name: string;
  body_part: BodyPart;
  secondary_body_parts: BodyPart[] | null;
  category: ExerciseCategory;
};

export function byOrder<T extends { sort_order: number; id: string }>(
  a: T,
  b: T,
): number {
  if (a.sort_order !== b.sort_order) return a.sort_order - b.sort_order;
  return a.id < b.id ? -1 : 1;
}

export function parseTimeBound(
  value: string,
  kind: "from" | "to",
): { iso: string } | { error: string } {
  const trimmed = value.trim();
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(trimmed);
  if (dateOnly) {
    const iso = kind === "from"
      ? `${trimmed}T00:00:00.000Z`
      : `${trimmed}T23:59:59.999Z`;
    if (Number.isNaN(Date.parse(iso))) {
      return {
        error:
          `${kind} is not a valid date. Use YYYY-MM-DD or an ISO timestamp.`,
      };
    }
    return { iso };
  }
  const ms = Date.parse(trimmed);
  if (Number.isNaN(ms)) {
    return {
      error: `${kind} is not a valid date. Use YYYY-MM-DD or an ISO timestamp.`,
    };
  }
  return { iso: new Date(ms).toISOString() };
}

export function parseLimit(
  raw: number | undefined,
): { limit: number } | { error: string } {
  if (raw === undefined) return { limit: DEFAULT_LIMIT };
  if (!Number.isInteger(raw) || raw < 1 || raw > MAX_LIMIT) {
    return { error: `limit must be an integer from 1 to ${MAX_LIMIT}.` };
  }
  return { limit: raw };
}

export function publicSet(set: WorkoutSetRow) {
  return {
    id: set.id,
    sort_order: set.sort_order,
    set_type: set.set_type,
    weight: set.weight,
    weight_unit: "kg" as const,
    reps: set.reps,
    rpe: set.rpe,
    distance: set.distance,
    duration_seconds: set.duration_seconds,
    rest_seconds: set.rest_seconds,
    is_completed: set.is_completed,
  };
}

export function publicWorkoutExercise(
  row: WorkoutExerciseRow,
  library: LibraryRow | undefined,
  sets: WorkoutSetRow[],
) {
  return {
    id: row.id,
    sort_order: row.sort_order,
    exercise_id: row.exercise_id,
    exercise_name: library?.name ?? null,
    body_part: library?.body_part ?? null,
    category: library?.category ?? null,
    superset_group_id: row.superset_group_id,
    note: row.note,
    sticky_note: row.sticky_note,
    sets: sets.map(publicSet),
  };
}

export async function loadWorkoutChildren(
  supabase: SupabaseClient,
  workoutIds: string[],
): Promise<
  | {
    exercises: WorkoutExerciseRow[];
    setsByExercise: Map<string, WorkoutSetRow[]>;
    libraryById: Map<string, LibraryRow>;
  }
  | { error: string }
> {
  if (workoutIds.length === 0) {
    return {
      exercises: [],
      setsByExercise: new Map(),
      libraryById: new Map(),
    };
  }

  const { data: exerciseData, error: exerciseError } = await supabase
    .from("workout_exercises")
    .select(
      "id, workout_id, exercise_id, sort_order, superset_group_id, note, " +
        "sticky_note, deleted_at",
    )
    .in("workout_id", workoutIds);

  if (exerciseError) return { error: exerciseError.message };

  const exercises = ((exerciseData ?? []) as unknown as WorkoutExerciseRow[])
    .filter((row) => row.deleted_at === null)
    .sort(byOrder);

  const slotIds = exercises.map((row) => row.id);
  const libraryIds = [
    ...new Set(
      exercises
        .map((row) => row.exercise_id)
        .filter((id): id is string => id !== null),
    ),
  ];

  const setsQuery = slotIds.length === 0
    ? Promise.resolve({ data: [] as WorkoutSetRow[], error: null })
    : supabase
      .from("workout_sets")
      .select(
        "id, workout_exercise_id, sort_order, set_type, weight, reps, rpe, " +
          "distance, duration_seconds, rest_seconds, is_completed, deleted_at",
      )
      .in("workout_exercise_id", slotIds);

  const libraryQuery = libraryIds.length === 0
    ? Promise.resolve({ data: [] as LibraryRow[], error: null })
    : supabase
      .from("exercises")
      .select("id, name, body_part, secondary_body_parts, category")
      .in("id", libraryIds);

  const [setsResult, libraryResult] = await Promise.all([
    setsQuery,
    libraryQuery,
  ]);

  if (setsResult.error) return { error: setsResult.error.message };
  if (libraryResult.error) return { error: libraryResult.error.message };

  const setsByExercise = new Map<string, WorkoutSetRow[]>();
  for (const set of (setsResult.data ?? []) as unknown as WorkoutSetRow[]) {
    if (set.deleted_at !== null) continue;
    const list = setsByExercise.get(set.workout_exercise_id) ?? [];
    list.push(set);
    setsByExercise.set(set.workout_exercise_id, list);
  }
  for (const list of setsByExercise.values()) list.sort(byOrder);

  const libraryById = new Map(
    ((libraryResult.data ?? []) as unknown as LibraryRow[]).map((row) => [
      row.id,
      row,
    ]),
  );

  return { exercises, setsByExercise, libraryById };
}
