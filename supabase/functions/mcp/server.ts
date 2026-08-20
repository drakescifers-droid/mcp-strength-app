import { McpServer } from "npm:@modelcontextprotocol/sdk@1.30.0/server/mcp.js";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { listExercises, listExercisesInput, listExercisesOutput } from "./listExercises.ts";
import type { ListExercisesInput } from "./listExercises.ts";
import { createExercise, createExerciseInput } from "./createExercise.ts";
import type { CreateExerciseInput } from "./createExercise.ts";
import { getTemplates, getTemplatesInput, getTemplatesOutput } from "./getTemplates.ts";
import type { GetTemplatesInput } from "./getTemplates.ts";
import { getTemplate, getTemplateInput, getTemplateOutput } from "./getTemplate.ts";
import type { GetTemplateInput } from "./getTemplate.ts";
import { createTemplate, createTemplateInput } from "./createTemplate.ts";
import type { CreateTemplateInput } from "./createTemplate.ts";
import { updateTemplate, updateTemplateInput } from "./updateTemplate.ts";
import type { UpdateTemplateInput } from "./updateTemplate.ts";
import {
  getWorkoutHistory,
  getWorkoutHistoryInput,
  getWorkoutHistoryOutput,
} from "./getWorkoutHistory.ts";
import type { GetWorkoutHistoryInput } from "./getWorkoutHistory.ts";
import {
  getExerciseProgress,
  getExerciseProgressInput,
  getExerciseProgressOutput,
} from "./getExerciseProgress.ts";
import type { GetExerciseProgressInput } from "./getExerciseProgress.ts";

// Built per request so the user-scoped client cannot leak across callers.
// Never pass supabaseAdmin in here — RLS is the authorization model.

export function createMcpServer(
  supabase: SupabaseClient,
  userId: string,
): McpServer {
  const server = new McpServer({
    name: "mcp-strength",
    version: "0.1.0",
  });

  server.registerTool(
    "list_exercises",
    {
      title: "List exercises",
      description:
        "Search the exercise library by name, or list it filtered by " +
        "category. Call this before creating anything so you resolve to an " +
        "existing id instead of inventing a near-duplicate name. Returns " +
        "stable UUIDs; later tools take those ids, never a name, for writes. " +
        "body_part is a ranking hint, not a filter.",
      inputSchema: listExercisesInput,
      outputSchema: listExercisesOutput,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (args: ListExercisesInput) => listExercises(supabase, args),
  );

  server.registerTool(
    "create_exercise",
    {
      title: "Create exercise",
      description:
        "Add a custom exercise to the library. Fuzzy-matches first: a unique " +
        "close match is returned (created: false) and nothing is written. " +
        "Several matches return candidates and write nothing. A true miss " +
        "creates a row owned by the signed-in user. There is no delete tool " +
        "for exercises — history points at them.",
      inputSchema: createExerciseInput,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async (args: CreateExerciseInput) => createExercise(supabase, userId, args),
  );

  server.registerTool(
    "get_templates",
    {
      title: "Get templates",
      description:
        "List workout templates, or look one up by id or name. Name is " +
        "lookup only: several matches return candidates and none is picked. " +
        "Returns notes. Weights live on get_template, in kilograms. Use the " +
        "returned UUID with get_template and with later write tools.",
      inputSchema: getTemplatesInput,
      outputSchema: getTemplatesOutput,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (args: GetTemplatesInput) => getTemplates(supabase, args),
  );

  server.registerTool(
    "get_template",
    {
      title: "Get template",
      description:
        "Return one template by UUID, including every exercise, set, note, " +
        "and sticky note. Weights are kilograms (the stored unit). There is " +
        "no name argument — call get_templates first if you only have a " +
        "name. set_type is normal | warmup | dropSet | failure; drop_set " +
        "is not a value.",
      inputSchema: getTemplateInput,
      outputSchema: getTemplateOutput,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (args: GetTemplateInput) => getTemplate(supabase, args),
  );

  server.registerTool(
    "create_template",
    {
      title: "Create template",
      description:
        "Write a workout plan. All-or-nothing: any unresolved exercise " +
        "writes nothing and returns candidates. Fuzzy-matches library " +
        "names (Pec Deck → Chest Fly). Errors on a duplicate name in the " +
        "same folder and returns that id for update_template. Weights need " +
        "weight_unit kg or lbs and are stored as kilograms. Notes and " +
        "sticky_note are coaching text, not optional trivia. set_type is " +
        "normal | warmup | dropSet | failure — drop_set is rejected. " +
        "Shorthand: set_count + reps for identical working sets.",
      inputSchema: createTemplateInput,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async (args: CreateTemplateInput) => createTemplate(supabase, userId, args),
  );

  server.registerTool(
    "update_template",
    {
      title: "Update template",
      description:
        "Revise a plan by UUID. Sending exercises replaces the whole list " +
        "(screenshot of a full workout: send every exercise). Same matching, " +
        "weight_unit, and notes rules as create_template. There is no " +
        "update-by-name.",
      inputSchema: updateTemplateInput,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
    async (args: UpdateTemplateInput) => updateTemplate(supabase, userId, args),
  );

  server.registerTool(
    "get_workout_history",
    {
      title: "Get workout history",
      description:
        "Read completed sessions, newest first. Must be used for coaching: " +
        "returns the session note (instructions going in), the summary " +
        "(how it went), per-exercise notes and sticky notes, and every " +
        "set. Weights are kilograms. Unfinished sessions are not history. " +
        "set_type is normal | warmup | dropSet | failure. Date window is " +
        "from / to as YYYY-MM-DD or an ISO timestamp.",
      inputSchema: getWorkoutHistoryInput,
      outputSchema: getWorkoutHistoryOutput,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (args: GetWorkoutHistoryInput) => getWorkoutHistory(supabase, args),
  );

  server.registerTool(
    "get_exercise_progress",
    {
      title: "Get exercise progress",
      description:
        "Time series for one exercise across completed sessions. Returns " +
        "the session summary and both exercise notes so a bad night is " +
        "not a downward trend. Name lookup returns candidates and no " +
        "series when several library rows match — the rebuilt library " +
        "has many equipment variants, so prefer the UUID from " +
        "list_exercises. Weights are kilograms. dropSet not drop_set.",
      inputSchema: getExerciseProgressInput,
      outputSchema: getExerciseProgressOutput,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async (args: GetExerciseProgressInput) => getExerciseProgress(supabase, args),
  );

  return server;
}
