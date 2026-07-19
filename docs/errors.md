# Error Responses

> Phase-1 wire contract ratified at the 2026-07-18 Spec Gate; full captured
> examples are completed with WP6/WP10 implementation evidence.

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

Will document, per code: producing extractor/helper, HTTP status, envelope
fields, and a captured example response.
