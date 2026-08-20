import { assertEquals } from "jsr:@std/assert@1";

function uncommented(source: string): string {
  return source
    .split("\n")
    .filter((line) => !line.trim().startsWith("//"))
    .join("\n");
}

Deno.test("the MCP function never uses the service-role client", async () => {
  const files = [
    "./index.ts",
    "./server.ts",
    "./listExercises.ts",
    "./createExercise.ts",
    "./getTemplates.ts",
    "./getTemplate.ts",
    "./templateWrite.ts",
    "./createTemplate.ts",
    "./updateTemplate.ts",
    "./getWorkoutHistory.ts",
    "./getExerciseProgress.ts",
    "./workoutRead.ts",
    "./createProgram.ts",
    "./deleteTemplate.ts",
    "./deleteProgram.ts",
    "./oauthResource.ts",
  ];
  for (const file of files) {
    const source = uncommented(await Deno.readTextFile(new URL(file, import.meta.url)));
    assertEquals(
      source.includes("supabaseAdmin"),
      false,
      `${file} references supabaseAdmin — RLS is the authorization model`,
    );
  }
});
