import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { suggest } from "./exerciseMatcher.ts";
import { logToolCall } from "./log.ts";
import {
  BODY_PARTS,
  EXERCISE_CATEGORIES,
  type BodyPart,
  type ExerciseCategory,
  type LibraryExercise,
} from "./types.ts";

export const createExerciseInput = z
  .object({
    name: z
      .string()
      .min(1)
      .describe(
        "The exercise name. Matched against the library first (aliases and " +
          "word order). A close unique match is returned, not created.",
      ),
    body_part: z
      .enum(BODY_PARTS)
      .optional()
      .describe(
        "Required to CREATE a new row. Optional as a ranking hint when " +
          "matching. Unknown values are rejected, never coerced.",
      ),
    category: z
      .enum(EXERCISE_CATEGORIES)
      .optional()
      .describe(
        "Required to CREATE a new row. Equipment / movement type. Unknown " +
          "values are rejected, never coerced.",
      ),
    aliases: z
      .array(z.string())
      .optional()
      .describe("Alternate names stored only when a new row is created."),
  })
  .strict();

export type CreateExerciseInput = z.infer<typeof createExerciseInput>;

type ExerciseRow = {
  id: string;
  name: string;
  aliases: string[] | null;
  body_part: BodyPart;
  category: ExerciseCategory;
  is_custom: boolean;
};

function asLibrary(rows: ExerciseRow[]): LibraryExercise[] {
  return rows.map((row) => ({
    id: row.id,
    name: row.name,
    aliases: row.aliases ?? [],
    bodyPart: row.body_part,
    category: row.category,
  }));
}

function publicExercise(row: ExerciseRow) {
  return {
    id: row.id,
    name: row.name,
    aliases: row.aliases ?? [],
    body_part: row.body_part,
    category: row.category,
    is_custom: row.is_custom,
  };
}

export async function createExercise(
  supabase: SupabaseClient,
  userId: string,
  args: CreateExerciseInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();
  const name = args.name.trim();
  if (name.length === 0) {
    return {
      isError: true,
      content: [{ type: "text", text: "name must not be blank." }],
    };
  }

  const { data, error } = await supabase
    .from("exercises")
    .select("id, name, aliases, body_part, category, is_custom")
    .is("deleted_at", null);

  if (error) {
    logToolCall({
      tool: "create_exercise",
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
  const hint = args.body_part ?? null;
  const matches = suggest(name, hint, asLibrary(rows));

  if (matches.length === 1) {
    const existing = rows.find((r) => r.id === matches[0].id)!;
    const payload = {
      created: false,
      exercise: publicExercise(existing),
      matched_to_existing: [`${name} -> ${existing.name}`],
      ignored_fields: [] as string[],
    };
    logToolCall({
      tool: "create_exercise",
      outcome: "ok",
      duration_ms: Math.round(performance.now() - started),
      created: false,
      matched: true,
    });
    return {
      content: [{ type: "text", text: JSON.stringify(payload) }],
      structuredContent: payload,
    };
  }

  if (matches.length > 1) {
    const payload = {
      created: false,
      ambiguous: true,
      candidates: matches.map((m) => {
        const row = rows.find((r) => r.id === m.id)!;
        return publicExercise(row);
      }),
      message:
        "Several exercises match that name. Use one of these ids rather than creating a near-duplicate.",
      ignored_fields: [] as string[],
    };
    logToolCall({
      tool: "create_exercise",
      outcome: "ok",
      duration_ms: Math.round(performance.now() - started),
      created: false,
      ambiguous: true,
      candidate_count: matches.length,
    });
    return {
      content: [{ type: "text", text: JSON.stringify(payload) }],
      structuredContent: payload,
    };
  }

  if (args.body_part === undefined || args.category === undefined) {
    const missing = [
      args.body_part === undefined ? "body_part" : null,
      args.category === undefined ? "category" : null,
    ].filter((x): x is string => x !== null);
    logToolCall({
      tool: "create_exercise",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "missing_create_fields",
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text:
          `No library match for ${JSON.stringify(name)}. To create it, supply ` +
          `${missing.join(" and ")}. body_part must be one of: ${
            BODY_PARTS.join(", ")
          }. category must be one of: ${EXERCISE_CATEGORIES.join(", ")}.`,
      }],
    };
  }

  const insert = {
    id: crypto.randomUUID(),
    user_id: userId,
    name,
    aliases: args.aliases ?? [],
    body_part: args.body_part,
    category: args.category,
    is_custom: true,
    updated_at: new Date().toISOString(),
  };

  const { data: created, error: insertError } = await supabase
    .from("exercises")
    .insert(insert)
    .select("id, name, aliases, body_part, category, is_custom")
    .single();

  if (insertError || created === null) {
    logToolCall({
      tool: "create_exercise",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: insertError?.message ?? "insert returned nothing",
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not create the exercise: ${insertError?.message ?? "unknown error"}`,
      }],
    };
  }

  const row = created as ExerciseRow;
  const payload = {
    created: true,
    exercise: publicExercise(row),
    matched_to_existing: [] as string[],
    ignored_fields: [] as string[],
  };
  logToolCall({
    tool: "create_exercise",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    created: true,
  });
  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
