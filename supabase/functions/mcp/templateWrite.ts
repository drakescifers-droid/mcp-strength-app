import { z } from "npm:zod@4";
import { suggest } from "./exerciseMatcher.ts";
import {
  BODY_PARTS,
  SET_TYPES,
  WEIGHT_UNITS,
  kilogramsFrom,
  type BodyPart,
  type LibraryExercise,
  type SetType,
  type WeightUnit,
} from "./types.ts";

export const templateSetInput = z
  .object({
    set_type: z
      .enum(SET_TYPES)
      .optional()
      .describe(
        "normal | warmup | dropSet | restPause | failure. drop_set, " +
          "rest_pause, and myoRep are not values and are rejected, not " +
          "coerced. Myo-reps use restPause. Omit for a working set " +
          "(normal). Omit reps when set_type is failure.",
      ),
    reps: z
      .number()
      .int()
      .positive()
      .optional()
      .describe(
        "Fixed rep target. Omit for failure sets, cardio/duration, or when " +
          "using a range. Do not send a range AND a fixed reps.",
      ),
    rep_range_start: z.number().int().positive().optional(),
    rep_range_end: z.number().int().positive().optional(),
    rpe: z
      .number()
      .optional()
      .describe("Prescribed RPE, 6 to 10 in half steps (7, 7.5, 8, …)."),
    weight: z
      .number()
      .optional()
      .describe(
        "In weight_unit on the parent call. Assisted bodyweight may be " +
          "negative. Stored as kilograms.",
      ),
    distance: z.number().nonnegative().optional(),
    duration_seconds: z.number().int().nonnegative().optional(),
    rest_seconds: z.number().int().nonnegative().optional(),
  })
  .strict();

export const templateExerciseInput = z
  .object({
    exercise_id: z.string().uuid().optional(),
    exercise_name: z
      .string()
      .optional()
      .describe(
        "Lookup in the library (aliases + word order). A unique match is " +
          "used; several matches write nothing. There is no silent create " +
          "of a library row from this tool — call create_exercise first.",
      ),
    body_part: z
      .enum(BODY_PARTS)
      .optional()
      .describe("Ranking hint for exercise_name, same as list_exercises."),
    superset_group: z
      .string()
      .optional()
      .describe(
        "Shared token for round-robin exercises, e.g. A. Same token → " +
          "same group. Stored as a UUID, not this letter.",
      ),
    note: z.string().optional().describe("Behind the exercise options menu."),
    sticky_note: z
      .string()
      .optional()
      .describe("Pinned under the exercise for the whole session."),
    default_rest_seconds: z.number().int().nonnegative().optional(),
    sets: z.array(templateSetInput).optional(),
    set_count: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Shorthand with reps: 4 and set_count 3 means 3×4 normal."),
    reps: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Shorthand with set_count. Do not combine with sets[]."),
  })
  .strict();

export const templateWriteFields = {
  name: z.string().min(1),
  folder_id: z.string().uuid().optional(),
  note: z.string().optional(),
  weight_unit: z
    .enum(WEIGHT_UNITS)
    .optional()
    .describe(
      "kg or lbs (Swift spelling). Required if any set has a weight. " +
        "lb is not a value. Stored as kilograms.",
    ),
  exercises: z.array(templateExerciseInput).min(1),
};

export const createTemplateInput = z.object(templateWriteFields).strict();

export type CreateTemplateInput = z.infer<typeof createTemplateInput>;
export type TemplateExerciseInput = z.infer<typeof templateExerciseInput>;
export type TemplateSetInput = z.infer<typeof templateSetInput>;

export type LibraryRow = LibraryExercise & { isCustom?: boolean };

export type UnresolvedExercise = {
  index: number;
  query: string;
  candidates: Array<{ id: string; name: string }>;
};

export type BuiltSet = {
  id: string;
  template_exercise_id: string;
  user_id: string;
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
  updated_at: string;
};

export type BuiltExercise = {
  id: string;
  user_id: string;
  template_id: string;
  exercise_id: string;
  sort_order: number;
  superset_group_id: string | null;
  note: string | null;
  sticky_note: string | null;
  default_rest_seconds: number;
  updated_at: string;
};

