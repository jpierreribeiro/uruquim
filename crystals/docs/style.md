# Style — the Odin taste a Crystal should have

**Status: GUIDANCE, not a gate.** None of this is checked by a script and most
of it should not be. It is here so that ten Crystals written by different people
read like they came from the same ecosystem, which is a property you get by
agreeing on taste early or not at all.

Everything below is derived from `knowledge-base/02-odin-idioms-guidelines.md`.
Where this document adds something, it says so.

---

## 1. Procedures and data, never objects

Odin has records and procedures. It does not have methods, and simulating them
is the single fastest way to make an Odin package feel foreign.

```odin
// Yes — the operation names itself, the subject is the first parameter.
pool_acquire :: proc(p: ^Pool) -> (conn: ^Conn, ok: bool)
sql_where_eq  :: proc(q: ^Query, column: string, value: Value)
```

```odin
// No — receiver-thinking dressed up in Odin syntax.
Pool_Methods :: struct { acquire: proc(...) }
p.acquire(...)
```

The core follows this without exception: `web.get(&app, ...)`, not
`app.get(...)`. A Crystal that inverts it forces the reader to switch grammars
mid-file.

**Ecosystem addition:** the package alias already carries the subject, so do
not repeat it. Inside `crystals:db/postgres`, prefer `pg.open` over
`pg.postgres_open`. The `pool_acquire`-style prefix is for procedures whose
first parameter is *not* the package's headline type.

## 2. Pair every `init` with a `destroy`, in the same package, at the same level

The core's rule is that every allocation belongs to exactly one of four
lifetimes: application, router, request, scratch. A Crystal introduces a fifth
possibility — *Crystal-owned* — and the only way that stays comprehensible is
if it is really "application lifetime, allocated by a Crystal on the
application's behalf".

```odin
pool: pg.Pool
if !pg.open(&pool, config) { return }
defer pg.close(&pool)
```

Two properties worth insisting on:

* **The caller declares the storage.** `pg.open(&pool, ...)` rather than
  `pool := pg.open(...)` returning a heap pointer. The application then owns
  the lifetime visibly, on its own stack, and `defer` does the right thing
  without anyone remembering a free.
* **`close` is idempotent and safe on a failed `open`.** The core does this
  (`web.destroy` on a zero-value `App` is contractual), and it is what makes
  the `defer`-immediately-after-init pattern safe to teach.

## 3. Return `(value, ok)`, not sentinel values or strings

The idiom guide is explicit that Go's `error`-interface style and
string-as-error are both rejected. For a Crystal:

```odin
// Simple fallibility — the core's own extractor shape.
path_int :: proc(ctx: ^web.Context, name: string) -> (value: int, ok: bool)

// Fallibility with distinguishable causes — a typed enum, exhaustively switchable.
Query_Error :: enum u8 {
    None,
    Not_Found,
    Constraint_Violation,
    Connection_Unavailable,
    Query_Failed,
}
```

A Crystal's error type is **its own domain's**, never HTTP. `Not_Found` is a
database fact; `404` is an application decision. The mapping between them is
three lines the application writes and can read, and it is the line where
someone eventually needs to return `409` instead of `400` for one specific
constraint. A Crystal that answered HTTP directly would have stolen that
decision.

## 4. Do the work at registration, not in the hot path

The core's data-oriented rule: "If work can be done at registration time, do it
then." Chains are flattened at `use`, not walked at dispatch. Param counts and
pattern metadata are computed once.

A Crystal on the request path inherits this literally. Parse configuration at
`init`. Compile the query at build time, not per row. Resolve the header name
to a constant once. What reaches the hot path should be a prepared,
preferably immutable value, and the Crystal should be able to say which
allocations it makes per request — ideally zero, honestly stated if not.

## 5. Fixed capacity beats a map

Flat arrays, enum-indexed tables, fixed-capacity storage. Maps are for
registration-time work, not per-request work. The core has no per-request map
anywhere and treats that as a feature.

If a Crystal wants a per-request map, that is a design smell worth three
minutes of thought: usually the key set is known and small, and an array with a
linear scan is both faster and simpler at that size.

## 6. State the perimeter, not the adjective

This is the habit that most distinguishes the project's documentation, and it
is worth adopting wholesale. The core's Phase-2 freeze has an entire ledger
dedicated to it.

| Don't write | Write |
|---|---|
| "zero-allocation" | "the chain walk allocates nothing; decoding a body allocates into the request arena" |
| "bounded" | "at most N connections are open; the 65th `acquire` blocks until one is returned" |
| "non-blocking" | "the exporter never blocks the handler; events are dropped when the queue is full, and the drop is counted" |
| "safe" | say what it is safe *against* |

Every bound states what happens when it is reached. Every lifetime states who
frees. Every "costs nothing when unused" states how it was measured — see
[`gate.md`](gate.md), because that particular claim is harder than it looks.

## 7. One canonical form per operation

Guardrail G-01 for the core; the same discipline is worth keeping in a Crystal,
for the same reason. Two ways to open a pool means every reader has to work out
whether the difference matters, and every AI agent has a coin to flip.

Convenience wrappers are the usual way this erodes. The test: does the wrapper
remove *mechanical* steps, or does it remove a *decision*? Removing steps is
fine. Removing a decision hides it, and the person who needed to make it
differently now has to fight the wrapper.

## 8. Comments carry the reasoning, not the restatement

The core's source is unusually heavily commented, and the comments are almost
entirely *why*: why there is no backpointer, why the middleware guard sits on
the dispatch path rather than in `serve`, why the sentence that was there
before was false. That is worth copying. A comment that restates the signature
is noise; a comment that records the alternative you rejected is the thing the
next reader actually needs.

## 9. Threading assumptions are stated, never assumed

The core says `serve` blocks and makes no promise about which thread anything
runs on. A Crystal must say whether its type is safe to share across threads,
whether `init` must happen before any concurrency starts, and what happens if
two goroutine-shaped things call it at once. "Probably fine" is not an answer a
pool can give.

## 10. Compile the examples

Every example in this project's tree is built by the gate, because an example
that does not compile is worse than no example — it teaches an API that does not
exist, to humans and to agents equally. Whatever else a Crystal skips, it should
not skip this.
