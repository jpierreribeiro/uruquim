# Error Responses

> Phase-1 wire contract ratified at the 2026-07-18 Spec Gate; full captured
> examples are completed with WP6/WP10 implementation evidence.
>
> **Implemented as of WP5: `invalid_path_parameter` and
> `invalid_query_parameter` only.** These two are produced by the extractors
> (`web.path_int`, `web.query_int`, `web.query_int_or`) and are test-pinned,
> including validation of the emitted bytes by the official
> `core:encoding/json` parser in strict JSON mode.
>
> Every other code in the list below is still unimplemented. The public
> responders — `web.bad_request`, `web.unauthorized`, `web.forbidden`,
> `web.not_found`, `web.internal_error` — commit nothing, and the automatic
> 404/405 bodies are EMPTY. The general envelope renderer is WP6;
> `invalid_json` and `body_too_large` arrive with body binding in WP7.

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
`invalid_json`, `body_too_large`, `not_found`, `method_not_allowed`,
`unauthorized`, `forbidden`, `internal_error`.

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
- No `Content-Type` and no other header is set. Response header policy is WP6.
- The response is committed through the single-commit guard, so continued
  handler code cannot replace it, and an extractor that fails after a response
  was already committed changes nothing.

Will document, per code: producing extractor/helper, HTTP status, envelope
fields, and a captured example response.
