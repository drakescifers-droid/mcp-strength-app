# Directory listing and launch compliance

What has to be true before MCP Strength appears in **Anthropic’s Connectors Directory** and **ChatGPT’s plugin directory**, and how that sits next to App Store launch.

This file is the checklist and the sequencing. It is not the protocol:

| Question | Where it lives |
|---|---|
| How OAuth and the MCP host are wired | `02-architecture.md` § Auth |
| What the tools are, and which ones must not exist | `03-mcp-tools.md` |
| What is built today | `04-status.md` |
| App Store Connect, signing, HealthKit entitlements | `04-status.md` § Shipping to a device |

Custom connect already works: paste `https://mcp.mcpstrength.com` into Claude. Directory listing is a **review**, not a second server. Do not rebuild OAuth to “qualify.”

Official pages change. The requirements below were read on **2026-08-20**. Re-read the links in § Sources before submitting; this file keeps *when we tackle what*, not a frozen copy of their legal text.

---

## When, in this project’s phases

`02-architecture.md` already named the phases. Directory work is **Phase 4 product**, with a short **Phase 3 leftover** that unblocks the forms. It is not a Phase 2 sync job and it does not wait on Watch-attach.

| When | What | Why it sits here |
|---|---|---|
| **Phase 3 — done** | Remote MCP, Streamable HTTP, OAuth Allow page, tool `title` + `readOnlyHint` / `destructiveHint`, privacy stub at `/privacy` | The technical bar both directories describe. Claude can already connect. |
| **Phase 3 leftover — before any directory form** | Thicken privacy, add terms, a public how-to, re-enable confirmation email, a populated reviewer account, say how to delete an account | Reviewers bounce missing pages and unusable sign-up. Same pages also unblock App Store review. |
| **Phase 4 — App Store** | App Store Connect record, in-app account deletion, screenshots, privacy nutrition labels | `04-status.md`. Apple’s rules, not Anthropic’s. |
| **Phase 4 — Anthropic directory** | Team or Enterprise Claude org, submit the live URL, test account, health-data declaration | Portal is org settings. A personal Pro/Max plan can *use* a custom connector and **cannot** submit. |
| **Phase 4 — ChatGPT plugins** | OpenAI identity verification, `/.well-known/openai-apps-challenge`, five pass / three fail prompts, privacy that matches tool payloads | This is the current Plugins Directory (MCP-backed), not the 2023 plugin store. |
| **After listing** | Keep the server up, answer security mail, keep tool descriptions honest | Both directories reserve the right to drop a listing that drifts. |

Do **not** start directory submit while confirmation email still points nowhere and the privacy page still says “email us to delete the account” without a retention story. The MCP surface can stay live for Drake and custom-connector users in the meantime.

Suggested order inside Phase 4: **legal pages and sign-up → App Store listing (record exists; first TestFlight build uploaded 2026-08-20) → Anthropic directory → ChatGPT plugins.** Anthropic first because the connector is already the product there. ChatGPT is a second client of the same URL.

---

## Already true (do not redo)

As of 2026-08-20:

- Public HTTPS MCP at `https://mcp.mcpstrength.com` (Streamable HTTP).
- OAuth 2.x consent on mcpstrength.com (`/oauth/consent`). Unauthenticated MCP traffic returns `401` with resource metadata. `02-architecture.md` § Auth.
- Every registered tool has `title`, `readOnlyHint`, `destructiveHint`, `openWorldHint`. Deletes are `destructiveHint: true`. Names are well under 64 characters.
- Reads and writes are separate tools (no catch-all `api_request`).
- First-party API: the server queries **our** Postgres as the signed-in user. Never `supabaseAdmin`.
- A privacy page exists: `https://mcpstrength.com/privacy`. Terms at `/terms`, how-to at `/connect`. Contact `help@mcpstrength.com`.
- Custom Claude connect is proven in use.

---

## Phase 3 leftover — pages and accounts

Do these once. They feed **both** directories and the App Store.

