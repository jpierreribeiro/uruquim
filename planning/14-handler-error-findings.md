# 14 — Handler Error Findings

## Question

Should Uruquim replace `proc(ctx: ^Context)` with an Echo-style returned error
or with a response/error outcome?

## Executed evidence

Experiment 10 compiled and tested three in-memory models on the pinned Odin
compiler:

1. void handler plus a private typed error-report path;
2. `proc(ctx) -> Handler_Error`;
3. `proc(ctx) -> Handler_Outcome`.

All three implemented success JSON, mapped domain 404, unknown 500 with a
server log, marshal failure before commit, post-commit failure without a
second write, extractor-already-responded behavior, middleware short-circuit,
and exact `ok` delegation. Four tests passed.

Two compiler probes were decisive:

- returned handler errors/outcomes can be silently ignored;
- an unnamed returned result makes bare `return` fail with
  `Expected 1 return values, got 0`.

## Accepted Phase-1 decision

Keep the void handler. It preserves the ratified extractor flow, keeps one
canonical shape for humans and agents, and does not claim a safety guarantee
the compiler does not provide. Centralized error formatting and logging are
still required, but live behind a private closed event. A typed observer or
external-reporting policy belongs to Phase 2 and cannot rewrite an already
committed response.

Application services should expose their own typed domain failures. Handlers
or typed extraction procedures map those failures to the HTTP boundary; the
framework does not accept arbitrary Go-like errors or `any`.
