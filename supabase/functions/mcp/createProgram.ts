import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { logToolCall } from "./log.ts";
import { tombstoneProgram } from "./deleteProgram.ts";
import { WEIGHT_UNITS, type WeightUnit } from "./types.ts";

const linearProgression = z
  .object({
    kind: z.literal("linear"),
    add_weight: z
      .number()
      .positive()
      .describe("Amount to add after hitting all prescribed reps."),
    weight_unit: z.enum(WEIGHT_UNITS).describe("kg or lbs. lb is not a value."),
  })
  .strict();

const noteProgression = z
  .object({
    kind: z.literal("note"),
    note: z
      .string()
      .min(1)
      .describe(
        "Prose the app will display, not execute. Use this for anything " +
          "that is not 'hit all reps → add X'.",
      ),
  })
  .strict();

const programDayInput = z
  .object({
    template_id: z
      .string()
      .uuid()
      .optional()
      .describe("Preferred. Days may repeat the same id (A, B, A)."),
    template_name: z
      .string()
      .optional()
      .describe(
        "Lookup only. Several matches write nothing. Prefer template_id " +
          "after the first call.",
      ),
    label: z
      .string()
      .optional()
      .describe('Advisory, e.g. "Day 1" or "Heavy Squat". Not a weekday.'),
  })
  .strict();

export const createProgramInput = z
  .object({
    name: z
      .string()
      .min(1)
      .describe("Program name. Errors if a live folder already has it."),
    days: z
      .array(programDayInput)
      .min(1)
      .describe(
        "The rotation, in order. May repeat templates. This is a cycle, " +
          "not a calendar — no weekdays.",
      ),
    total_cycles: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Omit to run indefinitely. 1 means the list plays once."),
    progression: z
      .union([linearProgression, noteProgression])
      .optional()
      .describe(
        "Optional. Linear is recorded as prose and NOT executed — the app " +
          "has no rules engine yet. The response says executed: false so " +
          "nobody thinks the load will auto-increase.",
      ),
  })
  .strict();

export type CreateProgramInput = z.infer<typeof createProgramInput>;

type TemplateRow = {
  id: string;
  name: string;
  folder_id: string | null;
  deleted_at: string | null;
};

type FolderRow = {
  id: string;
  name: string;
  kind: string;
  sort_order: number;
  deleted_at: string | null;
};

function toolError(
  message: string,
  extra?: Record<string, unknown>,
) {
  return {
    isError: true as const,
    content: [{ type: "text" as const, text: message }],
    structuredContent: extra,
  };
}

function lookupTemplate(
  rows: TemplateRow[],
  name: string,
): { matches: TemplateRow[]; ambiguous: boolean } {
  const needle = name.trim().toLowerCase();
  const exact = rows.filter((t) => t.name.toLowerCase() === needle);
  if (exact.length === 1) return { matches: exact, ambiguous: false };
  if (exact.length > 1) return { matches: exact, ambiguous: true };
  const partial = rows.filter((t) => t.name.toLowerCase().includes(needle));
  if (partial.length > 1) return { matches: partial, ambiguous: true };
  return { matches: partial, ambiguous: false };
}

function progressionWritten(
  progression: CreateProgramInput["progression"],
): {
  kind: "linear" | "note" | "none";
  executed: false;
  note: string | null;
  add_weight: number | null;
  weight_unit: WeightUnit | null;
} {
  if (progression === undefined) {
    return {
      kind: "none",
      executed: false,
      note: null,
      add_weight: null,
      weight_unit: null,
    };
  }
  if (progression.kind === "linear") {
    return {
      kind: "linear",
      executed: false,
      note:
        `Hit all prescribed reps → add ${progression.add_weight} ` +
        `${progression.weight_unit} next session. Recorded as prose; the ` +
        `app does not increase the load for you.`,
      add_weight: progression.add_weight,
      weight_unit: progression.weight_unit,
    };
  }
  return {
    kind: "note",
    executed: false,
    note: progression.note,
    add_weight: null,
    weight_unit: null,
  };
}

