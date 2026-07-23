# Allocation audit — WP27

**Status: MEASURED, WITH A DECISION PER ITEM.** RG-3's question was "where does
per-request allocation actually go?" and its required output was "a measured
list, and a decision per item". This is both.

**WP27 changes no behaviour.** Fixing belongs to WP29 and WP35, where a change
can be regression-tested against the WP26 baseline. Every number below is
produced by `tests/wp27-internal`, which runs in the mandatory gate.

---

## 0. The perimeter, before any number

Phase-2 claim **C-5** says *"dispatch through a middleware chain allocates zero
bytes"*, scoped to **the chain walk**, measured around
`driver_run`/`driver_cleanup` and explicitly *not* around `test_request`.

Everything in this document sits **outside the chain walk** — on the
request-construction and response-copy edges of the same pipeline. Nothing here
contradicts C-5, and no number here may be quoted as if it did. C-5's own "does
NOT guarantee" line already says the request as a whole allocates.

---

## 1. The measured list — one socket request, end to end

Per request on the production (socket) path, in pipeline order:

| # | Site | Allocations | Sized by | Audit item |
|---:|---|---:|---|---|
| 1 | `inbound_header_pairs` (`serve.odin:148`) | **1**, from `temp_allocator` | request header count | **A-8** |
| 2 | `response_headers_neutral_transport` (`serve.odin:166`) | **1** | response header count | **A-13** |
| 3 | `copy_response` header array (`odin_http_adapter.odin:184`) | **1** | response header count | A-13 |
| 4 | `copy_response` name + value clones (`:187-188`) | **2 per header** | response header count | **A-12** |
| 5 | `copy_response` body clone (`:197`) | **1** when the body is non-empty | — | — |

### The totals, for real response shapes

| Response | Response headers | Allocations |
|---|---:|---:|
| `204 No Content`, no request headers | 0 | **0** |
| `200` JSON, no request headers | 1 (`Content-Type`) | **5** |
| `200` JSON + `request_id` middleware | 2 | **7** |
| `405`, `Allow` + `Content-Type` + `X-Request-Id` | 3 | **9** |

Add **1** whenever the request carries any header at all (item 1 — one
allocation regardless of how many).

**Of a typical JSON 200's five allocations, two are clones of strings that never
needed cloning.** That is the honest headline, and §4 explains why removing them
is not the one-line change the audit item implies.

---

## 2. A-8 — inbound headers

> *"Inbound headers are allocated and copied every request, and no Phase-1 path
> can read them."* — `planning/post-phase1-audit.md:83`

**Measured.** One allocation per request, from `context.temp_allocator`, of
`count × size_of(Header_Pair)` bytes — **one slice, not one per header**. A
request with zero headers allocates **nothing**; the empty case returns nil.

**The audit's wording is half wrong, and the wrong half matters.** "Allocated
and copied" — the slice is allocated, the strings are **not** copied. Every name
and value is a view over transport-owned storage, pinned by
`wp27_a8_pairs_view_transport_storage`. If that ever stopped being true the cost
would be far larger than the audit recorded *and* G-05's lifetime contract would
have changed underneath everyone, so the test guards both.

**Also stale:** "no Phase-1 path can read them" was true when written. WP19
shipped `web.header` and `web.bearer_token`, so these pairs are now read on
every request that looks up a header. The item was filed as waste; it is now a
cost with a consumer.

**DECISION — keep, and hand the shape question to WP35.** One temp allocation
per request, only when headers exist, is not obviously worth removing. The
plausible fix is a fixed-capacity inline array on the `Context` with an overflow
path, which is exactly the buffer-reuse question **WP35** owns. Deciding it here
would decide it without the arena policy that governs it.

---

## 3. A-13 — the two conversions

> *"`Header_Pair` ≡ `transport.Header` structurally; two O(n) conversions per
> request purely to satisfy the one-way boundary. The honest price of
> ADR-009."* — `:93`

**Measured and confirmed exactly as filed.** One allocation inbound, one
outbound, both view-preserving, both `count × size_of(Header)` bytes. Two
structurally identical two-string structs, converted each way, once per request.

