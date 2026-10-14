# Jev hack day evidence

Generated from the data embedded in <https://gc.ai/assets/jev-hackday/jev-patterns.html> (GC AI, Jev Hack Day, 2026-09-29), fetched 2026-10-14. Original wording kept in English so numbers and quotes stay verbatim.

Numbers come from small, often synthetic sets, usually one run: direction, not proof. Rerun on real data before a Jev call gates anything.

Flow notation: `[code]` deterministic code, `[Jev]` a Jev call, `[LLM]` a generative model, `[person]` a human, `[I/O]` input or output. `→` is sequence, `/` is parallel branches.

## Top-line takeaways

- **Small typed questions, code decides.** Jev answers yes/no, pick one, or a score. Code counts, parses dates, holds thresholds in one file, and acts.
- **Jev first, fallback on the unsure share.** Every head-to-head that sent low-confidence items to a stronger model matched it at a fraction of the cost. The research cards all landed on "use Jev with a fallback".
- **Jev picks, code generates.** Code finds candidates (dates, sentences, fields) and Jev chooses. Always add "none" and a "present?" question: 0.92 wrong became 1.00 right.
- **Batch questions, not similar items.** Many questions about one item in one call is free. Many similar items in one array loses its place (72% vs 96%): key them or fan out.
- **Relevant context helps, misleading text hurts.** A whole 12k-token document matched excerpts and caught buried risks. But alert boilerplate caused false pages: Jev believes what it reads.
- **Hand it computed facts.** Weekday math 20%, Breakout reflex 17 → 29 with the landing x, pager precision 0.63 → 0.92 with the CPU value. Narrow questions beat broad ones.

## Where Jev did well vs. struggled

| Task type | Verdict | Evidence | Projects |
|---|---|---|---|
| Pick from a fixed list (routing) | Great | Skill match 21/21; alert family 133/136; movie title 46/50 over 253 options | Jev Skill Match, jev-pager, Jev Arcade and checkers, Agent routing drop-in |
| "Does this text do X?" on concrete text | Great | ToS traps 89% F1 vs 57% regex; SMS spam 100%; CI check 95 to 98% vs 4 to 16% | ToS Trap Spotter, Arrays vs one item per request, CI false-alarm clearer |
| Select-not-generate extraction | Great | 9/9 fields in one call; 14/14 on GitHub ToS; inbox deadlines 26/26 | Jev test battery, Jev Inbox Triage |
| Same entity / record matching | Great | 95.5% agreement with Opus at $0.00011 per probe | Same buyer? checker, Entity matcher swap |
| Does the source support the claim? | Great | 0 of 294 good cites hidden; verification 6/6 | Citation verifier, Streaming citation validator, Jev test battery |
| Objective rubric criteria | Good | 94% agreement; legal accuracy 98.7% vs 87.4% | Jev as an eval judge |
| Document type and status | Good with fallback | Type 87% vs Opus 93%, status 88% vs 87%; 90% right at confidence ≥ 0.7 | Document type and status bench |
| Document relationships | Good with fallback | Alone 84.6% vs 91.9%; with bands 91.9% at −43% cost | Relationship detection gate, Relationships by doc comparison |
| Ranking risk within a document | Good | Top 6 sentences all planted risks with full-contract context | Contract risk simulator |
| Rare positives (preferences) | Good with fallback | Precise but found 1 of 11 alone; great as a screen | Preference Memory |
| Holistic / subjective calls | Weak | "Sound advice" 83%; "useless test" AUC 0.54 | Jev as an eval judge, Useless Test Flagger, "Is this test useless?" |
| Absolute fine-grained scores | Weak | Heat-map level agreement 47 to 63%; absolute scores bunch in the middle | Contract Heat Map, Jev Arcade and checkers |
| Subtle patterns (recall) | Weak | Comment remover recall 12%; some comment rules 0% | Useless Comment Remover, Comment hygiene linter |
| Two-hop cross-references | Weak | Picked the general 60 days over the applicable 120 at 0.86; full-doc context helped | Jev test battery, Contract risk simulator |
| World knowledge and trivia | Weak | Missed "Nike" = victory; band trivia 57% vs Claude 93% | Generate-then-verify names, Jev Arcade and checkers |
| Near-synonym labels | Weak | Severability vs Enforceability at 1.00 confidence | Legal benchmark sweep, Document type and status bench |
| Criteria about files or tool output | Weak | 59% vs 96% for LLM judges | Jev as an eval judge |
| Security judgments | Weak | Caught 28 to 40% of security-path files | PR stamper |
| Many similar items in one array | Handle with care | Answers swap between rows: 72% vs 96% one per request | Arrays vs one item per request, Contract Heat Map |
| Untrusted or misleading text | Handle with care | Boilerplate caused false pages; planted notes flipped answers. A side injection yes/no caught it at 0.98. | jev-pager, De-id: Jev first, then a model, Jev Inbox Triage, Jev test battery |
| Counting, dates, math, phonology, writing | Not for Jev | Weekday of a date 20%; counts off by one; rhymes read by spelling. Do it in code. | Jev Arcade and checkers, Jev test battery, Jev plays Breakout |

