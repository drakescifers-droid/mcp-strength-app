import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { logToolCall } from "./log.ts";

export const deleteProgramInput = z
  .object({
    id: z
      .string()
      .uuid()
      .describe(
        "Program folder UUID. There is no delete-by-name. Templates the " +
          "program pointed at survive and become unfiled; only the rotation " +
          "is removed.",
      ),
  })
  .strict();

export type DeleteProgramInput = z.infer<typeof deleteProgramInput>;

function toolError(message: string) {
  return {
    isError: true as const,
    content: [{ type: "text" as const, text: message }],
  };
}

export async function tombstoneProgram(
  supabase: SupabaseClient,
  folderId: string,
  now: string,
): Promise<{ error: string | null }> {
  const { error: dayError } = await supabase
    .from("program_days")
    .update({ deleted_at: now, updated_at: now })
    .eq("folder_id", folderId)
    .is("deleted_at", null);
  if (dayError) return { error: dayError.message };

  const { error } = await supabase
    .from("template_folders")
    .update({ deleted_at: now, updated_at: now })
    .eq("id", folderId)
    .is("deleted_at", null);
  return { error: error?.message ?? null };
}

export async function deleteProgram(
  supabase: SupabaseClient,
  args: DeleteProgramInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();

  const { data, error } = await supabase
    .from("template_folders")
    .select("id, name, kind, deleted_at")
    .eq("id", args.id);

  if (error) {
    logToolCall({
      tool: "delete_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: error.message,
    });
    return toolError(`Could not read the program: ${error.message}`);
  }

  const rows = (data ?? []) as Array<{
    id: string;
    name: string;
    kind: string;
    deleted_at: string | null;
  }>;
  if (rows.length === 0) {
    logToolCall({
      tool: "delete_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "not_found",
    });
    return toolError(
      `No program with id ${args.id}. Call get_templates to see folder ids. ` +
        `There is no delete-by-name.`,
    );
  }

  const row = rows[0];
  if (row.kind !== "program") {
    logToolCall({
      tool: "delete_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "not_a_program",
    });
    return toolError(
      `Id ${args.id} is a folder named ${JSON.stringify(row.name)}, not a ` +
        `program. delete_program only removes programs. There is no ` +
        `delete_folder tool.`,
    );
  }

  const { data: templateRows, error: templateError } = await supabase
    .from("templates")
    .select("id")
    .eq("folder_id", row.id)
    .is("deleted_at", null);
  if (templateError) {
    logToolCall({
      tool: "delete_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: templateError.message,
    });
    return toolError(`Could not read program templates: ${templateError.message}`);
  }
  const templatesSurvived = (templateRows ?? []).length;

  if (row.deleted_at !== null) {
    const payload = {
      deleted: true,
      already_deleted: true,
      id: row.id,
      name: row.name,
      templates_survived: templatesSurvived,
      ignored_fields: [] as string[],
    };
    logToolCall({
      tool: "delete_program",
      outcome: "ok",
      duration_ms: Math.round(performance.now() - started),
      already_deleted: true,
    });
    return {
      content: [{ type: "text", text: JSON.stringify(payload) }],
      structuredContent: payload,
    };
  }

  const now = new Date().toISOString();
  const tombstoned = await tombstoneProgram(supabase, row.id, now);
  if (tombstoned.error) {
    logToolCall({
      tool: "delete_program",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: tombstoned.error,
    });
    return toolError(`Could not delete the program: ${tombstoned.error}`);
  }

  const payload = {
    deleted: true,
    already_deleted: false,
    id: row.id,
    name: row.name,
    templates_survived: templatesSurvived,
    ignored_fields: [] as string[],
  };
  logToolCall({
    tool: "delete_program",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    already_deleted: false,
    templates_survived: templatesSurvived,
  });
  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
