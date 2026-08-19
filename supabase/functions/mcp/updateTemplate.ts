import { z } from "npm:zod@4";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { logToolCall } from "./log.ts";
import {
  type BodyPart,
  type LibraryExercise,
} from "./types.ts";
import {
  buildTemplateRows,
  collisionInFolder,
  templateExerciseInput,
  templateWriteFields,
} from "./templateWrite.ts";

export const updateTemplateInput = z
  .object({
    id: z
      .string()
      .uuid()
      .describe(
        "Template UUID from get_templates. Never a name. Replacing exercises " +
          "rewrites the whole list — send the complete plan, not a delta.",
      ),
    name: templateWriteFields.name.optional(),
    folder_id: templateWriteFields.folder_id,
    note: templateWriteFields.note,
    weight_unit: templateWriteFields.weight_unit,
    exercises: z.array(templateExerciseInput).min(1).optional(),
  })
  .strict();

export type UpdateTemplateInput = z.infer<typeof updateTemplateInput>;

type ExerciseLibRow = {
  id: string;
  name: string;
  aliases: string[] | null;
  body_part: BodyPart;
  category: string;
};

type TemplateRow = {
  id: string;
  name: string;
  folder_id: string | null;
  note: string | null;
  sort_order: number;
};

type SlotRow = { id: string };

export async function updateTemplate(
  supabase: SupabaseClient,
  userId: string,
  args: UpdateTemplateInput,
): Promise<{
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}> {
  const started = performance.now();

  const { data, error } = await supabase
    .from("templates")
    .select("id, name, folder_id, note, sort_order")
    .is("deleted_at", null)
    .eq("id", args.id);

  if (error) {
    logToolCall({
      tool: "update_template",
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

  const current = ((data ?? []) as unknown as TemplateRow[])[0];
  if (!current) {
    logToolCall({
      tool: "update_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: "not_found",
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text:
          `No template with id ${args.id}. Call get_templates, then retry ` +
          `with that id. There is no update-by-name.`,
      }],
    };
  }

  const nextName = args.name?.trim() ?? current.name;
  if (args.name !== undefined && nextName.length === 0) {
    return {
      isError: true,
      content: [{ type: "text", text: "name must not be blank." }],
    };
  }
  const nextFolder = args.folder_id === undefined
    ? current.folder_id
    : args.folder_id;

  if (nextName !== current.name || nextFolder !== current.folder_id) {
    const { data: existing, error: existingError } = await supabase
      .from("templates")
      .select("id, name, folder_id")
      .is("deleted_at", null);
    if (existingError) {
      return {
        isError: true,
        content: [{
          type: "text",
          text: `Could not check existing templates: ${existingError.message}`,
        }],
      };
    }
    const collision = collisionInFolder(
      (existing ?? []) as unknown as Array<{
        id: string;
        name: string;
        folder_id: string | null;
      }>,
      nextName,
      nextFolder,
      current.id,
    );
    if (collision) {
      logToolCall({
        tool: "update_template",
        outcome: "error",
        duration_ms: Math.round(performance.now() - started),
        reason: "name_collision",
      });
      return {
        isError: true,
        content: [{
          type: "text",
          text:
            `A template named ${JSON.stringify(nextName)} already exists in ` +
            `that folder (id ${collision.id}).`,
        }],
        structuredContent: { existing_id: collision.id },
      };
    }
  }

  const now = new Date().toISOString();
  let matched_to_existing: string[] = [];
  let exerciseCount = 0;
  let setCount = 0;

  if (args.exercises) {
    const { data: libData, error: libError } = await supabase
      .from("exercises")
      .select("id, name, aliases, body_part, category")
      .is("deleted_at", null);
    if (libError) {
      return {
        isError: true,
        content: [{
          type: "text",
          text: `Could not read the exercise library: ${libError.message}`,
        }],
      };
    }
    const library: LibraryExercise[] =
      ((libData ?? []) as unknown as ExerciseLibRow[]).map((row) => ({
        id: row.id,
        name: row.name,
        aliases: row.aliases ?? [],
        bodyPart: row.body_part,
        category: row.category as LibraryExercise["category"],
      }));

    const built = buildTemplateRows(
      {
        name: nextName,
        folder_id: nextFolder ?? undefined,
        note: args.note ?? current.note ?? undefined,
        weight_unit: args.weight_unit,
        exercises: args.exercises,
      },
      library,
      {
        userId,
        templateId: current.id,
        sortOrder: current.sort_order,
        now,
        newId: () => crypto.randomUUID(),
      },
    );
    if (!built.ok) {
      logToolCall({
        tool: "update_template",
        outcome: "error",
        duration_ms: Math.round(performance.now() - started),
        reason: built.reason,
      });
      return {
        isError: true,
        content: [{ type: "text", text: built.content }],
        structuredContent: {
          reason: built.reason,
          ...built.extra,
          ignored_fields: [] as string[],
        },
      };
    }

    const { data: oldSlots, error: slotError } = await supabase
      .from("template_exercises")
      .select("id")
      .eq("template_id", current.id)
      .is("deleted_at", null);
    if (slotError) {
      return {
        isError: true,
        content: [{
          type: "text",
          text: `Could not read existing exercises: ${slotError.message}`,
        }],
      };
    }
    const oldIds = ((oldSlots ?? []) as unknown as SlotRow[]).map((row) =>
      row.id
    );

    const { error: exerciseError } = await supabase
      .from("template_exercises")
      .insert(built.exercises);
    if (exerciseError) {
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
      await supabase
        .from("template_exercises")
        .update({ deleted_at: now, updated_at: now })
        .in("id", built.exercises.map((row) => row.id));
      return {
        isError: true,
        content: [{
          type: "text",
          text: `Could not write template sets: ${setError.message}`,
        }],
      };
    }

    if (oldIds.length > 0) {
      await supabase
        .from("template_sets")
        .update({ deleted_at: now, updated_at: now })
        .in("template_exercise_id", oldIds)
        .is("deleted_at", null);
      await supabase
        .from("template_exercises")
        .update({ deleted_at: now, updated_at: now })
        .in("id", oldIds);
    }

    matched_to_existing = built.matched_to_existing;
    exerciseCount = built.exercises.length;
    setCount = built.sets.length;
  }

  const { error: updateError } = await supabase
    .from("templates")
    .update({
      name: nextName,
      folder_id: nextFolder,
      note: args.note === undefined ? current.note : args.note,
      updated_at: now,
    })
    .eq("id", current.id);

  if (updateError) {
    logToolCall({
      tool: "update_template",
      outcome: "error",
      duration_ms: Math.round(performance.now() - started),
      reason: updateError.message,
    });
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Could not update the template: ${updateError.message}`,
      }],
    };
  }

  const payload = {
    updated: true,
    template_id: current.id,
    name: nextName,
    matched_to_existing,
    exercise_count: args.exercises ? exerciseCount : null,
    set_count: args.exercises ? setCount : null,
    ignored_fields: [] as string[],
  };
  logToolCall({
    tool: "update_template",
    outcome: "ok",
    duration_ms: Math.round(performance.now() - started),
    replaced_exercises: Boolean(args.exercises),
  });
  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
    structuredContent: payload,
  };
}