## 16 reusable patterns

### Question shapes

**1. Yes/no gate** — One narrow question, one threshold.

- Flow: [I/O] Input → [Jev] Yes/no → [code] Threshold from data → [I/O] Act or skip
- Tip: Josh passes below 0.25; the guardrail flags at 0.4 because attacks scored 0.39 to 0.49.
- Seen in: CI false-alarm clearer, Prompt-injection guardrail, ToS Trap Spotter

**2. Checklist of narrow yes/nos** — Break a fuzzy judgment into concrete patterns mined from history.

- Flow: [I/O] Item → [Jev] 8 to 10 pattern yes/nos → [code] Per-pattern thresholds → [I/O] Decision
- Tip: One broad question was a coin flip (AUC 0.54). But for a clean single category (document status) one described pick beat splitting.
- Seen in: ToS Trap Spotter, Useless Test Flagger, Useless Comment Remover, Comment hygiene linter, Jev Playbook classifier

**3. Pick from a catalog + none** — Routing: which skill, bucket, alert family, card layout, agent.

- Flow: [I/O] Input + catalog → [Jev] Pick one or none → [code] Top beats none? → [I/O] Route or suggest
- Tip: Describe every option; missing descriptions caused the misses. Max 255 options.
- Seen in: Jev Skill Match, jev-pager, Jev Inbox Triage, Generative Tool Cards, Agent routing drop-in, Document type and status bench

**4. Code finds candidates, Jev picks** — Extraction as a choice: Jev cannot write, so code proposes.

- Flow: [code] Regex finds candidates → [Jev] Pick + none + present? → [code] Normalize value
- Tip: No escape option: wrong at 0.92. With none_of_these: right at 1.00. Merge duplicate candidates first.
- Seen in: Jev test battery, Jev Inbox Triage, Jev as an eval judge, Generative Tool Cards

**5. Fan out, don't index arrays** — One item per request in parallel, or keyed fields if they must share a call.

- Flow: [code] Split items → [Jev] Item 1 / [Jev] Item 2 / [Jev] Item N → [code] Collect
- Tip: Primes 72% in an array, 88% keyed, 96% one per request, at the same cost and speed.
- Seen in: Arrays vs one item per request, Citation verifier, CI false-alarm clearer

### Composition

**6. Confidence bands** — Confident no, confident yes, unsure middle goes elsewhere.

- Flow: [Jev] Probability → [code] Low: no / [LLM] Middle: stronger model / [code] High: yes
- Tip: Make the bands asymmetric when one mistake costs more (Dan: 0.40 / 0.70).
- Seen in: Relationship detection gate, Same buyer? checker, De-id: Jev first, then a model, Entity matcher swap, Legal benchmark sweep, Document type and status bench

**7. Jev screens, LLM finishes** — Jev drops most traffic cheaply; an LLM handles the rest.

- Flow: [Jev] Screen everything → [code] Drop ~90% → [LLM] LLM confirms or writes → [I/O] Result
- Tip: Screen with a low threshold: Jev alone was precise but missed 10 of 11 real preferences.
- Seen in: Preference Memory, Make This a Skill, Jev Playbook classifier

**8. LLM writes the Jev question** — An LLM turns a messy request into a typed question.

- Flow: [LLM] Plan the question → [Jev] Decide + basis? → [code] No basis: say so → [I/O] Answer
- Tip: Rare. Add a "is there any real basis?" question, and test generated questions on labeled data.
- Seen in: Caesar decider bot, Jev Playbook classifier, Jev Arcade and checkers, "Is this test useless?"

**9. Classify first, then decide** — Ask what kind of thing it is, then the decision with that in context.

- Flow: [Jev] What kind is it? → [code] Add its meaning to state → [Jev] Decide
- Tip: Fixed jev-pager's false pages completely.
- Seen in: jev-pager, Jev Playbook classifier, Relationships by doc comparison, Contract Heat Map

**10. Profile → policy file** — Several typed answers, one readable file decides the action.

