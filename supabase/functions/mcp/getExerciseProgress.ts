import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { suggest } from "./exerciseMatcher.ts";
import { logToolCall } from "./log.ts";
import {
  BODY_PARTS,
  EXERCISE_CATEGORIES,
  SET_TYPES,
  type LibraryExercise,
} from "./types.ts";
import {
  byOrder,
  parseLimit,
  parseTimeBound,
  publicSet,
  type LibraryRow,
  type WorkoutExerciseRow,
  type WorkoutRow,
  type WorkoutSetRow,
} from "./workoutRead.ts";

export const getExerciseProgressInput = z
  .object({
    exercise_id: z
      .string()
      .uuid()
      .optional()
      .describe(
        "Stable exercise UUID from list_exercises. Prefer this after the " +
          "first lookup — the library has many similarly named machines.",
      ),
    exercise_name: z
      .string()
      .optional()
      .describe(
        "Lookup by name. Several matches return candidates and no series. " +
          "Prefer exercise_id after the first call.",
      ),
    body_part: z
      .enum(BODY_PARTS)
      .optional()
      .describe(
        "Ranking hint for a name lookup, never a filter. Pass this when " +
          "you already know the movement (a JM press is arms).",
      ),
    from: z
      .string()
      .optional()
      .describe(
        "Inclusive start of the window. YYYY-MM-DD (UTC day) or an ISO " +
          "timestamp.",
      ),
    to: z
      .string()
      .optional()
      .describe(
        "Inclusive end of the window. YYYY-MM-DD (UTC day) or an ISO " +
          "timestamp.",
      ),
    limit: z
      .number()
      .int()
      .min(1)
      .max(50)
      .optional()
      .describe("Newest-first cap on sessions. Default 20, maximum 50."),
  })
  .strict();

export type GetExerciseProgressInput = z.infer<typeof getExerciseProgressInput>;

const progressSetSchema = z
  .object({
    id: z.string(),
    sort_order: z.number(),
    set_type: z.enum(SET_TYPES),
    weight: z.number().nullable(),
    weight_unit: z.literal("kg"),
    reps: z.number().nullable(),
    rpe: z.number().nullable(),
    distance: z.number().nullable(),
    duration_seconds: z.number().nullable(),
    rest_seconds: z.number(),
    is_completed: z.boolean(),
  })
  .strict();

const publicExerciseSchema = z
  .object({
    id: z.string(),
    name: z.string(),
    body_part: z.enum(BODY_PARTS),
    secondary_body_parts: z.array(z.enum(BODY_PARTS)),
    category: z.enum(EXERCISE_CATEGORIES),
  })
  .strict();

export const getExerciseProgressOutput = z
  .object({
    exercise: publicExerciseSchema.nullable(),
    sessions: z.array(
      z
        .object({
          workout_id: z.string(),
          workout_name: z.string(),
          started_at: z.string(),
          completed_at: z.string().nullable(),
          workout_note: z.string().nullable(),
          summary: z.string().nullable(),
          note: z.string().nullable(),
          sticky_note: z.string().nullable(),
          sets: z.array(progressSetSchema),
        })
        .strict(),
    ),
    ambiguous: z.boolean(),
    candidates: z.array(publicExerciseSchema),
    truncated: z.boolean(),
    ignored_fields: z.array(z.string()),
  })
  .strict();

type ExerciseLookupRow = LibraryRow & { aliases: string[] | null };

function asLibrary(rows: ExerciseLookupRow[]): LibraryExercise[] {
  return rows.map((row) => ({
    id: row.id,
    name: row.name,
    aliases: row.aliases ?? [],
    bodyPart: row.body_part,
    secondaryBodyParts: row.secondary_body_parts ?? [],
    category: row.category,
  }));
}

function publicExercise(row: LibraryRow) {
  return {
    id: row.id,
    name: row.name,
    body_part: row.body_part,
    secondary_body_parts: row.secondary_body_parts ?? [],
    category: row.category,
  };
}

function toolError(message: string) {
  return {
    isError: true as const,
    content: [{ type: "text" as const, text: message }],
  };
}

