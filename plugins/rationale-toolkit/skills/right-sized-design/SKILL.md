---
name: right-sized-design
description: "Sizes design effort to the cost of getting it wrong — build the minimum where change is cheap, design ahead where it is not. Use this skill when writing new code, adding functionality, or making architecture decisions. Triggers on: creating new abstractions, interfaces, or extension points; designing data schemas, API contracts, or serialization formats; deciding what data to keep, discard, or route — filters, gates, admission or relevance checks, ranking and similarity thresholds, sampling, retention and eviction policies; choosing dependencies, concurrency or transaction models; refactoring toward reusability; deciding whether to add error handling or validation; adding new files or modules."
---

# Right-Sized Design

## Core Principle

Design effort must match **reversal cost** — what it would take to change this decision after it ships.

YAGNI ("You Aren't Gonna Need It") is not a rule against thinking ahead. It is a bet that a wrong guess is cheaper to fix later than to prevent now. That bet is only valid where change is cheap. Where change is expensive or impossible, the bet loses and deliberate design wins.

So the question is never "am I over-engineering?" It is: **if this turns out wrong, what does the fix cost?**

## Step 1 — Classify the decision

Before building, ask: *six months from now, what does it take to change this?*

**High reversal cost — design ahead.** Fixing requires coordinating with data, users, or systems you do not control:

| Category | Why it is expensive to reverse |
|---|---|
| Persisted data schemas | Requires migration of existing rows; bad shapes outlive the code that wrote them |
| Published API / event / file formats | Consumers you cannot force to upgrade; needs versioning or a break |
| Security & trust boundaries | Authn/authz, tenant isolation, input validation — a gap is a breach, not a bug |
| Concurrency & transaction models | Retrofitting correctness under load means rewriting call paths, not patching one function |
| Core domain model | Names and relationships propagate into every layer; renaming later is a full-codebase edit |
| Load-bearing dependencies | A library whose types leak into business code is a rewrite to remove |
| Irreversible operations | Deleting data, sending mail, charging money, publishing identifiers — no undo |
| Discarding input | Anything a filter, gate, or threshold drops is gone; a false negative leaves no trace to debug or replay. A cheap pre-filter also caps the whole pipeline's recall — no downstream stage can recover what it never sees |

**Low reversal cost — build the minimum.** Fixing is a local edit by one person in one commit:

- Private functions, module-internal structure, and anything with no external caller
- Implementation details behind a stable interface
- UI layout, copy, styling
- One-off scripts and tooling
- Anything fully covered by tests you own

**When unsure, check blast radius:** how many callers, and are any of them outside this repository? Zero external callers means the decision is almost always cheap.

## Step 2 — Apply the matching rules

### In the low-cost zone: build the minimum

- **No speculative abstraction** — no interfaces, base classes, plugin systems, or config options for a use case that does not exist yet.
- **No premature DRY** — 3 similar lines beat an abstraction built to avoid them. Duplication is cheap; the wrong abstraction is expensive.
- **Delete dead code on sight** — unused functions, exports, flags, or config with no caller get removed, not commented out.
- **Write the concrete version** — if no second use case exists *right now* in this codebase, do not generalize.

### In the high-cost zone: design ahead

- **Design for the shape, not the feature** — model the data as the domain actually is, not as today's single screen needs it. A field that will obviously exist (timestamps, tenant id, soft-delete, currency alongside amount) belongs in the schema now; the code reading it does not.
- **Version from day one** — any format crossing a process or storage boundary carries a version discriminator, even at v1. Adding one retroactively requires guessing what unversioned data meant.
- **Keep the escape hatch** — do not build the general system, but do not foreclose it either. Put the expensive decision behind one seam so it can be replaced without touching every caller.
- **Enumerate what breaks the design** — before committing, name the plausible requirement that would invalidate this choice. If it is cheap to accommodate now and expensive later, accommodate it.
- **Prefer the reversible option at equal cost** — when two designs cost the same to build, take the one that is cheaper to walk back.

## Known future vs. speculative future

The distinction is **evidence**, not timing:

- **Known** — written in the ticket, on the roadmap this quarter, required by a contract already signed, or a second concrete caller that exists today. Design for it. This is not speculation; it is a requirement that has not been typed yet.
- **Speculative** — "we might want to", "this could be useful if", "other teams may need". Do not build it. Do not add the config option, the hook, or the interface.

The failure mode this skill exists to prevent: treating a known, funded, next-sprint requirement as speculative and shipping a schema that cannot hold it.

## What this skill never licenses

YAGNI is routinely stretched to justify things it has nothing to do with. It does **not** excuse:

- **Skipping input validation.** Data crossing a trust boundary (user input, network, files, other services) is untrusted regardless of who calls it today. This is not "handling an impossible case" — it is a case you have no control over.
- **Skipping error handling for real failure modes.** I/O, network, parsing, and concurrency fail in production. Only skip handling for states genuinely unreachable given the code's own invariants — and if you rely on an invariant, assert it rather than assuming it.
- **Scattering one business rule across many call sites.** Duplicating three lines of glue is fine. Duplicating a rule that must change everywhere at once is a defect waiting to happen. DRY applies to knowledge, not to text.
- **Omitting observability.** Logs, metrics, and error context are how a change gets debugged after it ships. They are not features for a hypothetical future.
- **Skipping tests.** Tests are what make the low-cost zone low-cost. Cutting them is what turns a cheap decision expensive.
- **Trading correctness for unmeasured performance.** A cheap heuristic bolted in front of an accurate-but-costly step is not a minimal implementation — it is extra machinery that buys a speedup nobody measured, paid for in accuracy. Build the correct version first; optimize only against a real profile, and only where the fast path cannot silently produce a wrong answer.

## Quick check

Before writing an abstraction, schema, interface, or anything that decides what data moves forward, answer in one line each:

1. **Reversal cost** — local edit, or coordinated migration?
2. **Evidence** — is the second use case real today, or written down as committed work? If neither, do not build it.
3. **Escape hatch** — if this is wrong, what is the smallest change that fixes it?

If (1) is "local edit", default to the minimum. Otherwise, state the trade-off explicitly before committing to it.