- Flow: [Jev] 5 to 9 typed answers → [code] policy.ts → [I/O] Bucket, approve, or page
- Tip: Pin the model and hash the questions so tuned thresholds break loudly (Rin).
- Seen in: Jev Inbox Triage, PR stamper, jev-pager, Make This a Skill

**11. Hand Jev the computed fact** — Code does the math; Jev makes the judgment on top.

- Flow: [code] Compute (landing x, CPU, dates) → [Jev] Decide → [code] Act
- Tip: Breakout reflex 17 → 29 bricks/min once code supplied the landing point.
- Seen in: Jev plays Breakout, jev-pager, Jev Inbox Triage

**12. Probe → decide → verify** — A chain of cheap calls where a verifier can veto.

- Flow: [Jev] Probe → [Jev] Decide → [Jev] Verify → [code] Any no: reject
- Tip: Don't mark anything high confidence until a threshold is calibrated.
- Seen in: Relationships by doc comparison, Jev Playbook classifier

**13. Generate, then verify** — An LLM proposes, Jev checks, failures go back.

- Flow: [LLM] Propose → [Jev] Check → [code] Fail? retry ≤ 3 → [I/O] Accepted
- Tip: Code owns state, counts, and the stop condition.
- Seen in: Generate-then-verify names, De-id: Jev first, then a model

### Placement

**14. Check while streaming** — Fire a check as each piece of the answer completes.

- Flow: [LLM] Model streams claims → [Jev] Check each as it closes → [code] Badge → [Jev] Re-check weak
- Tip: Cap the wait after the stream ends (8 s).
- Seen in: Streaming citation validator, Jev Skill Match

**15. Guard inside the agent loop** — Judge each tool call before it runs.

- Flow: [LLM] Tool call → [Jev] Suspicious? → [code] needsApproval or block → [I/O] Run or stop
- Tip: Separate trusted from untrusted text in the state: executed attacks 6 → 0.
- Seen in: Prompt-injection guardrail, Agent-loop signals (design)

**16. Send shape, not values** — Give Jev structure, not customer data, when that is enough.

- Flow: [code] Strip values → [Jev] Decide from shape → [code] Cache per shape
- Tip: Privacy and caching for free.
- Seen in: Generative Tool Cards, Useless Comment Remover, Useless Test Flagger

## All projects

Status: `worked` = Worked, `mixed` = Mixed, `struggled` = Struggled, `idea` = Design, `fun` = Fun, `unknown` = In progress.

### ToS Trap Spotter — Worked

Chrome extension that lights up trap clauses on any terms page. Headline: 89% F1 vs 57% regex.

- Flow: [Jev] Is it a terms page? → [Jev] 8 trap yes/nos per paragraph → [code] red ≥ 0.85, amber ≥ 0.6 → [I/O] Highlight clauses
- State: `{ section_heading, paragraph }`
- Questions: `forced_arbitration ... (8)` (yes/no): `paragraph` requires disputes to go to arbitration instead of court.
- Results: Held-out F1 89% vs regex 57%; 19 of 20 red highlights right on 11 real sites; ~85 ms per paragraph
- Lesson: Narrowing "liability waiver" to "harm the user suffers" halved false hits. Cookie banners caused every data-sharing hit, so dialogs are skipped.

### Contract Heat Map — Mixed

Colors each contract sentence by one-sidedness, or against the playbook Jev picks. Headline: 101 sentences, 1.2 s, $0.0014.

- Flow: [code] Batch 20 sentences → [Jev] 8 questions per sentence → [code] Offset level, trap rules → [I/O] Paint the editor
- State: `{ perspective, sentences: [20] }`
- Questions: `s{i}_one_sided` (score (5)): How balanced is this sentence for the reader?; `s{i}_trap ... (6)` (yes/no); `playbook` (pick + none): Which playbook fits?
- Results: Playbook pick 7 of 7; Level agreement 47% → 63%, trap recall 33% → 51%; Match accuracy 83% at 5 sentences per call, 60% at 40
- Lesson: Fewer items per call for pick-from-list questions. "Sentences" beat "units" by 5 points. Jev scored half a level harsh.

### Make This a Skill — Worked

Notices a repeated task and offers to save it as a skill. Headline: P/R 0.92 / 0.92 held-out.

