import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { rank } from "./exerciseMatcher.ts";
import { logToolCall } from "./log.ts";
import {
  BODY_PARTS,
  EXERCISE_CATEGORIES,
  type BodyPart,
  type ExerciseCategory,
  type LibraryExercise,
} from "./types.ts";

const MAX_RESULTS = 50;

export const listExercisesInput = z
  .object({
    query: z
      .string()
      .optional()
      .describe(
        "Free-text name to search. Word order does not matter. Omit to list " +
          "the library (optionally filtered by category).",
      ),
    category: z
      .enum(EXERCISE_CATEGORIES)
      .optional()
      .describe(
        "Hard filter on equipment / movement type. This is how you answer " +
          "'what barbell movements do I have'. Unknown values are rejected, " +
          "never coerced.",
      ),
    body_part: z
      .enum(BODY_PARTS)
      .optional()
      .describe(
        "Hint that RANKS results, it never filters. Pass this when you " +
          "already know the movement's body part (a JM press is arms) so a " +
          "spelling collision cannot surface the wrong machine. Deadlift's " +
          "primary body part is back, and a legs hint must still return " +
          "it — matched via body_part OR secondary_body_parts.",
      ),
  })
  .strict();

export type ListExercisesInput = z.infer<typeof listExercisesInput>;

export const listExercisesOutput = z
  .object({
    exercises: z.array(
      z.object({
        id: z.string(),
        name: z.string(),
        aliases: z.array(z.string()),
        body_part: z.enum(BODY_PARTS),
        secondary_body_parts: z.array(z.enum(BODY_PARTS)),
        category: z.enum(EXERCISE_CATEGORIES),
        is_custom: z.boolean(),
      }).strict(),
    ),
    query: z.string().nullable(),
    category_filter: z.enum(EXERCISE_CATEGORIES).nullable(),
    body_part_hint: z.enum(BODY_PARTS).nullable(),
    truncated: z.boolean(),
    ignored_fields: z.array(z.string()),
  })
  .strict();

type ExerciseRow = {
  id: string;
  name: string;
  aliases: string[] | null;
  body_part: BodyPart;
  secondary_body_parts: BodyPart[] | null;
  category: ExerciseCategory;
  is_custom: boolean;
};

export async function listExercises(
  supabase: SupabaseClient,
  args: ListExercisesInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();
  const { data, error } = await supabase
    .from("exercises")
    .select("id, name, aliases, body_part, secondary_body_parts, category, is_custom")
    .is("deleted_at", null);

  if (error) {
    logToolCall({
      tool: "list_exercises",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: error.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read the exercise library: ${error.message}`,
      }],
    };
  }

  const rows = (data ?? []) as ExerciseRow[];
  let library: LibraryExercise[] = rows.map((row) => ({
    id: row.id,
    name: row.name,
    aliases: row.aliases ?? [],
    bodyPart: row.body_part,
    secondaryBodyParts: row.secondary_body_parts ?? [],
    category: row.category,
  }));

  if (args.category) {
    library = library.filter((ex) => ex.category === args.category);
  }

  const query = args.query?.trim() ?? "";
  const hint = args.body_part ?? null;
  const matched = query.length === 0
    ? [...library].sort((a, b) =>
      a.name === b.name ? (a.id < b.id ? -1 : 1) : (a.name < b.name ? -1 : 1)
    )
    : rank(query, hint, library);

  const exercises = matched.slice(0, MAX_RESULTS).map((ex) => {
    const row = rows.find((r) => r.id === ex.id);
    return {
      id: ex.id,
      name: ex.name,
      aliases: ex.aliases,
      body_part: ex.bodyPart,
      secondary_body_parts: ex.secondaryBodyParts,
      category: ex.category,
      is_custom: row?.is_custom ?? false,
    };
  });

  const payload = {
    exercises,
    query: query.length === 0 ? null : query,
    category_filter: args.category ?? null,
    body_part_hint: hint,
    truncated: matched.length > MAX_RESULTS,
    ignored_fields: [] as string[],
  };

  logToolCall({
    tool: "list_exercises",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    result_count: exercises.length,
    truncated: payload.truncated,
    has_query: query.length > 0,
    category_filter: args.category ?? null,
    body_part_hint: hint,
  });

  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