export async function getExerciseProgress(
  supabase: SupabaseClient,
  args: GetExerciseProgressInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();
  const ignored: string[] = [];

  if (args.exercise_id && args.exercise_name !== undefined) {
    ignored.push("exercise_name");
  }
  if (args.exercise_id && args.body_part !== undefined) {
    ignored.push("body_part");
  }

  if (!args.exercise_id && args.exercise_name === undefined) {
    return toolError(
      "Supply exercise_id or exercise_name. Call list_exercises first if " +
        "you only have a description — names like Lat Pulldown now have " +
        "several real rows.",
    );
  }

  const parsedLimit = parseLimit(args.limit);
  if ("error" in parsedLimit) return toolError(parsedLimit.error);

  let fromIso: string | undefined;
  let toIso: string | undefined;
  if (args.from !== undefined) {
    const parsed = parseTimeBound(args.from, "from");
    if ("error" in parsed) return toolError(parsed.error);
    fromIso = parsed.iso;
  }
  if (args.to !== undefined) {
    const parsed = parseTimeBound(args.to, "to");
    if ("error" in parsed) return toolError(parsed.error);
    toIso = parsed.iso;
  }
  if (fromIso && toIso && fromIso > toIso) {
    return toolError("from must be on or before to.");
  }

  const { data: libraryData, error: libraryError } = await supabase
    .from("exercises")
    .select("id, name, aliases, body_part, secondary_body_parts, category")
    .is("deleted_at", null);

  if (libraryError) {
    logToolCall({
      tool: "get_exercise_progress",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: libraryError.message,
    });
    return toolError(`Could not read the exercise library: ${libraryError.message}`);
  }

  const libraryRows = (libraryData ?? []) as unknown as ExerciseLookupRow[];

  let resolved: LibraryRow | null = null;
  let ambiguous = false;
  let candidates: ReturnType<typeof publicExercise>[] = [];

  if (args.exercise_id) {
    resolved = libraryRows.find((row) => row.id === args.exercise_id) ?? null;
    if (resolved === null) {
      logToolCall({
        tool: "get_exercise_progress",
        outcome: "error",
        duration_ms: Math.round(performance.now() - started),
        reason: "not_found",
      });
      return toolError(
        `No exercise with id ${args.exercise_id}. Call list_exercises to ` +
          `look up the id, then retry.`,
      );
    }
  } else {
    const name = args.exercise_name!.trim();
    if (name.length === 0) {
      return toolError("exercise_name must not be blank.");
    }
    const hint = args.body_part ?? null;
    const matches = suggest(name, hint, asLibrary(libraryRows));
    if (matches.length === 1) {
      resolved = libraryRows.find((row) => row.id === matches[0].id) ?? null;
    } else if (matches.length > 1) {
      ambiguous = true;
      candidates = matches.map((match) => {
        const row = libraryRows.find((r) => r.id === match.id)!;
        return publicExercise(row);
      });
      const payload = {
        exercise: null,
        sessions: [] as unknown[],
        ambiguous: true,
        candidates,
        truncated: false,
        ignored_fields: ignored,
      };
      logToolCall({
        tool: "get_exercise_progress",
        outcome: "ok",
        duration_ms: Math.round(performance.now() - started),
        ambiguous: true,
        candidate_count: candidates.length,
      });
      return {
        content: [{ type: "text", text: JSON.stringify(payload) }],
        structuredContent: payload,
      };
    } else {
      logToolCall({
        tool: "get_exercise_progress",
        outcome: "error",
        duration_ms: Math.round(performance.now() - started),
        reason: "not_found",
      });
      return toolError(
        `No library match for ${JSON.stringify(name)}. Call list_exercises ` +
          `to search, then retry with an exercise_id.`,
      );
    }
  }

  if (resolved === null) {
    return toolError("Could not resolve the exercise.");
  }

  const { data: slotData, error: slotError } = await supabase
    .from("workout_exercises")
    .select(
      "id, workout_id, exercise_id, sort_order, superset_group_id, note, " +
        "sticky_note, deleted_at",
    )
    .eq("exercise_id", resolved.id)
    .is("deleted_at", null);

  if (slotError) {
    logToolCall({
      tool: "get_exercise_progress",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: slotError.message,
    });
    return toolError(`Could not read exercise progress: ${slotError.message}`);
  }

  const slots = (slotData ?? []) as unknown as WorkoutExerciseRow[];
  const workoutIds = [...new Set(slots.map((row) => row.workout_id))];

  const workoutsQuery = workoutIds.length === 0
    ? Promise.resolve({ data: [] as WorkoutRow[], error: null })
    : supabase
      .from("workouts")
      .select(
        "id, name, template_id, started_at, completed_at, duration_seconds, " +
          "note, summary, total_volume, deleted_at",
      )
      .in("id", workoutIds)
      .is("deleted_at", null)
      .not("completed_at", "is", null);

  const { data: workoutData, error: workoutError } = await workoutsQuery;
  if (workoutError) {
    logToolCall({
      tool: "get_exercise_progress",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: workoutError.message,
    });
    return toolError(`Could not read exercise progress: ${workoutError.message}`);
  }

  let workouts = ((workoutData ?? []) as unknown as WorkoutRow[])
    .filter((row) => {
      if (fromIso && row.started_at < fromIso) return false;
      if (toIso && row.started_at > toIso) return false;
      return true;
    })
    .sort((a, b) =>
      a.started_at === b.started_at
        ? (a.id < b.id ? 1 : -1)
        : (a.started_at < b.started_at ? 1 : -1)
    );

  const truncated = workouts.length > parsedLimit.limit;
  workouts = workouts.slice(0, parsedLimit.limit);
  const keptWorkoutIds = new Set(workouts.map((row) => row.id));
  const keptSlots = slots.filter((row) => keptWorkoutIds.has(row.workout_id));
  const slotIds = keptSlots.map((row) => row.id);

  const setsQuery = slotIds.length === 0
    ? Promise.resolve({ data: [] as WorkoutSetRow[], error: null })
    : supabase
      .from("workout_sets")
      .select(
        "id, workout_exercise_id, sort_order, set_type, weight, reps, rpe, " +
          "distance, duration_seconds, rest_seconds, is_completed, deleted_at",
      )
      .in("workout_exercise_id", slotIds);

  const { data: setData, error: setError } = await setsQuery;
  if (setError) {
    logToolCall({
      tool: "get_exercise_progress",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: setError.message,
    });
    return toolError(`Could not read exercise progress: ${setError.message}`);
  }

  const setsBySlot = new Map<string, WorkoutSetRow[]>();
  for (const set of (setData ?? []) as unknown as WorkoutSetRow[]) {
    if (set.deleted_at !== null) continue;
    const list = setsBySlot.get(set.workout_exercise_id) ?? [];
    list.push(set);
    setsBySlot.set(set.workout_exercise_id, list);
  }
  for (const list of setsBySlot.values()) list.sort(byOrder);

  const slotsByWorkout = new Map<string, WorkoutExerciseRow[]>();
  for (const slot of keptSlots) {
    const list = slotsByWorkout.get(slot.workout_id) ?? [];
    list.push(slot);
    slotsByWorkout.set(slot.workout_id, list);
  }
  for (const list of slotsByWorkout.values()) list.sort(byOrder);

  const payload = {
    exercise: publicExercise(resolved),
    sessions: workouts.flatMap((workout) => {
      const slotsForWorkout = slotsByWorkout.get(workout.id) ?? [];
      return slotsForWorkout.map((slot) => ({
        workout_id: workout.id,
        workout_name: workout.name,
        started_at: workout.started_at,
        completed_at: workout.completed_at,
        workout_note: workout.note,
        summary: workout.summary,
        note: slot.note,
        sticky_note: slot.sticky_note,
        sets: (setsBySlot.get(slot.id) ?? []).map(publicSet),
      }));
    }),
    ambiguous,
    candidates,
    truncated,
    ignored_fields: ignored,
  };

  logToolCall({
    tool: "get_exercise_progress",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    result_count: payload.sessions.length,
    truncated,
    ambiguous: false,
  });

  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
