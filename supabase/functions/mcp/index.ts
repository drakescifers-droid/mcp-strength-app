// MCPStrength remote MCP server.
//
// Queries Postgres as the signed-in user. RLS is the authorization model.
// Do not read `supabaseAdmin` off the context — the platform injects a
// service-role client, and using it would let this function see every
// account. docs/02-architecture.md § Auth.

import { createSupabaseContext } from "npm:@supabase/server";
import { WebStandardStreamableHTTPServerTransport } from "npm:@modelcontextprotocol/sdk@1.30.0/server/webStandardStreamableHttp.js";
import { createMcpServer } from "./server.ts";
import {
  corsPreflight,
  isMetadataPath,
  metadataResponse,
  unauthorizedResponse,
} from "./oauthResource.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return corsPreflight();

  if (req.method === "GET" && isMetadataPath(req.url)) {
    return metadataResponse(req.url);
  }

  const { data: ctx, error } = await createSupabaseContext(req, {
    auth: "user",
    cors: "disabled",
  });
  if (error || ctx === null || ctx.userClaims === null) {
    return unauthorizedResponse(req.url);
  }

  const server = createMcpServer(ctx.supabase, ctx.userClaims.id);
  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableDnsRebindingProtection: false,
  });
  await server.connect(transport);
  return await transport.handleRequest(req);
});