- Flow: [Jev] Same task? x20 chats + gates → [code] Count ≥ 2, vetoes first → [I/O] Offer card → [LLM] Skill Creator writes it
- State: `{ current_prompt, earlier_chats: [{title, summary} x20], existing_skills }`
- Questions: `same_task_{i}` (yes/no): Chat i did the same kind of task. Ignore parties, amounts, dates.; `procedure_depth` (score (4))
- Results: ~300 ms, $0.00008 per check; Precision 0.92, recall 0.92 held-out
- Lesson: Jev never counts; code does. A tuned threshold overfit, so defaults stayed.

### Preference Memory — Worked

Spots "from now on, always..." and offers to save it to custom instructions. Headline: 11.5x cheaper than Sonnet alone.

- Flow: [Jev] Preference? per sentence → [code] < 0.3 drop (92%) → [LLM] Sonnet confirms, extracts → [I/O] Save chip
- State: `{ sentences: [≤ 6] }`
- Questions: `pref_{i}` (yes/no): The user says how to respond, and it should hold beyond this reply.
- Results: 92% precision, 71% recall; Only 1 in 13 messages reaches Sonnet
- Lesson: Jev alone found 1 of 11 real preferences: a cheap screen, not a final judge. Choice ties failed calls, so it uses yes/no only.

### Generative Tool Cards — Worked

Jev picks the card layout from a tool result's field names, never its values. Headline: Right card 17% → 70%.

- Flow: [code] Strip values, keep shape → [Jev] Pick layout and fields → [code] Validate, cache per shape → [I/O] Render card
- State: `{ tool_name, shape: { fields: [...] } }`
- Questions: `component` (pick (6)): list, table, key facts...; `title / emphasis` (pick over field names)
- Results: Right card 17% → 70%, title 22% → 89%; 2,236 lines of hand-built cards deleted
- Lesson: Send shape, not values: privacy and caching for free.

### Useless Test Flagger — Struggled

Flags tests that only copy a constant. Self-labeled FAILED: too few caught. Headline: Broad question AUC 0.54.

- Flow: [Jev] 9 pattern yes/nos per test → [code] Count mocks, combine → [person] PR comment, person decides
- State: `{ file_path, file_setup, test_code }`
- Questions: `constant_mirror ... (9)` (yes/no)
- Results: One broad "useless?" question: AUC 0.54; Narrow questions + code count: 0.72; 4 of 5 held-out flags right
- Lesson: Broad questions are a coin flip. Reviewers caught 298 duplicate tests leaking across the split.

### Useless Comment Remover — Mixed

Deletes narrating comments, trained on Dusty's 135 cleanup PRs. Headline: Precision 1.00, recall 0.12.

- Flow: [code] Hard keep rules → [Jev] 10 pattern yes/nos → [code] Per-pattern thresholds → [I/O] Commit removal
- State: `{ file_path, comment, code_before, next_code_line }`
- Questions: `narrates_code ... (8)` (yes/no + examples); `explains_why` (yes/no)
- Results: 205 right removals, 0 wrong held-out; Few-shot examples: false deletions 6 → 0
- Lesson: Per-pattern thresholds beat one global one. Only new comments are judged because answers drift.

### Citation verifier — Worked

Checks each citation chip against its source before it renders. Headline: 0 of 294 good cites hidden.

- Flow: [code] Key cites cite_1..20 → [Jev] Supported? per cite → [code] Hide if unsupported ≥ 0.5 → [I/O] Render chips
- State: `{ userQuestion, citations: { cite_1: {claim, source}, ... } }`
- Questions: `c{i}` (pick): supports / contradicts / silent
- Results: Held-out: 0 of 151 good hidden, 57 of 84 bad hidden; p90 366 ms per message
- Lesson: Key items by name: citations[4] gave a wrong answer, cite_4 fixed it. Cache verdicts to avoid flicker.

### Jev as an eval judge — Worked

Advisory judge in the eval harness, one yes/no per rubric criterion. Headline: 94% agreement, ~1% of cost.

- Flow: [Jev] Meets criterion? + evidence sentence → [code] Pass ≥ 0.5 → [I/O] Advisory score
- State: `{ user_request, response: "S1 ... Sn" }`
- Questions: `c{i}` (yes/no): Does `response` meet this criterion?; `e{i}` (pick S1..Sn + none)
- Results: 94% agreement with the unanimous LLM panel; Legal accuracy 98.7% vs 87.4%; Tool/file criteria 59% vs 96%
- Lesson: Objective criteria yes; holistic or file-based criteria no.

### Caesar decider bot — Worked

Settles a Slack debate: an LLM frames the question, Jev decides. Headline: LLM writes the Jev question.

