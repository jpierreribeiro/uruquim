# Error Responses

> Phase-1 wire contract ratified at the 2026-07-18 Spec Gate; full captured
> examples are completed with WP6/WP10 implementation evidence.
>
> **Implemented as of WP6:** the two extractor errors (`invalid_path_parameter`,
> `invalid_query_parameter`) plus every general responder —
> `bad_request`, `unauthorized`, `forbidden`, `not_found`, `internal_error` —
> and the automatic `not_found` (404) and `method_not_allowed` (405). All carry
> the standardized envelope and a `Content-Type: application/json`, and all are
> test-pinned by parsing the emitted bytes with the official `core:encoding/json`
> parser in strict JSON mode.
>
> Still unimplemented: `invalid_json` and `body_too_large`, which arrive with
> body binding in WP7.

Documents the standardized error envelope (part of the compatibility
contract):

```json
{
  "error": {
    "code": "invalid_path_parameter",
    "message": "Path parameter 'id' must be an integer",
    "field": "id"
  }
}
```

`field` is optional and is omitted when no concrete input field caused the
error. It is present for errors such as `invalid_path_parameter` and
`invalid_query_parameter`; it is absent for general 404/405/500 responses.

Initial code list: `invalid_path_parameter`, `invalid_query_parameter`,
`invalid_json`, `body_too_large`, `bad_request`, `not_found`,
`method_not_allowed`, `unauthorized`, `forbidden`, `internal_error`.

> **Amendment (WP6, D4).** `bad_request` was added to the list above. The
> public helper `web.bad_request(ctx, message)` was ratified in WP1 and needs a
> wire code like every other error responder; the original list simply omitted
> one. This adds no public symbol and changes no signature.

Phase-1 policy:

- request bodies larger than the fixed 4 MiB cap produce `body_too_large`;
- a known path registered for another method produces
  `method_not_allowed` (HTTP 405) and the required `Allow` header;
- a JSON marshal failure is logged server-side before one complete
  `internal_error` response is written, and only before commit; partial JSON
  is forbidden.

## Implemented in WP5

Both codes are HTTP 400 and both always carry `field`. The exact messages:

| Producer | Condition | `code` | `message` |
|---|---|---|---|
| `web.path_int` | absent, empty, malformed or out of range | `invalid_path_parameter` | `Path parameter '<name>' must be an integer` |
| `web.query_int` | absent | `invalid_query_parameter` | `Query parameter '<name>' is required` |
| `web.query_int`, `web.query_int_or` | present but not a valid integer | `invalid_query_parameter` | `Query parameter '<name>' must be an integer` |

Captured example — `GET /users/banana` against `web.get(&app, "/users/:id", h)`
where `h` calls `web.path_int(ctx, "id")`:

```json
{"error":{"code":"invalid_path_parameter","message":"Path parameter 'id' must be an integer","field":"id"}}
```

Notes on the WP5 envelope specifically:

- The four path failure modes collapse into ONE message on purpose.
  Distinguishing "absent" from "malformed" would describe the server's routing
  to the caller: a name the handler asked for but the route never captured is
  an application bug, not something the client can act on. The query case
  distinguishes them because both are caller-fixable.
- `field` carries the parameter name, JSON-escaped. Names are bounded at 64
  escaped bytes; truncation lands on an escape boundary, so the envelope is
  valid JSON for any name.
- The response is committed through the single-commit guard, so continued
  handler code cannot replace it, and an extractor that fails after a response
  was already committed changes nothing.
- **Amended in WP6:** these envelopes now carry `Content-Type: application/json`.
  The body still lives on the fixed request-local buffer, so the WP5
  allocation-free error path is unchanged.

## Implemented in WP6

Every general error responder, plus the two automatic errors. None carries a
`field`. All carry `Content-Type: application/json`.

| Producer | HTTP | `code` | `message` |
|---|---|---|---|
| `web.bad_request(ctx, m)` | 400 | `bad_request` | `m`, verbatim |
| `web.unauthorized(ctx, m)` | 401 | `unauthorized` | `m`, verbatim |
| `web.forbidden(ctx, m)` | 403 | `forbidden` | `m`, verbatim |
| `web.not_found(ctx, r)` | 404 | `not_found` | `Resource '<r>' not found` |
| `web.internal_error(ctx)` | 500 | `internal_error` | `Internal server error` |
| automatic (unknown path) | 404 | `not_found` | `Route not found` |
| automatic (wrong method) | 405 | `method_not_allowed` | `Method not allowed` |

Notes on the WP6 envelopes:

- The `message` of `bad_request`/`unauthorized`/`forbidden` is returned
  VERBATIM, so pass a caller-facing explanation, never an internal diagnostic.
  `internal_error` takes no message on purpose: failure detail is logged on the
  server, never sent to the client.
- `not_found` takes the resource NAME (`"user"`), not a full sentence.
- The automatic 404/405 bodies are static constants; the responders that carry
  arbitrary text render through the official encoder, which escapes the message.
  All are validated as strict JSON in the tests.
- Success responses: `web.json`/`web.ok`/`web.created` set
  `Content-Type: application/json`; `web.text` sets
  `text/plain; charset=utf-8`; `web.no_content` sets none and sends an empty
  204. A rejected payload (a pointer or procedure) is logged server-side and
  answered with one complete `internal_error`; no partial body escapes.
