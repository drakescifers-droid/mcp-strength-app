// MCP tool failures have no human feedback channel — the model absorbs the
// error and tells the user the task succeeded (docs/02-architecture.md
// § Observability). Edge Function logs are the sink. One JSON line per call.

export function logToolCall(fields: {
  tool: string;
  outcome: "ok" | "error";
  duration_ms: number;
  [key: string]: unknown;
}): void {
  console.log(JSON.stringify({ mcp: true, ...fields }));
}
