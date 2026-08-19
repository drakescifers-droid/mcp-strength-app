import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { logToolCall } from "./log.ts";
import {
  type BodyPart,
  type LibraryExercise,
} from "./types.ts";
import {
  buildTemplateRows,
  collisionInFolder,
  createTemplateInput,
  type CreateTemplateInput,
} from "./templateWrite.ts";

export { createTemplateInput };
export type { CreateTemplateInput };

type ExerciseLibRow = {
  id: string;
  name: string;
  aliases: string[] | null;
  body_part: BodyPart;
  secondary_body_parts: BodyPart[] | null;
  category: string;
};

type TemplateNameRow = {
  id: string;
  name: string;
  folder_id: string | null;
  sort_order: number;
};

async function tombstoneWrite(
  supabase: SupabaseClient,
  templateId: string,
  exerciseIds: string[],
  now: string,
): Promise<void> {
  if (exerciseIds.length > 0) {
    await supabase
      .from("template_sets")
      .update({ deleted_at: now, updated_at: now })
      .in("template_exercise_id", exerciseIds)
      .is("deleted_at", null);
    await supabase
      .from("template_exercises")
      .update({ deleted_at: now, updated_at: now })
      .eq("template_id", templateId)
      .is("deleted_at", null);
  }
  await supabase
    .from("templates")
    .update({ deleted_at: now, updated_at: now })
    .eq("id", templateId);
}

export async function createTemplate(
  supabase: SupabaseClient,
  userId: string,
  args: CreateTemplateInput,
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

  const folderId = args.folder_id ?? null;

  const { data: existing, error: existingError } = await supabase
    .from("templates")
    .select("id, name, folder_id, sort_order")
    .is("deleted_at", null);

  if (existingError) {
    logToolCall({
      tool: "create_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: existingError.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not check existing templates: ${existingError.message}`,
      }],
    };
  }

  const collision = collisionInFolder(
    (existing ?? []) as unknown as TemplateNameRow[],
    name,
    folderId,
  );
  if (collision) {
    logToolCall({
      tool: "create_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "name_collision",
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text:
          `A template named ${JSON.stringify(name)} already exists in that ` +
          `folder (id ${collision.id}). Call update_template with that id ` +
          `instead of creating a duplicate.`,
      }],
      structuredContent: {
        created: false,
        existing_id: collision.id,
        name: collision.name,
      },
    };
  }

  const { data: libData, error: libError } = await supabase
    .from("exercises")
    .select("id, name, aliases, body_part, secondary_body_parts, category")
    .is("deleted_at", null);

  if (libError) {
    logToolCall({
      tool: "create_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: libError.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not read the exercise library: ${libError.message}`,
      }],
    };
  }

  const library: LibraryExercise[] = ((libData ?? []) as unknown as ExerciseLibRow[])
    .map((row) => ({
      id: row.id,
      name: row.name,
      aliases: row.aliases ?? [],
      bodyPart: row.body_part,
      secondaryBodyParts: row.secondary_body_parts ?? [],
      category: row.category as LibraryExercise["category"],
    }));

  const nextSort = ((existing ?? []) as unknown as TemplateNameRow[])
    .filter((row) => row.folder_id === folderId)
    .reduce((max, row) => Math.max(max, row.sort_order + 1), 0);

  const now = new Date().toISOString();
  const built = buildTemplateRows(args, library, {
    userId,
    templateId: crypto.randomUUID(),
    sortOrder: nextSort,
    now,
    newId: () => crypto.randomUUID(),
  });

  if (!built.ok) {
    logToolCall({
      tool: "create_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: built.reason,
    });
    return {
      isError: true,
      content: [{ type: "text", text: built.content }],
      structuredContent: {
        created: false,
        reason: built.reason,
        ...built.extra,
        ignored_fields: [] as string[],
      },
    };
  }

  const { error: templateError } = await supabase
    .from("templates")
    .insert(built.template);
  if (templateError) {
    logToolCall({
      tool: "create_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: templateError.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not create the template: ${templateError.message}`,
      }],
    };
  }

  const { error: exerciseError } = await supabase
    .from("template_exercises")
    .insert(built.exercises);
  if (exerciseError) {
    await tombstoneWrite(
      supabase,
      built.template.id,
      built.exercises.map((row) => row.id),
      now,
    );
    logToolCall({
      tool: "create_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: exerciseError.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not write template exercises: ${exerciseError.message}`,
      }],
    };
  }

  const { error: setError } = await supabase
    .from("template_sets")
    .insert(built.sets);
  if (setError) {
    await tombstoneWrite(
      supabase,
      built.template.id,
      built.exercises.map((row) => row.id),
      now,
    );
    logToolCall({
      tool: "create_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: setError.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not write template sets: ${setError.message}`,
      }],
    };
  }

  const payload = {
    created: true,
    template_id: built.template.id,
    name: built.template.name,
    matched_to_existing: built.matched_to_existing,
    exercise_count: built.exercises.length,
    set_count: built.sets.length,
    weight_unit: built.weight_unit,
    ignored_fields: [] as string[],
  };
  logToolCall({
    tool: "create_template",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    created: true,
    exercise_count: payload.exercise_count,
    set_count: payload.set_count,
  });
  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
