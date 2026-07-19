# Middleware

> Placeholder — the middleware surface starts in Phase 2; production
> hardening middleware is completed in Phase 4. No middleware API exists in
> Phase 1.

Will document: the `web.use` surface, exact ordering semantics (global →
outer groups → inner groups → route → handler), onion/unwind behavior,
short-circuiting, the built-in middleware catalog and their configs, and how
to write custom middleware (a plain handler calling `web.next`).
