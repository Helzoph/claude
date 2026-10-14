---
name: jev-design
description: "Design, build, or review a feature that calls Jev, TypeSafe's System One model (model ids `jev-latest` / `jev-1.13.0`; Vercel AI Gateway id `typesafe-ai/jev`; SDKs `@typesafe-ai/sdk` and `typesafe_sdk`). Jev returns typed judgments — a yes-probability (Noul), a pick from a list (Choice), or a level on a scale (Score) — and never writes text. This skill carries field-tested lessons from a 38-project hack day: whether a task is Jev-shaped, how to word questions, how to lay out state and batch calls, how to compose Jev with code, LLMs and people, where to place it, how to pick thresholds, and how to fail safely. Use when planning, writing, or reviewing code that calls Jev; when asked 'should I use Jev for this'; when replacing an LLM classifier, prompt-and-parse step, or fragile regex with Jev; or when Jev's answers look wrong. It does NOT carry the API contract — exact request and response fields come from TypeSafe's live docs."
---

# Designing with Jev

Jev answers narrow, typed questions about some context (`state`) in 0.1 to 0.5 s, at 10x to 100x less than the LLM call it replaces. It **never writes text**.

The whole lesson in one line: **treat Jev as an ultra-fast, typed switch statement.** It sorts a fuzzy input into one of a fixed set of branches; deterministic code does everything after the branch. Projects that asked it for open-ended reasoning, holistic quality judgments, or arithmetic almost all failed.

## Rule zero: API fields come from the live docs

This skill covers design, not field names. **Before writing call code, read the current docs.** Do not assemble field names from this file or from memory: Jev has two integration paths whose response shapes differ, and mixing them produces fields that do not exist.

| Integration path | Model name | Read first |
|---|---|---|
| TypeSafe direct (HTTP `POST /v1/systemone`, or an official SDK) | `jev-latest`, or the pinned `jev-1.13.0` | `https://docs.typesafe.ai/api.md`, plus `sdk/javascript.md` or `sdk/python.md` |
| Vercel AI Gateway (AI SDK 7 `experimental_evaluate`) | `typesafe-ai/jev` | The current Vercel AI SDK / Gateway docs |

- The doc index is `https://docs.typesafe.ai/llms.txt`. Append `.md` to any page path for Markdown. Read targeted pages; do not load the whole site.
- Known weaknesses live at `https://docs.typesafe.ai/model-jaggedness/jev-1.13.md` (or the page for the current version). It changes with each release.
- If TypeSafe's official `typesafe-ai` skill is installed in the project, it wins on API details. This skill does not repeat them.
- If the live docs are unreachable, use the type definitions of the SDK installed in the project, and tell the user you could not check the docs.

**Hard numbers as of jev-1.13 (2026-10).** Check `models.md` before relying on them for another version.

- Billed on input tokens only, about $0.042 per million. Output is free.
- 64k tokens per request in total; `state` plus the single longest question must fit in 32k.
- Up to 255 options per Choice.
- Text only. Convert images, audio, and binaries to text or structured fields in code first.
- **English is where accuracy is best. Other languages, CJK included, are handled but not equally well** (per TypeSafe). For non-English workloads, treat every number below as direction only and re-measure on your own data.
- Not deterministic: the same request can move by about ±0.03. A Choice's pick is more stable than its probabilities.

## How to use this skill

