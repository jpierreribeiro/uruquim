# Middleware

> Placeholder — written during Phase 3/4.

Will document: the `web.use` surface, exact ordering semantics (global →
outer groups → inner groups → route → handler), onion/unwind behavior,
short-circuiting, the built-in middleware catalog and their configs, and how
to write custom middleware (a plain handler calling `web.next`).
