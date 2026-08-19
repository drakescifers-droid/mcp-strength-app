import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { logToolCall } from "./log.ts";
import {
  BODY_PARTS,
  EXERCISE_CATEGORIES,
  FOLDER_KINDS,
  SET_TYPES,
  type BodyPart,
  type ExerciseCategory,
  type FolderKind,
  type SetType,
} from "./types.ts";

export const getTemplateInput = z
  .object({
    id: z
      .string()
      .uuid()
      .describe(
        "Template UUID from get_templates. Writes later take this id. " +
          "There is no name argument — look up first if you only have a name.",
      ),
  })
  .strict();

export type GetTemplateInput = z.infer<typeof getTemplateInput>;

const templateSetSchema = z
  .object({
    id: z.string(),
    sort_order: z.number(),
    set_type: z.enum(SET_TYPES),
    weight: z.number().nullable(),
    weight_unit: z.literal("kg"),
    reps: z.number().nullable(),
    rep_range_start: z.number().nullable(),
    rep_range_end: z.number().nullable(),
    rpe: z.number().nullable(),
    distance: z.number().nullable(),
    duration_seconds: z.number().nullable(),
    rest_seconds: z.number(),
  })
  .strict();

const templateExerciseSchema = z
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
    default_rest_seconds: z.number(),
    sets: z.array(templateSetSchema),
  })
  .strict();

export const getTemplateOutput = z
  .object({
    template: z
      .object({
        id: z.string(),
        name: z.string(),
        folder_id: z.string().nullable(),
        folder_name: z.string().nullable(),
        folder_kind: z.enum(FOLDER_KINDS).nullable(),
        sort_order: z.number(),
        last_performed_at: z.string().nullable(),
        note: z.string().nullable(),
        weight_unit: z.literal("kg"),
        exercises: z.array(templateExerciseSchema),
      })
      .strict(),
    ignored_fields: z.array(z.string()),
  })
  .strict();

type TemplateRow = {
  id: string;
  name: string;
  folder_id: string | null;
  note: string | null;
  sort_order: number;
  last_performed_at: string | null;
};

type FolderRow = {
  id: string;
  name: string;
  kind: FolderKind;
};

type ExerciseRow = {
  id: string;
  template_id: string;
  exercise_id: string | null;
  sort_order: number;
  superset_group_id: string | null;
  note: string | null;
  sticky_note: string | null;
  default_rest_seconds: number;
  deleted_at: string | null;
};

type SetRow = {
  id: string;
  template_exercise_id: string;
  sort_order: number;
  set_type: SetType;
  weight: number | null;
  reps: number | null;
  rep_range_start: number | null;
  rep_range_end: number | null;
  rpe: number | null;
  distance: number | null;
  duration_seconds: number | null;
  rest_seconds: number;
  deleted_at: string | null;
};

type LibraryRow = {
  id: string;
  name: string;
  body_part: BodyPart;
  category: ExerciseCategory;
};

function byOrder<T extends { sort_order: number; id: string }>(a: T, b: T): number {
  if (a.sort_order !== b.sort_order) return a.sort_order - b.sort_order;
  return a.id < b.id ? -1 : 1;
}

