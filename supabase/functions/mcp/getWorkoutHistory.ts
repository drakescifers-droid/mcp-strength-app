import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { logToolCall } from "./log.ts";
import {
  BODY_PARTS,
  EXERCISE_CATEGORIES,
  SET_TYPES,
} from "./types.ts";
import {
  byOrder,
  loadWorkoutChildren,
  parseLimit,
  parseTimeBound,
  publicWorkoutExercise,
  type WorkoutRow,
} from "./workoutRead.ts";

export const getWorkoutHistoryInput = z
  .object({
    id: z
      .string()
      .uuid()
      .optional()
      .describe(
        "Fetch one completed workout by UUID. When set, from / to / " +
          "template_id / limit are ignored. There is no name lookup — " +
          "workout names are copied from templates and collide.",
      ),
    from: z
      .string()
      .optional()
      .describe(
        "Inclusive start of the window. YYYY-MM-DD (UTC day) or an ISO " +
          "timestamp. Omit to start from the earliest completed session.",
      ),
    to: z
      .string()
      .optional()
      .describe(
        "Inclusive end of the window. YYYY-MM-DD (UTC day) or an ISO " +
          "timestamp. Omit to include the most recent completed session.",
      ),
    template_id: z
      .string()
      .uuid()
      .optional()
      .describe("Hard filter: only sessions started from this template."),
    limit: z
      .number()
      .int()
      .min(1)
      .max(50)
      .optional()
      .describe("Newest-first cap. Default 20, maximum 50."),
  })
  .strict();

export type GetWorkoutHistoryInput = z.infer<typeof getWorkoutHistoryInput>;

const historySetSchema = z
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

const historyExerciseSchema = z
  .object({
    id: z.string(),
    sort_order: z.number(),
    exercise_id: z.string().nullable(),
    exercise_name: z.string().nullable(),
    body_part: z.enum(BODY_PARTS).nullable(),
    category: z.enum(EXERCISE_CATEGORIES).nullable(),
    superset_group_id: z.string().nullable(),
    note: z.string().nullable(),
    sticky_note: z.string().nullable(),
    sets: z.array(historySetSchema),
  })
  .strict();

export const getWorkoutHistoryOutput = z
  .object({
    workouts: z.array(
      z
        .object({
          id: z.string(),
          name: z.string(),
          template_id: z.string().nullable(),
          started_at: z.string(),
          completed_at: z.string().nullable(),
          duration_seconds: z.number(),
          note: z.string().nullable(),
          summary: z.string().nullable(),
          total_volume: z.number(),
          weight_unit: z.literal("kg"),
          exercises: z.array(historyExerciseSchema),
        })
        .strict(),
    ),
    truncated: z.boolean(),
    ignored_fields: z.array(z.string()),
  })
  .strict();

function toolError(message: string) {
  return {
    isError: true as const,
    content: [{ type: "text" as const, text: message }],
  };
}

export async function getWorkoutHistory(
  supabase: SupabaseClient,
  args: GetWorkoutHistoryInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();
  const ignored: string[] = [];

  if (args.id) {
    if (args.from !== undefined) ignored.push("from");
    if (args.to !== undefined) ignored.push("to");
    if (args.template_id !== undefined) ignored.push("template_id");
    if (args.limit !== undefined) ignored.push("limit");
  }

  const parsedLimit = parseLimit(args.limit);
  if ("error" in parsedLimit) {
    return toolError(parsedLimit.error);
  }

  let fromIso: string | undefined;
  let toIso: string | undefined;
  if (!args.id) {
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
  }

  let query = supabase
    .from("workouts")
    .select(
      "id, name, template_id, started_at, completed_at, duration_seconds, " +
        "note, summary, total_volume, deleted_at",
    )
    .is("deleted_at", null)
    .not("completed_at", "is", null);

  if (args.id) {
    query = query.eq("id", args.id);
  } else {
    if (fromIso) query = query.gte("started_at", fromIso);
    if (toIso) query = query.lte("started_at", toIso);
    if (args.template_id) query = query.eq("template_id", args.template_id);
    query = query
      .order("started_at", { ascending: false })
      .limit(parsedLimit.limit + 1);
  }

  const { data, error } = await query;
  if (error) {
    logToolCall({
      tool: "get_workout_history",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: error.message,
    });
    return toolError(`Could not read workout history: ${error.message}`);
  }

  let rows = (data ?? []) as unknown as WorkoutRow[];
  if (args.id && rows.length === 0) {
    logToolCall({
      tool: "get_workout_history",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "not_found",
    });
    return toolError(
      `No completed workout with id ${args.id}. Unfinished sessions are ` +
        `not history — they never leave the phone. Call get_workout_history ` +
        `without id to list recent sessions.`,
    );
  }

  let truncated = false;
  if (!args.id && rows.length > parsedLimit.limit) {
    truncated = true;
    rows = rows.slice(0, parsedLimit.limit);
  }
  if (!args.id) {
    rows.sort((a, b) =>
      a.started_at === b.started_at
        ? (a.id < b.id ? 1 : -1)
        : (a.started_at < b.started_at ? 1 : -1)
    );
  }

  const children = await loadWorkoutChildren(
    supabase,
    rows.map((row) => row.id),
  );
  if ("error" in children) {
    logToolCall({
      tool: "get_workout_history",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: children.error,
    });
    return toolError(`Could not read workout history: ${children.error}`);
  }

  const exercisesByWorkout = new Map<string, typeof children.exercises>();
  for (const row of children.exercises) {
    const list = exercisesByWorkout.get(row.workout_id) ?? [];
    list.push(row);
    exercisesByWorkout.set(row.workout_id, list);
  }
  for (const list of exercisesByWorkout.values()) list.sort(byOrder);

  const payload = {
    workouts: rows.map((workout) => ({
      id: workout.id,
      name: workout.name,
      template_id: workout.template_id,
      started_at: workout.started_at,
      completed_at: workout.completed_at,
      duration_seconds: workout.duration_seconds,
      note: workout.note,
      summary: workout.summary,
      total_volume: workout.total_volume,
      weight_unit: "kg" as const,
      exercises: (exercisesByWorkout.get(workout.id) ?? []).map((slot) => {
        const lib = slot.exercise_id
          ? children.libraryById.get(slot.exercise_id)
          : undefined;
        return publicWorkoutExercise(
          slot,
          lib,
          children.setsByExercise.get(slot.id) ?? [],
        );
      }),
    })),
    truncated,
    ignored_fields: ignored,
  };

  logToolCall({
    tool: "get_workout_history",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    result_count: payload.workouts.length,
    truncated,
    has_id: Boolean(args.id),
  });

  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
