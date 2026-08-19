import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { logToolCall } from "./log.ts";
import { FOLDER_KINDS, type FolderKind } from "./types.ts";

export const getTemplatesInput = z
  .object({
    id: z
      .string()
      .uuid()
      .optional()
      .describe(
        "Stable template UUID. Use this when you already have an id from a " +
          "previous call. Mutating tools take ids, never a name.",
      ),
    name: z
      .string()
      .optional()
      .describe(
        "Lookup by template name. If several match, candidates are returned " +
          "and none is picked. Prefer id after the first lookup.",
      ),
    folder_id: z
      .string()
      .uuid()
      .optional()
      .describe("Hard filter: only templates in this folder."),
  })
  .strict();

export type GetTemplatesInput = z.infer<typeof getTemplatesInput>;

export const templateSummarySchema = z
  .object({
    id: z.string(),
    name: z.string(),
    folder_id: z.string().nullable(),
    folder_name: z.string().nullable(),
    folder_kind: z.enum(FOLDER_KINDS).nullable(),
    sort_order: z.number(),
    last_performed_at: z.string().nullable(),
    note: z.string().nullable(),
    exercise_count: z.number(),
  })
  .strict();

export const getTemplatesOutput = z
  .object({
    templates: z.array(templateSummarySchema),
    ambiguous: z.boolean(),
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
  deleted_at: string | null;
};

type FolderRow = {
  id: string;
  name: string;
  kind: FolderKind;
  sort_order: number;
  deleted_at: string | null;
};

type ExerciseCountRow = {
  id: string;
  template_id: string;
  deleted_at: string | null;
};

export type TemplateSummary = z.infer<typeof templateSummarySchema>;

function summaries(
  templates: TemplateRow[],
  folders: FolderRow[],
  exerciseRows: ExerciseCountRow[],
): TemplateSummary[] {
  const folderById = new Map(folders.map((f) => [f.id, f]));
  const countByTemplate = new Map<string, number>();
  for (const row of exerciseRows) {
    if (row.deleted_at !== null) continue;
    countByTemplate.set(
      row.template_id,
      (countByTemplate.get(row.template_id) ?? 0) + 1,
    );
  }
  const list = templates.map((row) => {
    const folder = row.folder_id ? folderById.get(row.folder_id) ?? null : null;
    return {
      id: row.id,
      name: row.name,
      folder_id: row.folder_id,
      folder_name: folder?.name ?? null,
      folder_kind: folder?.kind ?? null,
      sort_order: row.sort_order,
      last_performed_at: row.last_performed_at,
      note: row.note,
      exercise_count: countByTemplate.get(row.id) ?? 0,
    };
  });
  list.sort((a, b) => {
    const fa = a.folder_id === null ? -1 : (folderById.get(a.folder_id)?.sort_order ?? 0);
    const fb = b.folder_id === null ? -1 : (folderById.get(b.folder_id)?.sort_order ?? 0);
    if (fa !== fb) return fa - fb;
    if (a.sort_order !== b.sort_order) return a.sort_order - b.sort_order;
    return a.name < b.name ? -1 : a.name > b.name ? 1 : (a.id < b.id ? -1 : 1);
  });
  return list;
}

function lookupByName(
  rows: TemplateSummary[],
  name: string,
): { matches: TemplateSummary[]; ambiguous: boolean } {
  const needle = name.trim().toLowerCase();
  const exact = rows.filter((t) => t.name.toLowerCase() === needle);
  if (exact.length === 1) return { matches: exact, ambiguous: false };
  if (exact.length > 1) return { matches: exact, ambiguous: true };
  const partial = rows.filter((t) => t.name.toLowerCase().includes(needle));
  if (partial.length > 1) return { matches: partial, ambiguous: true };
  return { matches: partial, ambiguous: false };
}

export async function getTemplates(
  supabase: SupabaseClient,
  args: GetTemplatesInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();
  const ignored: string[] = [];
  if (args.id && args.name !== undefined) ignored.push("name");

  const templateQuery = supabase
    .from("templates")
    .select(
      "id, name, folder_id, note, sort_order, last_performed_at, deleted_at",
    )
    .is("deleted_at", null);

  const { data, error } = args.id
    ? await templateQuery.eq("id", args.id)
    : args.folder_id
    ? await templateQuery.eq("folder_id", args.folder_id)
    : await templateQuery;

  if (error) {
    logToolCall({
      tool: "get_templates",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: error.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read templates: ${error.message}`,
      }],
    };
  }

  const templates = (data ?? []) as unknown as TemplateRow[];
  if (args.id && templates.length === 0) {
    logToolCall({
      tool: "get_templates",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "not_found",
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text:
          `No template with id ${args.id}. Call get_templates without id to ` +
          `list, then retry with an id from that list.`,
      }],
    };
  }

  const folderIds = [
    ...new Set(
      templates.map((t) => t.folder_id).filter((id): id is string => id !== null),
    ),
  ];
  const templateIds = templates.map((t) => t.id);

  const folderQuery = folderIds.length === 0
    ? Promise.resolve({ data: [] as FolderRow[], error: null })
    : supabase
      .from("template_folders")
      .select("id, name, kind, sort_order, deleted_at")
      .in("id", folderIds)
      .is("deleted_at", null);

  const exerciseQuery = templateIds.length === 0
    ? Promise.resolve({ data: [] as ExerciseCountRow[], error: null })
    : supabase
      .from("template_exercises")
      .select("id, template_id, deleted_at")
      .in("template_id", templateIds);

  const [foldersResult, exercisesResult] = await Promise.all([
    folderQuery,
    exerciseQuery,
  ]);

  if (foldersResult.error) {
    logToolCall({
      tool: "get_templates",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: foldersResult.error.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read folders: ${foldersResult.error.message}`,
      }],
    };
  }
  if (exercisesResult.error) {
    logToolCall({
      tool: "get_templates",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: exercisesResult.error.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read template exercises: ${exercisesResult.error.message}`,
      }],
    };
  }

  let listed = summaries(
    templates,
    (foldersResult.data ?? []) as unknown as FolderRow[],
    (exercisesResult.data ?? []) as unknown as ExerciseCountRow[],
  );
  let ambiguous = false;

  if (!args.id && args.name !== undefined) {
    const needle = args.name.trim();
    if (needle.length === 0) {
      return {
        isError: true,
        content: [{ type: "text", text: "name must not be blank." }],
      };
    }
    const looked = lookupByName(listed, needle);
    listed = looked.matches;
    ambiguous = looked.ambiguous;
  }

  const payload = {
    templates: listed,
    ambiguous,
    ignored_fields: ignored,
  };

  logToolCall({
    tool: "get_templates",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    result_count: listed.length,
    ambiguous,
    has_id: Boolean(args.id),
    has_name: args.name !== undefined && !args.id,
  });

  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