| Item | Today | Enough when |
|---|---|---|
| Privacy policy | `https://mcpstrength.com/privacy` — categories, recipients, 90-day tombstones for row deletes, immediate account delete, `help@mcpstrength.com` | Keep it matching the app |
| Terms of use | `https://mcpstrength.com/terms` | Keep it matching the app |
| Documentation URL | `https://mcpstrength.com/connect` | Connector URL, logging stays on the phone |
| Support contact | `help@mcpstrength.com` | Forwards to Drake via Cloudflare Email Routing |
| Confirmation email | **On** as of 2026-08-20. App wired to `/auth/callback` | Prove with a throwaway signup that the link opens the app |
| Account deletion | In-app Profile → Delete Account. Edge Function `delete-account` (service role, that user only) | Privacy page already describes the button |
| Revoke connected apps | Password change or Delete Account | Do not promise a site revoke button |
| Reviewer account | Drake’s real account | A dedicated login with templates, finished workouts, notes, sticky notes, a program. No MFA maze. Both directories require a populated test account |

Health-data line to keep: **training logs and optional body measurements, not clinical records.** Declare “personal health data” on Anthropic’s form if asked — they mean sensitive body/training data, not “we are a HIPAA covered entity.” OpenAI’s plugin rules ban **PHI** (HIPAA). Gym sets, session notes, and user-entered weight are not a medical chart; do not collect diagnoses, SSNs, or clinician notes. If a form is ambiguous, say training data, not medical records.

---

## Phase 4 — Anthropic Connectors Directory

Submit from [Claude.ai directory submissions](https://claude.ai/admin-settings/directory/submissions/new). Needs a **Team or Enterprise** organization and Owner (or Directory) permission.

Portal will pull tools live from `https://mcp.mcpstrength.com`. Missing titles or hints fail before review. Then: listing copy (name ≤100, tagline ≤55, description ≤2000), docs URL, privacy URL, icon, support, auth mode (OAuth + DCR or whatever we already ship), whether we handle personal health data, a test account, seven policy acknowledgments.

First listing is usually **community**. **Verified** is Anthropic picking you later, not a second application.

We are not an MCP App (no in-chat UI). Skip carousel screenshots unless that ships.

Policy traps we already avoid: no money movement, no ads as the product, no `log_workout`, no collecting Claude’s chat log. Keep tool descriptions as *what the tool does*, not instructions that hijack Claude.

Sources: [submission](https://claude.com/docs/connectors/building/submission), [review criteria](https://claude.com/docs/connectors/building/review-criteria), [Software Directory Policy](https://support.claude.com/en/articles/13145358-anthropic-software-directory-policy).

---

## Phase 4 — ChatGPT plugin directory

OpenAI now publishes **plugins** (MCP and/or skills) into a directory shared with ChatGPT and Codex. This is not the 2023 plugin store.

On top of the leftover pages:

| Item | Why |
|---|---|
| Identity verification (individual or business) in OpenAI Platform | Unverified publisher names are rejected |
| Domain proof at `/.well-known/openai-apps-challenge` on the MCP host (or parent) | Portal will refuse an unverified domain |
| Five positive and three negative test cases | Written prompts with expected behavior |
| Privacy policy matches **tool responses** | If history returns notes, the policy names notes. Strip debug/internal ids from payloads rather than disclosing junk |
| Demo credentials | Same populated account as Anthropic unless they forbid sharing |

We do not ship MCP Apps UI, so do not send ChatGPT app screenshots “anyway.”

Sources: [Submit plugins](https://developers.openai.com/plugins/deploy/submission), [MCP review](https://developers.openai.com/plugins/deploy/app-review), [App guidelines](https://developers.openai.com/apps-sdk/app-guidelines).

---

## Not this file

- **App Store Connect record, archive, HealthKit capability** — `04-status.md` § Shipping to a device. The record exists; first TestFlight upload succeeded 2026-08-20 (processing).
- **Sign in with Apple** — only required once a third-party login is offered. Email/password alone does not trigger it. Identity linking is `04-status.md`.
- **Program UI, PRs, themes** — product, not directory compliance.
- **Lawyer-certified HIPAA program** — not implied by a consumer workout log. If that ever changes, it is a new decision, not a silent expansion of this checklist.

---

## Open questions

1. **Publisher name.** Individual (Drake) vs a business identity on OpenAI and Anthropic. Pick before verification; the listing name has to match.
2. **Whether ChatGPT is Phase 4.0 or 4.1.** The same MCP URL can list on both. Listing Claude first is enough to be “in a directory”; ChatGPT can follow once identity verify is done.
3. **Tombstone retention in the privacy page.** Row deletes keep tombstones 90 days. Whole-account delete is immediate (`auth.users` cascade). The public policy says both.
