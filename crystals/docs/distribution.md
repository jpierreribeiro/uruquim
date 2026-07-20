# Distribution — living without a package manager

**Status: PROPOSED.** The recommendation here is the most reversible thing in
these documents: moving a package between repositories is mechanical. Do not
over-think it.

---

## The constraint, stated plainly

Odin has no official package manager, and will not get one. The core treats
this as settled rather than as a gap to work around
(`planning/phase-3-plan.md` §4: *"C-8: Odin will never officially support one"*).
Consumption is by vendoring or submodule, and the **toolchain version is part of
the contract** — `odin-version.txt` pins a release, a commit and an asset
SHA-256, which is stronger than most ecosystems that do have a resolver.

Two things follow, and they are not obvious:

* **There is nothing to resolve, so there is nothing to get wrong at build
  time.** No network, no lockfile solver, no transitive version conflict, no
  post-install scripts. The ecosystem's hardest distribution problem is
  *recording* what you built against, not *computing* it.
* **Collections are the unit of import, not packages.** `-collection:name=path`
  makes a directory an import root; packages are directories under it. So the
  shape of the ecosystem is decided by how many collections a consumer must
  pass on the command line, and that number should be small.

---

## Proposed shape: one collection, one repository, to start

```text
uruquim-crystals/                    # -collection:crystals=…
├── README.md
├── COMPATIBILITY.md                 # the matrix (below)
├── odin-version.txt                 # same pin format as the core
├── build/
│   └── check.sh                     # the shared gate
├── docs/
├── sql/                             # crystals:sql
├── db/
│   ├── postgres/                    # crystals:db/postgres
│   └── migrate/                     # crystals:db/migrate
├── web/
│   ├── health/                      # crystals:web/health
│   └── secure/                      # crystals:web/secure
├── dev/
│   └── watch/                       # crystals:dev/watch
└── examples/
```

**Why one repository first**, when the long-term shape is probably many:

* One `-collection:crystals=…` flag for the consumer instead of one per Crystal.
* One Odin pin, one compatibility matrix, one gate.
* Atomic changes while the core is still moving. When Phase 3 changes something,
  five Crystals can be fixed in one commit rather than five coordinated releases.
* Fewer submodules for a user to configure, which matters more than it sounds
  when there is no tooling to configure them for you.

**When a Crystal should leave** and become its own repository: it grows a large
native dependency, needs a different licence, gets a different maintainer, needs
an independent release cadence, or becomes useful to people who do not use
Uruquim at all. The SQL builder is the most likely first candidate for the last
reason.

### The alternative that was considered and is not recommended

A `crystals/` or `druses/` directory **inside the core repository**. It has one
real advantage — zero setup for the consumer — and two disqualifying problems:

* It puts optional code inside a repository whose entire value proposition is a
  small, frozen, gate-enforced surface. Every future reader would have to be
  told which directories are the framework and which are not.
* `planning/roadmap.md` M5 already plans to *retire* `planning/`, `experiments/`
  and the knowledge base from the public tree. Adding a large optional subtree
  in the opposite direction, now, works against a decision already taken.

*(This document lives in the core repository, but it is documentation of an
idea, not shipped code. That distinction should not be allowed to blur.)*

---

## The consumer's layout

```text
my-api/
├── cmd/api/           # the server
├── internal/          # domain code — imports no framework (G-02)
├── tools/dev/         # the watcher's tiny main, if used
├── migrations/
└── vendor/
    ├── uruquim/       # submodule, pinned SHA
    └── crystals/      # submodule, pinned SHA
```

```bash
odin build ./cmd/api \
  -collection:uruquim=./vendor/uruquim \
  -collection:crystals=./vendor/crystals
```

```odin
import web "uruquim:web"
import sql "crystals:sql"
import pg  "crystals:db/postgres"
```

Submodules pinned to SHAs, never floating branches. Documentation that shows
`main` teaches an unreproducible build.

---

## Compatibility, when there are no versions

There is no Uruquim tag and no release; cutting one is the owner's decision and
the roadmap says not before M2. So compatibility cannot be a version range. It
is a **statement about commits**:

```text
Odin release      dev-2026-07a
Odin commit       819fdc7
Odin asset SHA    32a7678a…
Uruquim commit    <sha>
Uruquim phase     Phase 2 frozen (ledger 46)
Crystal commit    <sha>
Verified on       Linux x86-64
```

Every row is checkable, and "verified" means the gate ran, not that someone
believed it. The core is honest that only Linux x86-64 is tested
(`planning/roadmap.md`, M2); a Crystal must be equally specific rather than
inheriting an optimism nobody measured.

When tags eventually exist, this becomes ranges. Until then, precision costs
nothing and vagueness costs a bug report nobody can reproduce.

---

## Combinations that are known to work

**There is no artifact for this, and there should not be one.** A set of
Crystals verified together against one Uruquim commit and one toolchain is a
**tag on the Crystals repository** — nothing more. "At this tag, these Crystals
were tested together against that Uruquim commit, and these examples compile."

This section previously proposed a `uruquim-druse-*` repository with
submodules, a matrix and a check script. That was wrong, and
[`glossary.md`](glossary.md) records why: "Druse" names the philosophy — small
crystals lining a cavity another rock deliberately left empty — and turning a
metaphor into a deliverable is precisely the accretion this ecosystem exists to
avoid.

The failure mode to watch is the same one either way: the moment a curated
combination starts exporting a convenience procedure, it has become a framework
wrapping a framework, and the layer the whole design was built to prevent has
appeared anyway — this time from the outside.