export type BuiltTemplate = {
  id: string;
  user_id: string;
  name: string;
  folder_id: string | null;
  note: string | null;
  sort_order: number;
  updated_at: string;
};

export type BuildOk = {
  ok: true;
  template: BuiltTemplate;
  exercises: BuiltExercise[];
  sets: BuiltSet[];
  matched_to_existing: string[];
  weight_unit: WeightUnit | null;
};

export type BuildFail = {
  ok: false;
  reason: string;
  content: string;
  extra?: Record<string, unknown>;
};

function legalRpe(value: number): boolean {
  return value >= 6 && value <= 10 && value * 2 === Math.trunc(value * 2);
}

function expandSets(exercise: TemplateExerciseInput): TemplateSetInput[] | BuildFail {
  const hasArray = exercise.sets !== undefined;
  const hasShorthand =
    exercise.set_count !== undefined || exercise.reps !== undefined;
  if (hasArray && hasShorthand) {
    return {
      ok: false,
      reason: "sets_and_shorthand",
      content:
        "Send either sets[] or set_count+reps, not both, on one exercise.",
    };
  }
  if (hasArray) {
    if (exercise.sets!.length === 0) {
      return {
        ok: false,
        reason: "empty_sets",
        content: "sets[] must not be empty. Omit it and use set_count+reps, or add set objects.",
      };
    }
    return exercise.sets!;
  }
  if (exercise.set_count !== undefined && exercise.reps !== undefined) {
    return Array.from({ length: exercise.set_count }, () => ({
      set_type: "normal" as const,
      reps: exercise.reps,
    }));
  }
  if (hasShorthand) {
    return {
      ok: false,
      reason: "incomplete_shorthand",
      content: "Shorthand needs both set_count and reps.",
    };
  }
  return {
    ok: false,
    reason: "missing_sets",
    content: "Each exercise needs sets[] or set_count+reps.",
  };
}

function validateSet(
  set: TemplateSetInput,
  index: string,
): BuildFail | null {
  const start = set.rep_range_start;
  const end = set.rep_range_end;
  if ((start === undefined) !== (end === undefined)) {
    return {
      ok: false,
      reason: "unpaired_range",
      content: `${index}: rep_range_start and rep_range_end must both be set, or neither.`,
    };
  }
  if (start !== undefined && end !== undefined && end < start) {
    return {
      ok: false,
      reason: "range_order",
      content: `${index}: rep_range_end must be >= rep_range_start.`,
    };
  }
  if (set.reps !== undefined && start !== undefined) {
    return {
      ok: false,
      reason: "reps_and_range",
      content: `${index}: a set uses fixed reps OR a range, never both.`,
    };
  }
  if (set.rpe !== undefined && !legalRpe(set.rpe)) {
    return {
      ok: false,
      reason: "bad_rpe",
      content: `${index}: rpe must be 6 to 10 in half steps (7, 7.5, 8, …).`,
    };
  }
  return null;
}