- Flow: [LLM] Plan question and criteria → [Jev] Decide + "any real basis?" → [code] Basis < 0.5: too close → [I/O] Thumb in Slack
- State: `{ question, thread (≤ 8,000 chars) }`
- Questions: `verdict / winner` (yes/no or pick): written by the LLM planner; `basis` (yes/no): Is there real information, or would any answer be a guess?
- Results: 20/20 debates, 10/10 no-context cases flagged; Planner 2.9 s, Jev 0.2 s
- Lesson: With no context Jev still picked at 0.81 to 0.89. A "basis" question catches it.

### Legal benchmark sweep — Mixed

Jev over LegalBench, CUAD, and LEDGAR, plus batching tests. Headline: 92% right when confident.

- Flow: [code] Key 1 to 80 clauses → [Jev] Classify each → [code] ≥ 0.8 keep / [LLM] Else Opus
- State: `{ clauses: { clause_01 ... clause_80 } }`
- Questions: `q_clause_NN` (pick or yes/no)
- Results: 79% overall, 92% at ≥ 0.8 (72% of items); vs Opus on 55 hard items: 64% vs 80%; with fallback 78% at half cost; 80 keyed clauses per call: accuracy held
- Lesson: Near-synonym labels break it. Spelling out the rule took CUAD from 65% to 90%.

### Generate-then-verify names — Mixed

De-id loop: an LLM proposes names, Jev checks, failures retry. Headline: Echo recall 80% vs Sonnet 97%.

- Flow: [LLM] Invent replacement names → [Jev] Echoes original? realistic? → [code] Reject if echo → 0.3 → [LLM] Regenerate (≤ 3 rounds)
- State: `{ pairs: [{real, invented} x20] }`
- Questions: `echo_{i}` (yes/no); `realistic_{i}` (yes/no)
- Results: Semantic echoes: Jev 16/20, code 0/20, Sonnet 19/20; 34x faster than Sonnet
- Lesson: World knowledge is the gap: missed "Nike" → "Victoria Sportswear".

### Agent plan verifier — Worked

Checks a draft answer against plan rules. Headline: 92%, tied gpt-5-mini.

- Flow: [Jev] 3 plan checks per draft → [code] ≥ 0.8 keep / [person] Else review
- State: `{ ask, draft }`
- Questions: `J1 ... (3)` (yes/no): needs a "not applicable" option
- Results: 92% vs gpt-5-mini 92%; gpt-5-mini's 7 errors were all at ≥ 0.85 confidence
- Lesson: Jev's confidence can drive routing; the LLM's self-reported confidence could not.

### Entity matcher swap — Worked

Replace an existing LLM party-matching call with Jev plus fallback. Headline: 95% with fallback vs 93%.

- Flow: [Jev] Pick match (+ none) → [code] ≥ 0.8 keep / [LLM] Else existing LLM
- State: `{ name, candidates }`
- Questions: `match` (pick + none)
- Results: Jev 90%, existing LLM 93%, Jev + fallback 95%; $0.019 vs $0.51 per 1,000
- Lesson: Misses former company names. No confident answer was wrong.

### Agent-loop signals (design) — Design

A shared way to inject Jev results, dates, and token budgets into the agent loop. Headline: Design only.

- Flow: [Jev] Classifier produces a signal → [code] Note, approve, or block → [LLM] Model reads tagged note
- State: `registry: { trigger, produce(ctx), decide(result) }`
- Questions: `(any classifier)` (yes/no)
- Results: Cache rules: append, never mutate; inject only on change
- Lesson: The plan for putting more Jev inside the loop without breaking prompt caching.

### Jev Skill Match — Worked

Suggests the right skill as you type. Headline: 21/21, 8x faster than gpt-5-mini.

- Flow: [code] Debounce typing 600 ms → [Jev] Pick skill + "concrete task?" → [code] Beats none? max 2 pills → [I/O] Show pill
- State: `{ userDraft } + all skills as options (≤ 254)`
- Questions: `skill` (pick + none): Judge by the task, not shared words.; `concrete` (yes/no)
- Results: 21/21 vs 20/21; 221 ms vs 1,896 ms; 102 real skills: button right 96%, 0 wrong pills; Right skill lifts answers 34% → 75%
- Lesson: Misses were "no pill", not wrong pills. Skills without descriptions caused them.

### Jev Inbox Triage — Worked

Sorts a lawyer's inbox into Act now, This week, FYI, Needs a look. Headline: 26/26 vs Sonnet 25/26.

