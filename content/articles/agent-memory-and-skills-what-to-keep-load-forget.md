Title:  Agent Memory and Skills: What to Keep, What to Load, What to Forget
Date: 2026-09-24
Category: AI Agents
Tags: ai-agents, agent-memory, skill
Slug: cagent-memory-and-skills-what-to-keep-load-forget
Authors: Sijan Bhandari
Summary: How agent memory and skills differ, why progressive disclosure saves context, and when to prune skills without losing rare but valuable routines.

An agent that runs ten unrelated jobs forgets nine of them. That's the gap memory systems exist to close. Context compaction keeps one task from drowning in its own history. Memory and skills carry useful knowledge from one task to the next. The hard part is deciding what to keep, how to pull it back, and how much detail to load. This post covers the split between memories and skills, how layered loading actually works, and how to stop a skill library from turning into dead weight.

## Memories and skills store different kinds of knowledge

A memory records a fact, a past event, or a detail about an environment. My standing example: "This store requires an authentication token in request headers."

A skill captures a reusable way of doing something. Procedures. "Search for a product, compare options, verify the result."

Memory is a note on the doorframe: "The front door sticks." A skill is the routine for getting through it: turn the handle, lift the door slightly, push.

This split matters because the two kinds of knowledge age differently. A fact about one website or one account goes stale. A general procedure, like checking filters before scanning results, travels well across sites.

**Practical takeaway:** Keep durable facts as memories. Keep repeatable methods as skills. If a skill leans on an interface that changes, say so inside the skill instead of treating that dependency as permanent.