export async function createProgram(
  supabase: SupabaseClient,
  userId: string,
  args: CreateProgramInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();
  const name = args.name.trim();
  if (name.length === 0) {
    return toolError("name must not be blank.");
  }

  const { data: folderData, error: folderError } = await supabase
    .from("template_folders")
    .select("id, name, kind, sort_order, deleted_at")
    .is("deleted_at", null);

  if (folderError) {
    logToolCall({
      tool: "create_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: folderError.message,
    });
    return toolError(`Could not read folders: ${folderError.message}`);
  }

  const folders = (folderData ?? []) as FolderRow[];
  const collision = folders.find(
    (row) => row.name.toLowerCase() === name.toLowerCase(),
  );
  if (collision) {
    logToolCall({
      tool: "create_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "name_collision",
    });
    return toolError(
      `A ${collision.kind} named ${JSON.stringify(name)} already exists ` +
        `(id ${collision.id}). Use that id or pick a different name.`,
      {
        created: false,
        existing_id: collision.id,
        existing_kind: collision.kind,
        name: collision.name,
      },
    );
  }

  const { data: templateData, error: templateError } = await supabase
    .from("templates")
    .select("id, name, folder_id, deleted_at")
    .is("deleted_at", null);

  if (templateError) {
    logToolCall({
      tool: "create_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: templateError.message,
    });
    return toolError(`Could not read templates: ${templateError.message}`);
  }

  const templates = (templateData ?? []) as TemplateRow[];
  const byId = new Map(templates.map((row) => [row.id, row]));
  const resolved: Array<{
    template: TemplateRow;
    label: string | null;
  }> = [];
  const ignored: string[] = [];

  for (let i = 0; i < args.days.length; i++) {
    const day = args.days[i];
    if (day.template_id && day.template_name !== undefined) {
      ignored.push(`days[${i}].template_name`);
    }
    let template: TemplateRow | undefined;
    if (day.template_id) {
      template = byId.get(day.template_id);
      if (!template) {
        return toolError(
          `No live template with id ${day.template_id} (day ${i + 1}). ` +
            `Call get_templates, then retry. Nothing was written.`,
        );
      }
    } else if (day.template_name !== undefined) {
      const needle = day.template_name.trim();
      if (needle.length === 0) {
        return toolError(`days[${i}].template_name must not be blank.`);
      }
      const looked = lookupTemplate(templates, needle);
      if (looked.ambiguous || looked.matches.length !== 1) {
        const names = looked.matches.map((m) => `${m.name} (${m.id})`);
        return toolError(
          looked.matches.length === 0
            ? `No template matches ${JSON.stringify(needle)} (day ${i + 1}). ` +
              `Call get_templates, then retry with an id. Nothing was written.`
            : `Several templates match ${JSON.stringify(needle)} (day ${
              i + 1
            }): ${names.join(", ")}. Use a template_id. Nothing was written.`,
          {
            created: false,
            ambiguous: looked.matches.length > 1,
            candidates: looked.matches.map((m) => ({ id: m.id, name: m.name })),
          },
        );
      }
      template = looked.matches[0];
    } else {
      return toolError(
        `Day ${i + 1} needs template_id or template_name. Nothing was written.`,
      );
    }
    resolved.push({
      template,
      label: day.label?.trim() ? day.label.trim() : null,
    });
  }

  const sortOrder = folders.reduce(
    (max, row) => Math.max(max, row.sort_order + 1),
    0,
  );

  const now = new Date().toISOString();
  const folderId = crypto.randomUUID();
  const folderInsert = {
    id: folderId,
    user_id: userId,
    name,
    sort_order: sortOrder,
    is_collapsed: false,
    kind: "program",
    program_cursor: 0,
    total_cycles: args.total_cycles ?? null,
    updated_at: now,
  };

  const { error: insertFolderError } = await supabase
    .from("template_folders")
    .insert(folderInsert);
  if (insertFolderError) {
    logToolCall({
      tool: "create_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: insertFolderError.message,
    });
    return toolError(`Could not create the program: ${insertFolderError.message}`);
  }

  const dayRows = resolved.map((day, index) => ({
    id: crypto.randomUUID(),
    user_id: userId,
    folder_id: folderId,
    template_id: day.template.id,
    sort_order: index,
    label: day.label,
    updated_at: now,
  }));

  const { error: dayError } = await supabase
    .from("program_days")
    .insert(dayRows);
  if (dayError) {
    await tombstoneProgram(supabase, folderId, now);
    logToolCall({
      tool: "create_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: dayError.message,
    });
    return toolError(`Could not write program days: ${dayError.message}`);
  }

  const uniqueIds = [...new Set(resolved.map((day) => day.template.id))];
  const { error: fileError } = await supabase
    .from("templates")
    .update({ folder_id: folderId, updated_at: now })
    .in("id", uniqueIds)
    .is("deleted_at", null);
  if (fileError) {
    await tombstoneProgram(supabase, folderId, now);
    logToolCall({
      tool: "create_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: fileError.message,
    });
    return toolError(`Could not file templates into the program: ${fileError.message}`);
  }

  const written = progressionWritten(args.progression);
  const payload = {
    created: true,
    program_id: folderId,
    name,
    kind: "program" as const,
    total_cycles: args.total_cycles ?? null,
    program_cursor: 0,
    days: dayRows.map((day, index) => ({
      id: day.id,
      sort_order: day.sort_order,
      template_id: day.template_id,
      template_name: resolved[index].template.name,
      label: day.label,
    })),
    progression: written,
    ignored_fields: ignored,
  };

  logToolCall({
    tool: "create_program",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    created: true,
    day_count: dayRows.length,
    progression_kind: written.kind,
    progression_executed: false,
  });

  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