- Flow: [code] Regex finds date phrases → [Jev] 9 questions per email → [code] Policy file + runner-up check → [I/O] Inbox bucket
- State: `{ email, recipient } + candidate date phrases`
- Questions: `is_legal, needs_action, injection` (yes/no); `urgency` (score (0 to 3)); `deadline_pick` (pick over found phrases + none)
- Results: 26/26 buckets vs Sonnet 4.6 25/26; 7x faster, 16x cheaper
- Lesson: Code finds date candidates, Jev picks. The injection question must win.

### jev-pager — Worked

Reads every alert and pages the on-call only when a person is needed. Headline: 11/11 incidents paged, 1 false page.

- Flow: [code] Compute facts, strip boilerplate → [Jev] Which alert family? → [Jev] Page now? (family in state) → [I/O] Page on-call
- State: `{ cause, service, pinned_minutes, in_known_noisy_window, other_open_alerts }`
- Questions: `family` (pick + unknown): stage 1; `page_now` (yes/no): stage 2
- Results: Family 133/136, page precision 0.92, recall 1.00; 49-alert day → 1 page
- Lesson: Jev believes what it reads: template text caused false pages until it asked family first. Code-known facts raised precision 0.63 → 0.92.

### Same buyer? checker — Worked

Catches returning buyers that exact-email matching misses. Headline: 95.5% agreement with Opus 5.

- Flow: [code] Generate candidate records → [Jev] Same person? same org? → [code] Recommend / [person] Show a human / [code] Proceed
- State: `{ new_record, candidate }`
- Questions: `same_person` (yes/no): clerical equivalences in criteria; `same_organization` (yes/no)
- Results: 95.5% agreement with Opus 5; $0.00011 vs $0.0073 per probe; Past duplicate incidents replay as "recommend"
- Lesson: Two narrow questions beat one. Every veto and threshold stays in code.

### Comment hygiene linter — Mixed

Checks comments against our comment guidelines at edit time. Headline: Whole codebase ~$2.60.

- Flow: [Jev] 7 checks per comment, all in 1 call → [code] Flag → 0.7 → [person] Advisory note
- State: `{ blocks: [{comment, code}] }`
- Questions: `narratesChange ... (6)` (yes/no); `length` (score (4))
- Results: Precision 79%, recall 33%; Some rules 71 to 93% recall, some 0%; 26 ms per block vs 1,247 ms for Opus
- Lesson: An anti-injection line in the question did not hold against a planted comment.

### PR stamper — Worked

Auto-approves low-risk PRs labeled "stamp". Headline: Historical backtest, 0 bad approvals.

- Flow: [code] Coded gates first → [Jev] 7 questions per changed file → [code] Every file passes every bar → [person] Approve, never merge
- State: `{ pr, file, diff (≤ 48k chars), rules }`
- Questions: `change_kind` (pick (8)); `touches_security_surface ...` (yes/no): author text is untrusted; `blast_radius` (score (4))
- Results: 96 historical approvals, all hand-checked OK; Security question caught 28 to 40%, so security stays a coded gate
- Lesson: Pin the model and hash the questions so tuned thresholds break loudly.

### CI false-alarm clearer — Worked

Clears false alarms from a noisy security-pattern CI check. Headline: Real 95 to 98%, tests 4 to 16%.

- Flow: [code] Flag risky call sites → [Jev] Real risky query? per file → [code] All < 0.25: pass / [person] Else reviewer
- State: `{ path, diff + enclosing function }`
- Questions: `adds_risky_query` (yes/no): Ignore comments arguing it is safe.
- Results: Old check: only 8 of 30 sampled alarms were real
- Lesson: Judge each file separately: one call over all files pulled scores together.

### Jev Playbook classifier — Mixed

Word playbook verdicts in seconds instead of minutes. Headline: 73 of 80 checks, ~10x faster.

- Flow: [LLM] Rewrite checks as literal lines (once) → [Jev] Which sections are relevant? → [Jev] Each condition true? → [code] Pass / Fallback / Flag / [LLM] < 0.6: full LLM
- State: `{ check, representing, relevantExcerpts }`
- Questions: `standard__1 ...` (yes/no): "Required: Customer may terminate for convenience."
- Results: 80 verdicts in 17 s vs 20 to 35 s per check; 55/80 agree with the LLM (LLM self-agreement 73 to 79%)
- Lesson: Checks had to be rewritten for Jev: as-is guidance scored 41/80.

### Streaming citation validator — Worked

Checks each cited claim against all its sources while the answer streams. Headline: 0 false "supported" in 25 claims.

