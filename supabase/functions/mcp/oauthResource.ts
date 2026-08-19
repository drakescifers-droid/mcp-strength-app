// RFC 9728 Protected Resource Metadata + the Claude 401 handshake.
// @supabase/server 1.4.1 documents `withOAuthProtectedResource` but does not
// export it, so this function owns the behaviour. Claude will not start OAuth
// unless an unauthenticated POST gets 401 with WWW-Authenticate pointing at
// this metadata — a well-known probe on the functions origin 404s.
//
// Do not build the resource URL from `req.url`. On hosted Edge Functions the
// request is rewritten to something like `http://<ref>.supabase.co/mcp`, which
// is not the URL a client types. `resource` must match that public URL exactly.

const METADATA_SUFFIX = "/oauth-protected-resource";
const FUNCTION_PATH = "/functions/v1/mcp";

export function mcpResourceUrl(requestUrl?: string): string {
  const explicit = Deno.env.get("MCP_RESOURCE_URL")?.replace(/\/$/, "");
  if (explicit) return explicit;

  const supabase = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  if (supabase.includes(".supabase.co")) {
    return `${supabase.replace(/^http:/, "https:")}${FUNCTION_PATH}`;
  }

  if (requestUrl) {
    const url = new URL(requestUrl);
    let path = url.pathname;
    if (path.endsWith(METADATA_SUFFIX)) {
      path = path.slice(0, -METADATA_SUFFIX.length);
    }
    if (path.endsWith("/")) path = path.slice(0, -1);
    if (path.endsWith(FUNCTION_PATH) || path.endsWith("/mcp")) {
      return `${url.protocol}//${url.host}${path.replace(/\/mcp$/, FUNCTION_PATH)}`;
    }
    return `${url.origin}${FUNCTION_PATH}`;
  }

  if (supabase.length > 0) return `${supabase}${FUNCTION_PATH}`;
  return FUNCTION_PATH;
}

export function isMetadataPath(requestUrl: string): boolean {
  const path = new URL(requestUrl).pathname;
  return path === METADATA_SUFFIX || path.endsWith(METADATA_SUFFIX);
}

export function authorizationServerIssuer(): string {
  const supabase = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const issuer = supabase.includes(".supabase.co")
    ? supabase.replace(/^http:/, "https:")
    : supabase;
  return `${issuer}/auth/v1`;
}

export function protectedResourceMetadata(requestUrl?: string): {
  resource: string;
  authorization_servers: string[];
  scopes_supported: string[];
  bearer_methods_supported: string[];
  resource_name: string;
} {
  return {
    resource: mcpResourceUrl(requestUrl),
    authorization_servers: [authorizationServerIssuer()],
    // Do not advertise offline_access — the AS does; Claude appends it from
    // there. Resource servers listing it is what the MCP spec warns against.
    scopes_supported: ["openid", "email", "profile"],
    bearer_methods_supported: ["header"],
    resource_name: "MCP Strength",
  };
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, content-type, accept, mcp-protocol-version, mcp-method, mcp-name",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function corsPreflight(): Response {
  return new Response(null, { status: 204, headers: cors });
}

export function metadataResponse(requestUrl?: string): Response {
  return new Response(JSON.stringify(protectedResourceMetadata(requestUrl)), {
    status: 200,
    headers: {
      ...cors,
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}

export function unauthorizedResponse(requestUrl?: string): Response {
  const resource = mcpResourceUrl(requestUrl);
  const metadataUrl = `${resource}${METADATA_SUFFIX}`;
  return new Response(
    JSON.stringify({
      error: "invalid_token",
      error_description: "Authentication required",
    }),
    {
      status: 401,
      headers: {
        ...cors,
        "content-type": "application/json",
        "WWW-Authenticate":
          `Bearer realm="mcp-strength", resource_metadata="${metadataUrl}", scope="openid email profile"`,
      },
    },
  );
}