**DECISION — pay it, and stop calling it a defect.** The price is two
allocations per request and no string copying. What it buys is
`build/phase1-direct-dependencies.txt` staying enforceable and the transport
staying replaceable — the README's promise that the vendored backend "may be
rewritten as long as the observable contracts hold" is only true because no
transport type crosses into `web`. Unifying the types would delete two
allocations and ADR-009 together.

This item should be **reclassified from "cost to remove" to "cost accepted, with
a number"**. The number is now measured, so a future argument for changing
ADR-009 has something to weigh instead of an adjective.

---

## 4. A-12 — the response clones, and the correction

> *"Static response headers are `strings.clone`d every request although
> `response.odin:164-166` states they are static strings."* — `:92`

**Measured.** `copy_response` clones **both** the name and the value of every
response header: 2 allocations per header, plus one for the array, plus one for
the body.

**THE AUDIT ITEM CANNOT BE ACTED ON AS WRITTEN, AND ACTING ON IT LITERALLY WOULD
SHIP A DANGLING VIEW.** `response.odin`'s sentence is about the header *pairs
the framework writes*, and it is true of some strings and false of others:

| Header | Name | Value | Aliasable? |
|---|---|---|---|
| `Content-Type` | package constant | package constant | **yes, both** |
| `Allow` | package constant | `Context_Internal.allow_buffer` | **name only** |
| `X-Request-Id` | package constant | `Context_Internal.request_id_buffer` | **name only** |

Two of the three values point into request-local storage on the `Context` — a
fixed array that dies at `driver_cleanup`. `copy_response` exists precisely to
survive that: the adapter must own the bytes it sends. Aliasing them would hand
the transport a view into freed memory, and the failure would be
timing-dependent and rare, which is the worst shape a bug can have.

`wp27_a12_only_some_response_strings_are_static` pins the contrast: two headers,
the same struct, opposite lifetimes.

**So the change is not "stop cloning static headers".** It cannot be made by
knowing that a *header* is static — only by knowing which *string* is. The pair
would have to carry that knowledge, which is a design change, not an
optimisation.

**DECISION — the item is REWRITTEN, not scheduled.**

* **A-12 as filed is withdrawn.** "They are static strings, so the clone is
  waste" is false for two of the three headers this framework emits.
* **What survives:** every response header *name* is a package constant, and
  cloning names is unambiguous waste — **one allocation per header per request**,
  with no lifetime question at all.
* **The remaining value clones are correct** and must stay until something
  distinguishes owned values from borrowed ones.
* **Owner: WP29**, where the response path is already being touched and the
  saving can be measured against the WP26 baseline rather than asserted.

Expected saving if only the names stop being cloned: **1 allocation per response
header per request** — 1 on a JSON 200, 3 on a 405 with a request ID. Against
FINDING-E's ±57.6% timing noise floor this will not be visible as a *timing*
improvement at any cardinality, and it should be justified as an allocation
reduction or not at all.

---

## 5. What this audit did not measure

* **Bytes on the socket path end to end.** Every figure here is a count taken at
  the procedure boundary. A whole-request byte total would need the socket
  driver instrumented, which is a WP35 concern.
* **The request arena.** JSON body binding allocates into a per-request
  `mem.Dynamic_Arena`, which is R-16 and belongs to **WP35**, not here.
* **Peak or retained memory.** Still owed, as `planning/benchmark-methodology.md`
  §12 records.
* **Anything under concurrency.** Single-threaded measurement throughout.

---

## 6. Summary for WP28 and WP29

* **The router shootout inherits nothing from this audit.** None of A-8, A-12 or
  A-13 is on the route-matching path; all three sit on the request/response
  edges. WP28 may proceed without waiting on any decision here.
* **WP29 inherits one concrete change:** stop cloning response header *names*,
  and keep cloning values.
* **WP35 inherits two open shapes:** the inbound pair slice (A-8) and the
  request arena.
* **ADR-009's price is now a number** rather than an adjective: two allocations
  per request, no string copying.
