import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { logToolCall } from "./log.ts";

export const deleteTemplateInput = z
  .object({
    id: z
      .string()
      .uuid()
      .describe(
        "Template UUID from get_templates. There is no delete-by-name — " +
          "look up first. History performed from this template is kept.",
      ),
  })
  .strict();

export type DeleteTemplateInput = z.infer<typeof deleteTemplateInput>;

function toolError(message: string) {
  return {
    isError: true as const,
    content: [{ type: "text" as const, text: message }],
  };
}

export async function tombstoneTemplate(
  supabase: SupabaseClient,
  templateId: string,
  now: string,
): Promise<{ error: string | null }> {
  const { data: slots, error: slotError } = await supabase
    .from("template_exercises")
    .select("id")
    .eq("template_id", templateId)
    .is("deleted_at", null);
  if (slotError) return { error: slotError.message };

  const slotIds = ((slots ?? []) as Array<{ id: string }>).map((row) => row.id);
  if (slotIds.length > 0) {
    const { error: setError } = await supabase
      .from("template_sets")
      .update({ deleted_at: now, updated_at: now })
      .in("template_exercise_id", slotIds)
      .is("deleted_at", null);
    if (setError) return { error: setError.message };

    const { error: exerciseError } = await supabase
      .from("template_exercises")
      .update({ deleted_at: now, updated_at: now })
      .eq("template_id", templateId)
      .is("deleted_at", null);
    if (exerciseError) return { error: exerciseError.message };
  }

  const { error } = await supabase
    .from("templates")
    .update({ deleted_at: now, updated_at: now })
    .eq("id", templateId)
    .is("deleted_at", null);
  return { error: error?.message ?? null };
}

export async function deleteTemplate(
  supabase: SupabaseClient,
  args: DeleteTemplateInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();

  const { data, error } = await supabase
    .from("templates")
    .select("id, name, deleted_at")
    .eq("id", args.id);

  if (error) {
    logToolCall({
      tool: "delete_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: error.message,
    });
    return toolError(`Could not read the template: ${error.message}`);
  }

  const rows = (data ?? []) as Array<{
    id: string;
    name: string;
    deleted_at: string | null;
  }>;
  if (rows.length === 0) {
    logToolCall({
      tool: "delete_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "not_found",
    });
    return toolError(
      `No template with id ${args.id}. Call get_templates to look up the ` +
        `id. There is no delete-by-name.`,
    );
  }

  const row = rows[0];
  if (row.deleted_at !== null) {
    const payload = {
      deleted: true,
      already_deleted: true,
      id: row.id,
      name: row.name,
      ignored_fields: [] as string[],
    };
    logToolCall({
      tool: "delete_template",
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
  const tombstoned = await tombstoneTemplate(supabase, row.id, now);
  if (tombstoned.error) {
    logToolCall({
      tool: "delete_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: tombstoned.error,
    });
    return toolError(`Could not delete the template: ${tombstoned.error}`);
  }

  const payload = {
    deleted: true,
    already_deleted: false,
    id: row.id,
    name: row.name,
    ignored_fields: [] as string[],
  };
  logToolCall({
    tool: "delete_template",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    already_deleted: false,
  });
  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