- Flow: [LLM] Answer streams <claim → tags → [Jev] Check each claim as it closes → [code] High / medium / low badge → [Jev] Re-check weak claims
- State: `{ cited_statement, sources: [≤ 8] }`
- Questions: `relation` (pick (5)): supports ... contradicts; `overstates` (yes/no): "may" became "must"?
- Results: No false "high" in a 32-case test; 200 to 470 ms per call
- Lesson: One verdict missed "may" → "must"; three extra yes/nos fixed it. Judge a claim against all sources together.

### Prompt-injection guardrail — Mixed

Judges every tool call inside the agent loop for data exfiltration. Headline: All 11 exfiltration calls stopped.

- Flow: [LLM] Model calls a tool → [Jev] Suspicious call? → [code] ≥ 0.4: ask approval or block → [I/O] Run or stop
- State: `{ userRequest, untrustedPasted, untrustedToolResults, toolCall }`
- Questions: `suspicious` (yes/no): Contacts a host the untrusted text introduced, or sends private data?
- Results: GPT-5.5: 122 → 135 of 160 evals; 0 of 63 Claude calls flagged; ~200 ms per tool call
- Lesson: Separating the user's ask from pasted text cut executed attacks 6 → 0. The Skill tool caused false positives.

### Relationship detection gate — Worked

Jev takes clear relationship calls; unsure pairs go to Flash. Headline: Same accuracy, 43% cheaper.

- Flow: [code] SQL finds candidate pairs → [Jev] P(related) → [code] < 0.40: no / [LLM] 0.40 to 0.70: Flash / [code]  → 0.70: yes
- State: `{ policy, source: {excerpt 5k}, candidate }`
- Questions: `relationship_exists` (yes/no); `classification` (pick (17))
- Results: Flash 91.9%, Jev alone 84.6%, gated 91.9%; Jev handled 86% of pairs; 63% fewer Flash calls
- Lesson: False "yes" was the weakness, so the yes bar is stricter: asymmetric bands.

### Relationships by doc comparison — Mixed

Compares document passages, decides, then verifies, in PR previews. Headline: 51/51 fictional; speedup unmeasured.

- Flow: [code] Cut docs into windows → [Jev] Probe window pairs → [Jev] Decide relationship → [Jev] Verify (any no vetoes)
- State: `{ window pairs (1,400 chars) } then { top evidence, operative clauses }`
- Questions: `pair_1..4` (pick): none / possible; `exact_identity` (pick): yes / no / unclear
- Results: 51/51 fictional judgments; Up to 7 calls per pair
- Lesson: A chain with a veto step. Nothing marked high confidence until calibrated.

### De-id: Jev first, then a model — Worked

Benchmark de-identification: rules, then Jev, then a model. Headline: Jev 97% vs Opus 88%.

- Flow: [code] Code rules first → [Jev] Identity, fact, or noise? → [code] ≥ 0.9 keep / [LLM] Else Sol
- State: `{ value, detectedAs, snippets, whoIsWho }`
- Questions: `identifies` (pick): identity / fact / noise
- Results: Agreement with Sol 14/14 at 0.95; Routing: code 93, Jev 222, model 843
- Lesson: Planted text flipped 2 of 5 answers, but below the bar, so the fallback caught them.

### Entity resolution POC — In progress

Match companies, customers, and orgs across data sources. Headline: In progress.

- Flow: [Jev] Match probability → [code] Confident: merge / [LLM] Escalate: Sonnet / [person] Unsure: review queue
- State: `{ record_a, record_b }`
- Questions: `same_entity` (yes/no)
- Results: No numbers yet
- Lesson: Same shape as the same-buyer checker.

### Agent routing drop-in — Worked

Jev swapped in for the agent-routing classifier. Headline: "Identical results, much cheaper".

- Flow: [I/O] User request → [Jev] Which agent? → [I/O] Route
- State: `{ request }`
- Questions: `route` (pick)
- Results: Same decisions, much faster and cheaper
- Lesson: Routing over a fixed set is the most natural fit.

### Jeventus Slack pet — Fun

A sloth in Slack whose stats change by message category. Headline: Jev as a switch statement.

- Flow: [I/O] Message tags the pet → [Jev] Which category? → [code] Update hunger, mood → [I/O] Pet replies
- State: `{ message }`
- Questions: `category` (pick)
- Results: No metrics
- Lesson: A typed switch statement for a game.

### "Is this test useless?" — Struggled

AI-generated questions over tests gave no useful signal. Headline: No signal.

- Flow: [LLM] AI writes the questions → [Jev] Jev answers → [I/O] No signal
- State: `{ test_code }`
- Questions: `(AI-written)` (yes/no)
- Results: Broad questions on mock-heavy tests: coin flip
- Lesson: Write narrow questions by hand; check on labeled items first.

