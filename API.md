# Hermes API & MCP

Programmatic access to **tech-ops tasks** over a REST API and an MCP endpoint, so
external apps (and Claude via MCP) can report and resolve engineering/operational
issues.

## Authentication

All API and MCP requests use a **personal API token** sent as a bearer header:

```
Authorization: Bearer hermes_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

- Each admin creates their **own** token at **Admin → API tokens**
  (`/admin/api-tokens`) → **New token**. The token always belongs to the admin
  who creates it; there is no "create on behalf of another user".
- The raw token is shown **once** at creation; only its SHA256 hash is stored.
  Copy it immediately — if lost, revoke it and create a new one.
- A token acts as its owner. Writes are attributed to that user (e.g. the task's
  `responsible`).
- All admins can see and revoke every token (a shared operations console). Only
  metadata is shared — the raw secret is never displayed after creation.
- Access is restricted to the **tech team** (`dev_team` role or admins). A token
  for any other user is rejected with `403`.

Error responses are JSON: `{"error": {"code": "...", "message": "..."}}`.
Statuses: `401` missing/invalid token, `403` not tech team, `404` not found,
`422` validation failed, `429` rate limited.

## Rate limiting

The API/MCP surface is rate limited: **60 requests per minute** per token (or per
client IP for requests without a token). The limiter runs *before*
authentication, so invalid-token guessing is throttled too. When exceeded, the
response is `429 Too Many Requests` with a `Retry-After` header (seconds):

```json
{ "error": { "code": "rate_limited", "message": "Too many requests" } }
```

Limits are configured in `config :hermes, HermesWeb.Plugs.RateLimit`
(`limit`, `window_ms`, `enabled`). The limiter is in-memory and per-node — behind
multiple app instances each node enforces it independently, so an edge/load
balancer limiter should remain the outer line of defense.

## REST API

Base path: `/api/v1`

| Method | Path                             | Description                          |
|--------|----------------------------------|--------------------------------------|
| GET    | `/me`                            | Authenticated token owner            |
| GET    | `/requests`                      | List team requests (`?status=`)      |
| GET    | `/requests/:id`                  | Get one request                      |
| GET    | `/tech-ops/tasks`                | List tasks (`?status=` filter)       |
| GET    | `/tech-ops/tasks/:id`            | Get one task                         |
| POST   | `/tech-ops/tasks`                | Report (create) a task               |
| PATCH  | `/tech-ops/tasks/:id`            | Update status / resolution           |
| GET    | `/tech-ops/reporters`            | List canonical reporter values       |
| POST   | `/tech-ops/reporters`            | Add a reporter value                 |
| GET    | `/tech-ops/issue-origins`        | List canonical issue-origin values   |
| POST   | `/tech-ops/issue-origins`        | Add an issue-origin value            |

Tech-ops resources are grouped under `/api/v1/tech-ops/`. `requests` is a
separate, read-only domain and stays top-level.

Tech-ops task statuses: `open`, `in_progress`, `blocked`, `resolved`, `closed`.

### Reporter & issue origin are controlled vocabularies

`reporter` and `issue_origin` on a task are **managed lookup values**, not free
text. On create/update you pass the **name** (matched case- and
whitespace-insensitively). An **unknown value is rejected** with `422` and
suggestions — it is not silently created:

```json
{ "error": {
    "code": "unknown_issue_origin",
    "message": "Unknown issue origin. Use an existing value or add it first.",
    "suggestions": ["AppSignal alert"] } }
```

To add a new value first, `POST /tech-ops/reporters` or
`POST /tech-ops/issue-origins` with
`{"name": "..."}` (idempotent — returns the existing row if it already exists).
Pass `""` to clear a task's reporter/origin.

**Requests are read-only** over the API. Visibility matches the app: you only
see requests where your team is the requesting or assigned team. Fetching a
request outside that scope returns `404` (its existence is never revealed).

### Examples

```bash
# Verify a token
curl -H "Authorization: Bearer $TOKEN" https://<host>/api/v1/me

# Add an issue-origin value (once), then report an issue using it
curl -X POST https://<host>/api/v1/tech-ops/issue-origins \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "AppSignal alert"}'

curl -X POST https://<host>/api/v1/tech-ops/tasks \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reported_problem": "Disk full on web-1", "issue_origin": "AppSignal alert"}'

# Resolve it
curl -X PATCH https://<host>/api/v1/tech-ops/tasks/42 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "resolved", "resolution": "Rotated logs, expanded volume"}'
```

Successful responses wrap the payload in `{"data": ...}`.

## MCP endpoint

`POST /mcp` speaks **JSON-RPC 2.0** (MCP over Streamable HTTP). Supported methods:
`initialize`, `notifications/initialized`, `ping`, `tools/list`, `tools/call`.

### Tools

| Tool                    | Purpose                                              |
|-------------------------|------------------------------------------------------|
| `list_tasks`            | List tech-ops tasks, optional `status` filter        |
| `get_task`              | Fetch one task by `id`                               |
| `report_task`           | Create a task (`reported_problem` required)          |
| `update_task`           | Change `status` / `resolution` / `issue_origin`      |
| `resolve_task`          | Complete a task: status → `resolved` + `resolution`  |
| `list_requests`         | List your team's requests, optional `status` filter  |
| `get_request`           | Fetch one request by `id` (team-scoped, read-only)   |
| `list_reporters`        | List canonical reporter values                       |
| `add_reporter`          | Add a reporter value (idempotent)                    |
| `list_issue_origins`    | List canonical issue-origin values                   |
| `add_issue_origin`      | Add an issue-origin value (idempotent)               |

When reporting/updating a task, `reporter` and `issue_origin` must be existing
values (see `list_*`); an unknown value returns an `isError` result naming close
matches. Add a new value with `add_reporter` / `add_issue_origin` first.

Tool results come back as an MCP text content block whose `text` is the
JSON-encoded result. Handler failures set `isError: true`.

### Connecting Claude

The endpoint is a remote HTTP MCP server with bearer auth. Add it with the CLI:

```bash
claude mcp add --transport http hermes-tech-ops https://<host>/mcp \
  --header "Authorization: Bearer $TOKEN"
```

Or in an `mcp.json` / client config:

```json
{
  "mcpServers": {
    "hermes-tech-ops": {
      "type": "http",
      "url": "https://<host>/mcp",
      "headers": { "Authorization": "Bearer hermes_xxx" }
    }
  }
}
```

Once connected, Claude can call e.g. `report_task` to file an issue and
`resolve_task` to close it out.

## Implementation notes

- REST and MCP share one implementation: `Hermes.MCP.Tools` holds the tool
  definitions and handlers; both controllers delegate to it, so the two surfaces
  never drift.
- Auth: `HermesWeb.Plugs.ApiAuth`. Tokens: `Hermes.Accounts.ApiToken`.
- Domain: `Hermes.TechOps` (unchanged by the API layer).
