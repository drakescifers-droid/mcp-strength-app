// Enum values are the Swift / Postgres raw values, character for character.
// docs/05-database.md § Naming — a mapping layer is how Phase 0 silently
// rewrote drop_set → normal.

export const BODY_PARTS = [
  "arms",
  "back",
  "cardio",
  "chest",
  "core",
  "fullBody",
  "legs",
  "olympic",
  "other",
  "shoulders",
] as const;

export type BodyPart = (typeof BODY_PARTS)[number];

export const EXERCISE_CATEGORIES = [
  "barbell",
  "dumbbell",
  "machineOther",
  "weightedBodyweight",
  "assistedBodyweight",
  "repsOnly",
  "cardio",
  "duration",
  "hammerStrength",
] as const;

export type ExerciseCategory = (typeof EXERCISE_CATEGORIES)[number];

export const SET_TYPES = [
  "normal",
  "warmup",
  "dropSet",
  "restPause",
  "failure",
] as const;

export type SetType = (typeof SET_TYPES)[number];

export const FOLDER_KINDS = ["folder", "program"] as const;

export type FolderKind = (typeof FOLDER_KINDS)[number];

// Swift `WeightUnit` raw values. `lb` is not a value — teach `lbs`.
export const WEIGHT_UNITS = ["kg", "lbs"] as const;

export type WeightUnit = (typeof WEIGHT_UNITS)[number];

export const KILOGRAMS_PER_POUND = 0.45359237;

export function kilogramsFrom(
  displayed: number,
  unit: WeightUnit,
): number {
  return unit === "kg" ? displayed : displayed * KILOGRAMS_PER_POUND;
}

export type LibraryExercise = {
  id: string;
  name: string;
  aliases: string[];
  bodyPart: BodyPart;
  // Body parts trained beyond `bodyPart` — Deadlift is back + [legs]. Mirrors
  // MCPStrength/Models/Exercise.swift's `secondaryBodyParts`; see
  // exerciseMatcher.ts for why the matcher's body-part hint checks both.
  secondaryBodyParts: BodyPart[];
  category: ExerciseCategory;
};