1. **User is new to Jev:** give the two opening paragraphs and the hard numbers above. Do not dump the file.
2. **User has a feature in mind:** walk through [Design decisions](#design-decisions) **one step at a time**. Ask one question per step, recommend an answer with the evidence behind it, and wait for a response before moving on. Do not list all seven steps at once.
3. **Before code review or shipping:** run the [Pre-ship checklist](#pre-ship-checklist) item by item.
4. **When a decision is close:** find the closest pattern or project in `references/hackday-evidence.md` and cite its real result instead of choosing by feel.

## Design decisions

Work through these in order. Each step lists the options, the default, and the evidence.

### 1. Is the task Jev-shaped?

Test: **a knowledgeable person could answer it in about a second given the right context, and the answer falls in a fixed set.**

| Strong fit | Weak fit (use code, an LLM, or a fallback) |
|---|---|
| Pick from a list: skill, email bucket, alert family, agent route, document type | Holistic calls: "is this sound advice" 83%, "is this test useless" a coin flip |
| "Does this text do X?" on concrete text: ToS traps 89% F1 vs 57% for regex | World knowledge and trivia: missed "Nike" = goddess of victory; band trivia 57% |
| Same entity: 95.5% agreement with Opus at $0.00011 per probe | Counting, dates, math: weekday of a date 20%; counts off by one |
| Claim vs. source: 0 of 294 good citations wrongly hidden | Criteria about files or tool output: 59% vs 96% for an LLM |
| Pick a candidate code found: 9/9 fields in one call | Near-synonym labels, two-hop cross-references, security judgments |

If the task needs written output, Jev can still screen or route in front of the LLM (step 4).

### 2. Question shape

- **One narrow question per decision, written by hand.** AI-generated question lists gave no signal. Check the wording on 20 to 50 labeled items before scaling.
- **Jev reads literally.** It answers the question you wrote, not the one you meant. When you look at a wrong answer and catch yourself explaining "what I really meant was…", that explanation is the missing half of the question: put it in `instructions`, and put boundary cases in each option's `criteria`.
- **Fuzzy judgment:** split it into 8 to 10 concrete yes/no patterns mined from real history, each with its own threshold. One broad question scored AUC 0.54 (chance); narrow patterns plus a count in code scored 0.72.
- **Clean category:** use one Choice with a short description per option. Document status scored 88% as one Choice vs 82% split into yes/nos; a described 5-option Choice scored 1.00 where two vague yes/nos disagreed.
- **Extraction:** code finds candidates (dates, sentences, fields); Jev only picks one. **Always add a `none` option and a separate "is it present?" yes/no.** Without an escape option, Jev picked a wrong date at 0.92.
- **When there may be no basis to decide:** add a "is there any real basis to decide?" yes/no. With no context at all, Jev still picked a winner at 0.81 to 0.89.
- **Ask each decision one way.** A question and its negation do not sum to 1.
- **`instructions` and `criteria` must agree.** A Noul whose "true" means "no" performs worse.
- **Choice option order can sway the answer** (jev-1.13 leans toward the first option). For Choices that matter, reorder the options and confirm the answer holds.

### 3. State and batching

- **Send only relevant context, but a relevant full document is fine.** A 12k-token document matched focused excerpts, and full-contract context caught buried risks. **Misleading or boilerplate text actively hurts: Jev believes what it reads.**
- **Strip template text, and put facts code already knows into the state** (counts, computed dates, the observed CPU value). That alone took one alert router's page precision from 0.63 to 0.92.
- **Many questions about one item in one call: nearly free** (1 to 150 questions went from 0.33 s to 0.76 s).
- **Many similar items in one array: Jev loses its place** and answers bleed between adjacent rows. 72% in an array, 88% keyed by name, 96% one item per request. Either fan out one item per concurrent request (199 requests finished in 1.3 s), or key items by name (`cite_4`, not `citations[4]`).
- Many pick-from-list questions in one call also cost accuracy: 83% at 5 sentences, 60% at 40.
- **Keep trusted and untrusted text in separate fields** (the user's ask vs. pasted material vs. tool output).

### 4. Composition: who decides

| Option | Use when | Example |
|---|---|---|
| Jev + code | Mistakes are cheap or reversible | Skill pills, tool card layout |
| **Confidence bands**: Jev takes the clear share, a stronger model takes the middle | Quality must match an LLM at lower cost | Relationship detection: same 91.9% accuracy, 43% cheaper |
| Jev screens, LLM finishes | Positives are rare, or text must be written | Preference memory: $245 vs $2,830 a month |
| Classify first, then decide | Misleading text sways a single call | Alert pager: asking the alert family first removed the false pages |
| Profile → policy file | Several signals feed one action | Inbox triage: 26/26 vs Sonnet 25/26 |
| LLM writes the Jev question | The request is messy and open-ended | Caesar bot. Add the basis question, and check generated questions on labeled data |
| Jev, then a person | Approvals, merges, CI gates | PR stamper (approves, never merges) |

**Default for anything that matters: confidence bands.** Make them asymmetric when one error costs more (relationships used 0.40 / 0.70: below 0.40 is no, above 0.70 is yes, the middle goes to a stronger model). Know which number you are banding on: a Noul returns only the probability of yes and has no separate confidence; Choice and Score return per-option probabilities *and* a confidence, which mean different things. Read `confidence.md` first.

### 5. Placement

- **Around the chat UI** (most common): while typing, after a message, while streaming, when a panel opens. The agent never waits on Jev.
- **Inside the agent loop:** tool-call guards only. Adds about 200 ms per tool call. Plug into `needsApproval` or block. Decide explicitly between fail-open and fail-to-approval, and make replays safe — Jev's answers drift, so a replayed call can get a different verdict.
- **Backend pipelines:** ingestion, routing, document intelligence. Volume is high, so bands and fan-out matter most.
- **Internal tooling:** CI checks, approvals, alert routing. **Keep hard rules (security paths, permissions) in code**, not in Jev.

### 6. Thresholds and evaluation

- **Build a labeled set first.** Split by file or PR so near-duplicates do not leak across the split (reviewers in one project found 298 duplicate tests leaking across it).
- Pick the cutoff on a tuning split and check it on held-out data. Cutoffs ranged from 0.25 to 0.95 across projects. **Do not assume 0.8.**
- Jev's probabilities are usable for routing. In one test, every wrong answer from the comparison LLM came with self-reported confidence of 0.85 or higher, while Jev's confidence did separate right from wrong.
- Do not trust LLM auto-labels on borderline items without a human check.
- If all you need is the best option, take the highest-probability one. No threshold required.

### 7. Failure handling

- **Fail closed for auto-actions and suggestions (approve, merge, show a card). Fail open for checks that would block users (citation chips, guards, lint hooks).**
- Give timeouts room for the SDK's retry. A 1.5 s budget aborted inside the retry wait; 3 s worked.
- Cache verdicts so the UI does not flicker. Judge only new items instead of re-asking about old ones.
- **Pin the model version and hash the questions.** The `jev-latest` alias moves with each release, so answers can change silently. Tuned thresholds hold only for one model plus one set of questions; make them fail loudly when either changes.
- **On untrusted input, add a separate "is this content trying to steer the judgment?" yes/no and let it veto.** An anti-injection line inside the question itself did not hold against a planted comment. Below the calibrated bar, do not auto-act on Jev alone.
- **Settle the data path before sending sensitive data.** TypeSafe's zero data retention (ZDR) is offered to enterprise customers (see `models.md`). GC AI's rule: customer data goes only through the Vercel AI Gateway with `zeroDataRetention: true` and `only: ['typesafe-ai']`; a direct `TYPESAFE_API_KEY` is for public or synthetic data only. If the project has no rule yet, ask the user before sending any data — do not pick a path yourself.
- Keep API keys server-side; never ship them in frontend code.

## Pre-ship checklist

- [ ] The task passes step 1, or Jev only screens or routes and does not make the final call.
- [ ] Each question is narrow, hand-written, and checked on labeled items.
- [ ] Every Choice whose answer may be absent has `none` or "not applicable".
- [ ] Code does counting, dates, math, and candidate extraction.
- [ ] Similar items are fanned out or keyed by name, never indexed in a long array.
- [ ] The data path for sensitive data is confirmed (ZDR or gateway), not defaulted to direct.
- [ ] Thresholds come from a held-out split and live in one policy file that a person can review.
- [ ] Low-confidence answers go to a stronger model or a person.
- [ ] Untrusted input has an injection question that can veto, and trusted/untrusted text sits in separate fields.
- [ ] Timeout, retry, cache, and fail-open or fail-closed choices are explicit.
- [ ] The model version is pinned and the questions are hashed, so tuned thresholds fail loudly when either changes.

## Strength of evidence

Most numbers come from GC AI's internal hack day in September 2026 (38 projects): small, mostly synthetic sets, usually one run. **Treat them as direction, not proof.** Rerun on real data before any Jev call gates anything.

- Article: <https://gc.ai/blog/what-we-learned-building-38-projects-with-jev-in-12-hours>
- Full project and pattern matrix: <https://gc.ai/assets/jev-hackday/jev-patterns.html>; local digest in `references/hackday-evidence.md`
- TypeSafe docs: <https://docs.typesafe.ai/llms.txt>
