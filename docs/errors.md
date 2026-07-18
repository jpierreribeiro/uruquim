# Error Responses

> Placeholder — frozen at the Phase 1 Spec Gate.

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

Initial code list: `invalid_path_parameter`, `invalid_query_parameter`,
`invalid_json`, `body_too_large`, `not_found`, `method_not_allowed`,
`unauthorized`, `forbidden`, `internal_error`.

Will document, per code: producing extractor/helper, HTTP status, envelope
fields, and a captured example response.
