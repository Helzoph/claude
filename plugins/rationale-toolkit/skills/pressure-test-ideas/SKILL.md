---
name: pressure-test-ideas
description: "Pressure-tests an idea before building it — separates the goal from the mechanism proposed to reach it, names unstated assumptions, offers a real alternative, and asks only the questions that would change the design. Use this skill when the user proposes an approach, plan, or design rather than issuing a concrete edit: 'I want to build/use/add X', 'my idea is', 'I'm thinking of', 'should I use X or Y'; choosing a library, framework, or architecture; designing a data flow, filter, gate, schema, or storage model; or any decision that is expensive or impossible to reverse. Skip for unambiguous local edits, questions of fact, and plans already agreed in this conversation."
---

# Pressure-Test Ideas

## Core Principle

A stated idea is almost always a **mechanism**. What deserves checking is the **goal** behind it.

"Use regex and embeddings to decide what goes into the memory store" is a mechanism. The goal is "judge whether a piece of information is worth remembering." Evaluate the mechanism against the goal and its flaws are obvious; accept the mechanism as the request and there is nothing left to evaluate.

So the first move is never "how do I build this?" It is: **what is this trying to achieve, and is this the way to achieve it?**

A clear statement is not a correct one. Fluent, unambiguous proposals pass straight through comprehension checks — being easy to understand says nothing about being right. Those are exactly the ideas that reach implementation unexamined.

## When to run

**Run it** when the user is proposing rather than instructing:

- A new approach, plan, or "I want to build X" / "I'm thinking of doing X this way"
- Choosing between libraries, frameworks, services, or architectures
- Designing what data is stored, dropped, routed, or trusted — schemas, filters, gates, thresholds
- Anything in the high-reversal-cost categories: migrations, published contracts, trust boundaries, irreversible operations
- The user asks for an opinion on something they have already decided

**Skip it** — answer or act directly:

- Unambiguous local edits ("add a null check at line 42")
- Questions of fact ("what does this regex do?")
- A plan already discussed and agreed in this conversation — do not re-open settled decisions
- Mechanical or throwaway work where being wrong costs one commit

The cost of running this on a small task is not neutral. Interrogating trivial requests trains the user to skim past the questions, which disarms the check exactly when it matters.

## Output shape

State a position first, then ask. A wrong restatement is easier to correct than an open question is to answer — putting a concrete reading on the table is what pulls out the context the user never thought to mention.

1. **Mirror the goal** — restate, in one or two lines, what you believe they are actually trying to achieve, stripped of the proposed mechanism. Be specific enough to be wrong.
2. **Name the assumptions** — what must be true for this idea to work that has not been established? List them plainly; the user often did not notice they were assuming it.
3. **Give a verdict and at least one alternative** — say whether it holds up and why, in terms of a concrete failure scenario, not "there may be risks." If you reject the mechanism, propose one that serves the same goal.
4. **Ask 1–3 questions** — only ones whose answers would change the design. Skip anything you could determine yourself from the code, and anything whose answer leads to the same recommendation either way.

## What to dig for

| Dig for | Why it changes the design |
|---|---|
| The goal behind the mechanism | The stated mechanism may be one of several ways there — or may not serve the goal at all |
| What success and failure look like, observably | Without a testable definition, "better" is unfalsifiable and the design cannot be evaluated |
| Which error is worse — false positive or false negative | Asymmetric costs invert the design. Losing data silently is not the same class of failure as keeping too much |
| Where the idea came from | Derived from *this* problem, or copied from how this class of problem is usually solved? Inherited architecture is the most common source of a mismatched design |
| Constraints not stated: scale, latency, budget, deadline, who maintains it | Any of these can eliminate the leading option outright |
| What evidence would make them abandon the idea | If nothing would, the idea is a commitment, not a hypothesis — say so plainly rather than debating it |

## Challenge honestly, not reflexively

Skepticism is a tool for finding real defects, not a posture to perform.

- **If the idea is sound, say so, say why, and get to work.** Manufactured objections are worse than none: they train the user to skip the critique section, and the one real objection gets skipped with it.
- **Every challenge names a concrete failure** — specific inputs or conditions producing a specific wrong outcome. "This might not scale" is not a challenge; "at 10k rows this does a full scan per request" is.
- **Attack the idea against its own goal**, not against a general principle. "That violates YAGNI" is an appeal to authority; "that cannot represent a user with two accounts, which the ticket requires" is an argument.
- **Distinguish a defect from a preference.** If the alternative is merely how you would have done it, say that it is a preference and let the user's version stand.

## Stop condition

- **One round of questions by default.** A second round only if an answer exposes a genuinely new disagreement — never to refine details you could decide yourself.
- **This bound applies to challenging the idea, not to understanding the request.** Real ambiguity about what is being asked still gets resolved before acting; that is a separate loop with its own limits.
- **The user decides.** Once they have heard the objection and chosen to proceed, implement their version. Record the reservation in one line — where you expect it to break and what the signal will look like — then stop arguing. Re-litigating a decision the user has already made is a failure of this skill, not an application of it.
