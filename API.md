# Hermes API & MCP

Programmatic access to **tech-ops tasks** over a REST API and an MCP endpoint, so
external apps (and Claude via MCP) can report and resolve engineering/operational
issues.

## Authentication

All API and MCP requests use a **personal API token** sent as a bearer header:

```
Authorization: Bearer hermes_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

- Tokens are minted by admins at **Admin → API tokens** (`/admin/api-tokens`).
- The raw token is shown **once** at creation; only its SHA256 hash is stored.
- A token acts as its owner. Writes are attributed to that user (e.g. the task's
  `responsible`).
- Access is restricted to the **tech team** (`dev_team` role or admins). A token
  for any other user is rejected with `403`.

Error responses are JSON: `{"error": {"code": "...", "message": "..."}}`.
Statuses: `401` missing/invalid token, `403` not tech team, `404` not found,
`422` validation failed.

## REST API

Base path: `/api/v1`

| Method | Path                       | Description                          |
|--------|----------------------------|--------------------------------------|
| GET    | `/me`                      | Authenticated token owner            |
| GET    | `/tech_ops_tasks`          | List tasks (`?status=` filter)       |
| GET    | `/tech_ops_tasks/:id`      | Get one task                         |
| POST   | `/tech_ops_tasks`          | Report (create) a task               |
| PATCH  | `/tech_ops_tasks/:id`      | Update status / resolution           |
| GET    | `/requests`                | List team requests (`?status=`)      |
| GET    | `/requests/:id`            | Get one request                      |

Tech-ops task statuses: `open`, `in_progress`, `blocked`, `resolved`, `closed`.

**Requests are read-only** over the API. Visibility matches the app: you only
see requests where your team is the requesting or assigned team. Fetching a
request outside that scope returns `404` (its existence is never revealed).

### Examples

```bash
# Verify a token
curl -H "Authorization: Bearer $TOKEN" https://<host>/api/v1/me

# Report an issue
curl -X POST https://<host>/api/v1/tech_ops_tasks \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reported_problem": "Disk full on web-1", "issue_origin": "AppSignal alert"}'

# Resolve it
curl -X PATCH https://<host>/api/v1/tech_ops_tasks/42 \
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
| `list_tech_ops_tasks`   | List tasks, optional `status` filter                 |
| `get_tech_ops_task`     | Fetch one task by `id`                               |
| `report_tech_ops_task`  | Create a task (`reported_problem` required)          |
| `update_tech_ops_task`  | Change `status` / `resolution` / `issue_origin`      |
| `resolve_tech_ops_task` | Complete a task: status → `resolved` + `resolution`  |
| `list_requests`         | List your team's requests, optional `status` filter  |
| `get_request`           | Fetch one request by `id` (team-scoped, read-only)   |

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

Once connected, Claude can call e.g. `report_tech_ops_task` to file an issue and
`resolve_tech_ops_task` to close it out.

## Implementation notes

- REST and MCP share one implementation: `Hermes.MCP.Tools` holds the tool
  definitions and handlers; both controllers delegate to it, so the two surfaces
  never drift.
- Auth: `HermesWeb.Plugs.ApiAuth`. Tokens: `Hermes.Accounts.ApiToken`.
- Domain: `Hermes.TechOps` (unchanged by the API layer).