Skills come in two flavors, and the papers behind this label them clearly. Textual skills show up in AWM ([Agent Workflow Memory](https://arxiv.org/abs/2409.07429)) and ReasoningBank ([ReasoningBank, ICLR 2026](https://proceedings.iclr.cc/paper_files/paper/2026/hash/980ea04d23d1f6908964eba2a74afe45-Abstract-Conference.html)), which distills reasoning strategies from both successful and failed rollouts. Code skills show up in Voyager ([Voyager](https://arxiv.org/abs/2305.16291)), ASI ([Inducing Programmatic Skills for Agentic Tasks](https://arxiv.org/abs/2504.06821)), and PolySkill ([PolySkill, ICLR 2026](https://proceedings.iclr.cc/paper_files/paper/2026/hash/e350897ed832f9cad6f2e223e7acad6d-Abstract-Conference.html)). Those papers carry far more implementation detail than this post does, so don't read more into the labels than they say.

## Load detail in layers instead of all at once

Packing every skill into the active instructions crowds the context window. Costs go up. The model gets distracted. Progressive disclosure fixes this by loading information in tiers.

| Tier | What the agent gets | Plain version |
|---|---|---|
| 1. Metadata index | A small YAML header with a skill's name and trigger description | A table of contents |
| 2. Skill instructions | The `SKILL.md` body, once the skill looks relevant | The how-to guide |
| 3. Supporting assets | Scripts, assets, and reference files, fetched on demand | Tools and supplies |

The [agentskills.io specification](https://agentskills.io/specification) formalizes exactly this split. Only a name and description, roughly 100 tokens, load at startup. The full `SKILL.md` body comes in when the skill activates, with the spec recommending the body stay under about 5,000 tokens. Files under `scripts/`, `references/`, or `assets/` get read only when a step needs them.

Hermes documents the same idea as an explicit three-step sequence: `skills_list()` returns names, descriptions, and categories for about 3k tokens, `skill_view(name)` pulls full content, and `skill_view(name, path)` grabs one reference file ([NousResearch Hermes Agent](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/skills.md)). OpenHands points developers at the same AgentSkills `SKILL.md` format, where the agent sees a summary and reads the full content on demand ([OpenHands docs](https://docs.openhands.dev/sdk/guides/skill)). A source-code study of eleven coding agents describes the identical chain of an index in the prompt, a `skill_view` call, then linked assets ([a source-code study of eleven coding agents](https://arxiv.org/html/2609.00006v1), July 2026).

Think about a repair manual. You don't lay the whole thing open on the bench. You check the index, flip to the relevant repair, and grab one tool when the procedure asks for it.

The cost side has a concrete number. A budget-constrained study of web agents found that adding skill and memory modules isn't automatically worth the extra tokens ([Are Online Skill and Memory Modules Always Worth Their Tokens?](https://arxiv.org/pdf/2606.15017)). Against a budget-matched actor, the plain baseline matched or beat all three augmentation methods in aggregate success rate across four WebArena domains.

**Practical takeaway:** Keep the index tight and the descriptions sharp enough that the agent picks the right entry. Layers cut clutter. They don't guarantee a good choice. A vague trigger still loads the wrong skill.

## Text skills and code skills trade flexibility for speed

Induced skills can be written as natural-language procedures or as runnable code. Neither wins everywhere. Each fits different conditions.

| Dimension | Textual (AWM, ReasoningBank) | Code (Voyager, ASI, PolySkill) |
|---|---|---|
| Execution style | Natural-language steps | Python or Bash functions exposed as tools |
| Adaptability | Higher; the model reinterprets when an interface shifts slightly | Lower; hardcoded selectors or API params break on change |
| Step efficiency | Lower; one tool call per sub-step, often | Higher; one function runs many low-level actions |
| Verification | Softer, often LLM-as-a-Judge | Programmatic, via linters and automated unit tests |

A text skill is a checklist handed to a capable colleague. Easy to adjust when things shift. The colleague still does every step. A code skill is the machine that runs the checklist fast and the same way every time. If that machine was built for an old button layout, a small interface change stops it cold.

The numbers back the efficiency claim. ASI beat a static baseline by 23.5% and a text-skill version by 11.3% in success rate on WebArena, cutting 10.7 to 15.3% of steps by composing primitive actions like clicks into higher-level skills. Voyager collected 3.3x more unique items than prior work and unlocked tech-tree milestones up to 15.3x faster in Minecraft.

### How PolySkill reduces code brittleness

PolySkill attacks the breakage directly. It separates a skill's abstract goal, the what, from its concrete implementation, the how, drawing on polymorphism in software engineering. A shared interface defines the operation, and site-specific subclasses implement it for each provider. The paper's own framing: existing methods create skills over-specialized to one website that fail to generalize ([PolySkill, ICLR 2026](https://proceedings.iclr.cc/paper_files/paper/2026/hash/e350897ed832f9cad6f2e223e7acad6d-Abstract-Conference.html)).

The specific class names sometimes cited for this pattern, such as an abstract shopping-site class with per-retailer subclasses, are [UNVERIFIED]. The decoupling idea is what the abstract supports.

In plain language: the agent calls one standard method, and each provider adapter handles the local details. Updating a provider doesn't force you to rewrite every workflow that uses it. It doesn't kill brittleness either. The provider-specific code still needs upkeep when the site changes.

Results land where you'd expect. PolySkill improved skill reuse 1.7x on seen sites, lifted success rates up to 9.4% on Mind2Web and 13.9% on unseen sites, and cut steps by over 20%.

Pick text workflows when interfaces change often or steps need judgment. Pick code workflows when a process repeats a lot, the environment holds still, and speed or consistency matters. A hybrid works too. Code for the reliable operations, natural language for the decisions and exceptions.

## A skill library needs a lifecycle

A skill library grows without a limit if you let it. Then retrieval gets harder and inference slows down. Three maintenance phases show up again and again.

### Check a skill before you store it

Before a newly induced skill enters the library, a judge model or reward verifier runs the candidate workflow or code to see whether it actually succeeds.

Don't add a recipe to the family cookbook just because someone wrote it down. Cook it first.

A trace that looks successful isn't automatically a reliable skill. Testing at admission filters out procedures that only appeared to work.

### Learn from failures

An agent can pull a negative lesson out of a failed attempt. "Don't page through thousands of results. Apply category filters first." Systems built on reasoning memory store structured lessons from successful and failed rollouts, and ReasoningBank retrieves those memories at test time ([ReasoningBank, ICLR 2026](https://proceedings.iclr.cc/paper_files/paper/2026/hash/980ea04d23d1f6908964eba2a74afe45-Abstract-Conference.html)).

A pilot's checklist records the normal procedure and the mistakes worth avoiding. Same idea.

Failures improve future behavior when the system turns them into specific, reusable guidance. A vague note that "the task failed" does nothing.

### Prune the library

TroVE trims skills based on how often they're called relative to the number of tasks solved. Its framing is a toolbox that is generated, grown, and periodically trimmed so the functions stay verifiable and efficient ([TroVE, ICML 2024](https://arxiv.org/abs/2401.12869)). The payoff shows in the numbers: toolboxes 79 to 98% smaller than baselines, with human verification 31% faster and 13% more accurate.

One threshold heuristic from my source material says to drop functions whose running call count falls below roughly **½·log₁₀(K)**, where **K** is the number of tasks solved. Treat that as a paraphrase, not a quoted result. I could confirm the periodic-trimming mechanism in the TroVE paper, but not that exact formula, so the ½·log₁₀(K) figure stays **unconfirmed**.

Clearing out a toolbox every so often keeps the tools you actually reach for and makes you reconsider the rest.

Pruning cuts clutter and raises the odds of retrieving something useful. Frequency measures value only loosely, though. An uncommon emergency procedure can be worth keeping precisely because it's rare.

## Diagnostic exercise

### When would you choose code skills for AWS or GCP consoles, and how would you reduce UI-change brittleness?

I'd lean toward code skills when the console task repeats often, has many predictable low-level steps, and is stable enough to test and maintain. I'd also pick code when the job is costly or error-prone by hand, or when automated checks can confirm the operation completed. I'd pick text skills when the console workflow changes a lot, depends on judgment, or has to absorb interface shifts I can't predict. My source material says nothing about AWS or GCP interfaces specifically, so this is a decision framework, not a claim about either console.

To reduce brittleness, I'd borrow PolySkill's separation of common operation from provider-specific implementation:

1. Define a stable abstract operation, something like "find the target resource" or "apply the requested configuration."
2. Put AWS- and GCP-specific behavior behind separate implementations of that operation.
3. Keep changing UI details out of the shared workflow.
4. Test the provider-specific implementation after interface changes, and feed those checks into admission or maintenance.

The trade-off holds. Code runs faster and tests easier. It still breaks when the interface or API underneath moves. An abstraction limits how far a change spreads. It doesn't make the change vanish.

### Why might 10 retrieved skills perform worse than 1 or 2, and how does consolidation help?

The mechanism I can point to is context distraction. A big pile of retrieved skills adds competing instructions and irrelevant detail to the active context. The agent has to sort out which instructions apply, and the extra material crowds out what matters for the current task. Retrieval hurts when it returns too much or too many weakly relevant skills. The budget-constrained study points the same way: skill and memory modules carry a real token cost that isn't always repaid ([Are Online Skill and Memory Modules Always Worth Their Tokens?](https://arxiv.org/pdf/2606.15017)).

Treat that as a caution. It doesn't prove fewer skills always win. The goal is a small set of well-targeted skills, not an arbitrary cap.

Consolidation helps by shrinking the library and sharpening retrieval, dropping skills that are seldom used and keeping the collection from becoming a growing stack of competing procedures. Frequency-based pruning has a real blind spot here. A rare, high-value skill could get cut just because it's rarely needed. Admission checks, task relevance, and retention of critical procedures have to weigh in beside usage counts.

Two questions stay open for me. Who gets to judge whether a skill is good enough to store? A judge model or reward verifier can help, but my sources don't say how its standards get set or how false successes get caught. And how is relevance measured at retrieval time? A well-maintained library still distracts the agent if it returns the wrong entries. Those aren't small implementation details. They decide whether a memory system makes an agent more capable or just hands it more things to confuse itself with.

---

### FAQ

**Do I need agent memory if I already have agent skills?**
Yes. The two store different things. Memory holds facts and environment details, like a token a site expects in request headers. Skills hold procedures, like the sequence for searching a catalogue and verifying the result. Drop either one and the agent loses half of what it learned.

**How many tokens does a skill index actually cost?**
The [agentskills.io specification](https://agentskills.io/specification) puts the metadata tier at roughly 100 tokens per skill at startup, with the instruction body recommended under about 5,000 tokens once activated. Hermes reports its Level 0 list at around 3k tokens total. That's the whole case for layered loading. You pay for the index, not the full manual.

**When should I write a skill as code instead of text?**
Write code when the task repeats often, the environment is stable enough to test, and you want one function call instead of ten. ASI cut 10.7 to 15.3% of steps by composing clicks into higher-level skills. Keep text when the interface shifts often or a step needs judgment. Code won't reinterpret itself when a selector changes.

**How often should I prune a skill library?**
TroVE-style systems trim periodically rather than on a fixed calendar, watching how often each function gets called relative to tasks solved ([TroVE, ICML 2024](https://arxiv.org/abs/2401.12869)). Check for rarely used skills on a regular cycle. Don't cut on frequency alone, because an uncommon emergency procedure may be the most valuable thing in there.

**Is retrieving more skills always worse for an agent?**
No. Retrieving many weakly relevant skills adds competing instructions and crowds the context, but a small set of well-targeted skills is the point. The problem is relevance and volume together, not retrieval on its own. A budget-constrained study even found the modules' gains often disappear against an agent given the same tokens for more interaction steps ([budget-constrained study](https://arxiv.org/pdf/2606.15017)).