export async function getTemplate(
  supabase: SupabaseClient,
  args: GetTemplateInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();

  const { data, error } = await supabase
    .from("templates")
    .select(
      "id, name, folder_id, note, sort_order, last_performed_at",
    )
    .is("deleted_at", null)
    .eq("id", args.id);

  if (error) {
    logToolCall({
      tool: "get_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: error.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read the template: ${error.message}`,
      }],
    };
  }

  const templates = (data ?? []) as unknown as TemplateRow[];
  if (templates.length === 0) {
    logToolCall({
      tool: "get_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "not_found",
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text:
          `No template with id ${args.id}. Call get_templates to look up ` +
          `the id, then retry. Writes take that id, never a name.`,
      }],
    };
  }

  const template = templates[0];

  const folderResult = template.folder_id
    ? await supabase
      .from("template_folders")
      .select("id, name, kind")
      .is("deleted_at", null)
      .eq("id", template.folder_id)
    : { data: [] as FolderRow[], error: null };

  if (folderResult.error) {
    logToolCall({
      tool: "get_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: folderResult.error.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read the folder: ${folderResult.error.message}`,
      }],
    };
  }

  const { data: exerciseData, error: exerciseError } = await supabase
    .from("template_exercises")
    .select(
      "id, template_id, exercise_id, sort_order, superset_group_id, note, " +
        "sticky_note, default_rest_seconds, deleted_at",
    )
    .eq("template_id", template.id);

  if (exerciseError) {
    logToolCall({
      tool: "get_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: exerciseError.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read template exercises: ${exerciseError.message}`,
      }],
    };
  }

  const exerciseRows = ((exerciseData ?? []) as unknown as ExerciseRow[])
    .filter((row) => row.deleted_at === null)
    .sort(byOrder);

  const exerciseSlotIds = exerciseRows.map((row) => row.id);
  const libraryIds = [
    ...new Set(
      exerciseRows
        .map((row) => row.exercise_id)
        .filter((id): id is string => id !== null),
    ),
  ];

  const setsQuery = exerciseSlotIds.length === 0
    ? Promise.resolve({ data: [] as SetRow[], error: null })
    : supabase
      .from("template_sets")
      .select(
        "id, template_exercise_id, sort_order, set_type, weight, reps, " +
          "rep_range_start, rep_range_end, rpe, distance, duration_seconds, " +
          "rest_seconds, deleted_at",
      )
      .in("template_exercise_id", exerciseSlotIds);

  const libraryQuery = libraryIds.length === 0
    ? Promise.resolve({ data: [] as LibraryRow[], error: null })
    : supabase
      .from("exercises")
      .select("id, name, body_part, category")
      .in("id", libraryIds);

  const [setsResult, libraryResult] = await Promise.all([
    setsQuery,
    libraryQuery,
  ]);

  if (setsResult.error) {
    logToolCall({
      tool: "get_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: setsResult.error.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read template sets: ${setsResult.error.message}`,
      }],
    };
  }
  if (libraryResult.error) {
    logToolCall({
      tool: "get_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: libraryResult.error.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read exercises: ${libraryResult.error.message}`,
      }],
    };
  }

  const setsByExercise = new Map<string, SetRow[]>();
  for (const set of (setsResult.data ?? []) as unknown as SetRow[]) {
    if (set.deleted_at !== null) continue;
    const list = setsByExercise.get(set.template_exercise_id) ?? [];
    list.push(set);
    setsByExercise.set(set.template_exercise_id, list);
  }
  for (const list of setsByExercise.values()) list.sort(byOrder);

  const libraryById = new Map(
    ((libraryResult.data ?? []) as unknown as LibraryRow[]).map((row) => [row.id, row]),
  );

  const folder = ((folderResult.data ?? []) as unknown as FolderRow[])[0] ?? null;

  const payload = {
    template: {
      id: template.id,
      name: template.name,
      folder_id: template.folder_id,
      folder_name: folder?.name ?? null,
      folder_kind: folder?.kind ?? null,
      sort_order: template.sort_order,
      last_performed_at: template.last_performed_at,
      note: template.note,
      weight_unit: "kg" as const,
      exercises: exerciseRows.map((row) => {
        const lib = row.exercise_id ? libraryById.get(row.exercise_id) : undefined;
        return {
          id: row.id,
          sort_order: row.sort_order,
          exercise_id: row.exercise_id,
          exercise_name: lib?.name ?? null,
          body_part: lib?.body_part ?? null,
          category: lib?.category ?? null,
          superset_group_id: row.superset_group_id,
          note: row.note,
          sticky_note: row.sticky_note,
          default_rest_seconds: row.default_rest_seconds,
          sets: (setsByExercise.get(row.id) ?? []).map((set) => ({
            id: set.id,
            sort_order: set.sort_order,
            set_type: set.set_type,
            weight: set.weight,
            weight_unit: "kg" as const,
            reps: set.reps,
            rep_range_start: set.rep_range_start,
            rep_range_end: set.rep_range_end,
            rpe: set.rpe,
            distance: set.distance,
            duration_seconds: set.duration_seconds,
            rest_seconds: set.rest_seconds,
          })),
        };
      }),
    },
    ignored_fields: [] as string[],
  };

  logToolCall({
    tool: "get_template",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    exercise_count: payload.template.exercises.length,
    set_count: payload.template.exercises.reduce(
      (n, ex) => n + ex.sets.length,
      0,
    ),
  });

  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
