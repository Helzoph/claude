# typesafe-jev

A Claude Code plugin that teaches an agent how to **design** features around
[Jev](https://docs.typesafe.ai/introduction), TypeSafe's System One model.

Jev answers narrow, typed questions about some context — a yes-probability
(Noul), a pick from a list (Choice), or a level on a scale (Score) — in 0.1 to
0.5 s, at a tenth to a hundredth of an LLM call's cost. It never writes text.

## The problem

Jev is easy to call and easy to misuse. An agent that has only read the API
reference will happily:

- ask one broad question ("is this test useless?") and get a coin flip back;
- pack fifty similar rows into one array and watch answers bleed between rows;
- ask Jev to compare dates or count items, which it cannot do reliably;
- hard-code 0.8 as the threshold because it looks reasonable;
- treat a typed answer as a correct answer and let it auto-merge something.

None of these fail loudly. The call returns 200 and a well-formed answer.

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`jev-design`](skills/jev-design/SKILL.md) | "should I use Jev for this", planning or reviewing code that calls Jev, replacing an LLM classifier or fragile regex, Jev answers that look wrong | Walks one decision at a time through task fit, question shape, state and batching, composition, placement, thresholds, and failure handling; ends with a pre-ship checklist |

`skills/jev-design/references/hackday-evidence.md` holds the evidence behind
each recommendation: 38 projects, 16 reusable patterns, and a did-well /
struggled table, so a close call can cite a real result instead of a guess.

## Design notes

**No API contract in the skill.** Field names, response shapes, model ids,
limits, and prices change between Jev versions, and there are two integration
paths (TypeSafe direct, and the Vercel AI Gateway via AI SDK 7) whose
responses are shaped differently. A frozen copy here would go stale with
nothing to catch it, and TypeSafe's own docs list "the agent invents request or
response fields" as the symptom of a stale skill. So the skill sends the agent
to `https://docs.typesafe.ai/llms.txt` for anything contract-shaped and keeps
only what the docs do not cover: field-tested design judgment.

**Complements, not replaces, TypeSafe's official skill.** TypeSafe publishes
`typesafe@typesafe-ai` (`claude plugin marketplace add typesafe-ai/skills`),
which covers the programming model and points at the live docs. This plugin
adds the lessons from shipping: which shapes worked, which failed, and by how
much. Installing both is fine; where they overlap on API details, the official
skill and the live docs win.

**Numbers are direction, not proof.** The evidence comes from GC AI's
September 2026 hack day — small, mostly synthetic sets, usually one run. Jev's
own docs say English is where accuracy is best and other languages, CJK
included, are handled but not equally well. The skill says so in-line so an agent does not quote "89% F1" as a
guarantee for a Chinese-language workload.

**The evidence table is generated, not hand-copied.** It was extracted from
the data embedded in GC AI's public pattern explorer so the numbers match the
source verbatim. It is English for the same reason.

## Sources

- [What we learned building 38 projects with Jev in 12 hours](https://gc.ai/blog/what-we-learned-building-38-projects-with-jev-in-12-hours) — GC AI, 2026-10-06. The skill is adapted from the `jev-design` skill published in that post, with company-specific paths, packages, and links removed.
- [Jev hack day pattern explorer](https://gc.ai/assets/jev-hackday/jev-patterns.html)
- [TypeSafe docs](https://docs.typesafe.ai/llms.txt), in particular
  [Models](https://docs.typesafe.ai/models.md) and
  [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13.md)

## Installation

From within Claude Code:

```
/plugin marketplace add helzoph/claude
/plugin install typesafe-jev@helzoph-claude-marketplace
```

The skill needs no credentials. To actually run Jev calls you need a
`TYPESAFE_API_KEY` from [console.typesafe.ai](https://console.typesafe.ai/keys)
or a Vercel AI Gateway key.

## License

Apache-2.0