export function buildTemplateRows(
  args: {
    name: string;
    folder_id?: string;
    note?: string;
    weight_unit?: WeightUnit;
    exercises: TemplateExerciseInput[];
  },
  library: LibraryRow[],
  options: {
    userId: string;
    templateId: string;
    sortOrder: number;
    now: string;
    newId: () => string;
  },
): BuildOk | BuildFail {
  const needsUnit = args.exercises.some((exercise) => {
    const expanded = expandSets(exercise);
    if (!Array.isArray(expanded)) return false;
    return expanded.some((set) => set.weight !== undefined);
  });
  if (needsUnit && args.weight_unit === undefined) {
    return {
      ok: false,
      reason: "missing_weight_unit",
      content:
        "weight_unit is required when any set has a weight. Use kg or lbs " +
        "(not lb). Values are stored as kilograms.",
    };
  }

  const unresolved: UnresolvedExercise[] = [];
  const matched_to_existing: string[] = [];
  const resolvedIds: string[] = [];

  for (let i = 0; i < args.exercises.length; i++) {
    const exercise = args.exercises[i];
    if (exercise.exercise_id) {
      const row = library.find((item) => item.id === exercise.exercise_id);
      if (!row) {
        unresolved.push({
          index: i,
          query: exercise.exercise_id,
          candidates: [],
        });
        resolvedIds.push("");
        continue;
      }
      resolvedIds.push(row.id);
      continue;
    }
    const name = exercise.exercise_name?.trim() ?? "";
    if (name.length === 0) {
      return {
        ok: false,
        reason: "missing_exercise",
        content:
          `exercises[${i}] needs exercise_id or exercise_name. Writes use ids; ` +
          `names are lookup only.`,
      };
    }
    const hint = exercise.body_part ?? null;
    const matches = suggest(name, hint, library);
    if (matches.length === 1) {
      resolvedIds.push(matches[0].id);
      if (matches[0].name !== name) {
        matched_to_existing.push(`${name} -> ${matches[0].name}`);
      }
      continue;
    }
    unresolved.push({
      index: i,
      query: name,
      candidates: matches.map((item) => ({ id: item.id, name: item.name })),
    });
    resolvedIds.push("");
  }

  if (unresolved.length > 0) {
    return {
      ok: false,
      reason: "unresolved_exercises",
      content:
        "No template was written. Resolve each exercise to a library id " +
        "(list_exercises / create_exercise) and retry. Ambiguous names " +
        "return candidates; missing names need create_exercise first.",
      extra: { unresolved, matched_to_existing },
    };
  }

  const groupIds = new Map<string, string>();
  const exercises: BuiltExercise[] = [];
  const sets: BuiltSet[] = [];

  for (let i = 0; i < args.exercises.length; i++) {
    const exercise = args.exercises[i];
    const expanded = expandSets(exercise);
    if (!Array.isArray(expanded)) return expanded;
    for (let s = 0; s < expanded.length; s++) {
      const invalid = validateSet(expanded[s], `exercises[${i}].sets[${s}]`);
      if (invalid) return invalid;
    }

    let groupId: string | null = null;
    const token = exercise.superset_group?.trim();
    if (token) {
      const existing = groupIds.get(token);
      if (existing) groupId = existing;
      else {
        groupId = options.newId();
        groupIds.set(token, groupId);
      }
    }

    const slotId = options.newId();
    exercises.push({
      id: slotId,
      user_id: options.userId,
      template_id: options.templateId,
      exercise_id: resolvedIds[i],
      sort_order: i,
      superset_group_id: groupId,
      note: exercise.note ?? null,
      sticky_note: exercise.sticky_note ?? null,
      default_rest_seconds: exercise.default_rest_seconds ?? 90,
      updated_at: options.now,
    });

    for (let s = 0; s < expanded.length; s++) {
      const set = expanded[s];
      const unit = args.weight_unit ?? "kg";
      sets.push({
        id: options.newId(),
        template_exercise_id: slotId,
        user_id: options.userId,
        sort_order: s,
        set_type: set.set_type ?? "normal",
        weight: set.weight === undefined ? null : kilogramsFrom(set.weight, unit),
        reps: set.reps ?? null,
        rep_range_start: set.rep_range_start ?? null,
        rep_range_end: set.rep_range_end ?? null,
        rpe: set.rpe ?? null,
        distance: set.distance ?? null,
        duration_seconds: set.duration_seconds ?? null,
        rest_seconds: set.rest_seconds ?? 90,
        updated_at: options.now,
      });
    }
  }

  return {
    ok: true,
    template: {
      id: options.templateId,
      user_id: options.userId,
      name: args.name,
      folder_id: args.folder_id ?? null,
      note: args.note ?? null,
      sort_order: options.sortOrder,
      updated_at: options.now,
    },
    exercises,
    sets,
    matched_to_existing,
    weight_unit: args.weight_unit ?? null,
  };
}

export function collisionInFolder(
  rows: Array<{ id: string; name: string; folder_id: string | null }>,
  name: string,
  folderId: string | null,
  exceptId?: string,
): { id: string; name: string } | null {
  const hit = rows.find((row) =>
    row.name === name &&
    row.folder_id === folderId &&
    row.id !== exceptId
  );
  return hit ? { id: hit.id, name: hit.name } : null;
}