### Jev test battery — Worked

Clause types, extraction, verification, injection, long context, languages, calibration. Headline: 9/9 fields in one 0.34 s call.

- Flow: [code] Regex finds candidates → [Jev] Pick one (+ none) + "present?" → [code] Normalize value
- State: `GitHub ToS (12k tokens) or a contract`
- Questions: `field` (pick over regex candidates + none_of_these); `present` (yes/no): Is the field in the document at all?
- Results: Clause types 11/11, verification 6/6, extraction 14/14 on GitHub ToS; Needle at 30k tokens of boilerplate: still found; Same results in ES, DE, FR, JA; Injection did not move the answer; a side yes/no flagged it at 0.98
- Lesson: With no escape option it picked a wrong date at 0.92; adding none_of_these fixed it. Two-hop cross-references were confidently wrong (0.86). Counting was off by one; per-item yes/nos summed in code were exact.

### Arrays vs one item per request — Worked

Jev loses its place when many similar items sit in one array. Headline: 72% → 96% by fanning out.

- Flow: [code] Fan out: 1 item per request → [Jev] Judge each item → [code] Collect (199 requests in 1.3 s)
- State: `{ number } per request (vs numbers[0..49] in one)`
- Questions: `is_prime / is_spam` (yes/no)
- Results: Primes: array 72%, keyed fields 88%, one per request 96%; SMS spam: 62% batched → 100% one per request; Rhymes stayed 58% in every layout: a real limit
- Lesson: Many questions about one item: free. Many similar items in one array: answers swap between rows. Fan out, or use keyed fields.

### Contract risk simulator — Worked

Every sentence colored by risk for our side, with the full contract as context. Headline: Top 6 sentences all planted risks.

- Flow: [I/O] Whole contract + perspective as state → [Jev] Risk score, driver, "protects us?" per sentence → [code] Outline ≥ 1.8, tint red / green → [I/O] Colored contract
- State: `{ contract (full), perspective, sentence }`
- Questions: `risk` (score (4)); `driver` (pick); `protects_us` (yes/no)
- Results: 91 sentences, $0.018, ~1 s; 8 of top 10 were planted risks; Caught a buried cross-reference that swallowed the liability cap
- Lesson: Full-document context is the lever: it fixed the two-hop failure and anchored scores against standard sentences.

### Document type and status bench — Worked

Document type and status on a 25k-document eval corpus. Headline: 87% type, 88% status, $0.0001/doc.

- Flow: [I/O] Whole document as state → [Jev] Type (17) or status (5) → [code] Confidence ≥ 0.7: keep / [LLM] Else second opinion
- State: `{ document (full) }`
- Questions: `doc_type` (pick (17, described)); `status` (pick (5)): Draft / Unsigned / Partially / Executed / n/a
- Results: Type 87% (Opus 93%), right type in top 2: 99%; Status 88% holistic vs 82% split into yes/nos; 119 documents per second; 113x cheaper than Opus
- Lesson: Misses sit on soft boundaries (contract vs MSA). A clean single category beat decomposing into yes/nos here.

### Jev plays Breakout — Mixed

Code only vs Jev strategy vs Jev reflex, same rules. Headline: Strategy 39 vs code 24 bricks/min.

- Flow: [code] Physics: predict landing x → [Jev] Pick target, aggression, chase → [code] Move paddle
- State: `{ ball, paddle, bricks, predicted_landing_x }`
- Questions: `target_column` (pick); `aggression` (score)
- Results: Jev strategy 39 bricks/min vs code 24; Jev reflex from raw state 17, lost 10 balls; Reflex with code's landing x: 29
- Lesson: Slowing the game did not help; giving Jev the computed fact did. The state must be true about the world.

### Jev Arcade and checkers — Fun

Party games and graded checkers: alignment charts, Codenames, time, rhymes, trivia. Headline: Movie guess 46/50 over 253 titles.

- Flow: [LLM] Claude writes premise or fakes → [Jev] Score or pick per item → [code] Stretch axes, grade vs truth
- State: `{ items or clue }`
- Questions: `axis_x / axis_y` (score); `movie` (pick (253))
- Results: Codenames: 415 clues fanned out in 7 s for $0.05; Weekday of a date 20%, rhymes by spelling not sound; Band trivia 57% vs Claude 93%; SMS spam 100%
- Lesson: Absolute scores bunch in the middle; relative ranking works. Not a trivia store.
