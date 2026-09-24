Title:  Agent Memory and Skills: What to Keep, What to Load, What to Forget
Date: 2026-09-24
Category: AI Agents
Tags: ai-agents, agent-memory, skill
Slug: cagent-memory-and-skills-what-to-keep-load-forget
Authors: Sijan Bhandari
Summary: How agent memory and skills differ, why progressive disclosure saves context, and when to prune skills without losing rare but valuable routines.

An agent working across many separate tasks needs to remember useful things without carrying its entire history into every new conversation. The key distinction is:

- **Context compaction** helps manage information *within one ongoing task*.
- **Memory and skills** help preserve useful knowledge *between separate tasks*.

A useful analogy: during one project, you keep a tidy workbench; between projects, you keep a filing cabinet. The workbench should hold only what is needed right now. The filing cabinet should store things that are likely to help again.

The hard part is deciding what to keep, how to retrieve it, and how much detail to load.

---

## 1. Memories and skills are different kinds of knowledge

**Memories** record facts, past events, or details about an environment. For example: "This store requires an authentication token in request headers."

**Skills** capture a reusable way of doing something. They are procedures: "Here's how to search for a product, compare options, and verify the result."

Skills may be written by people or learned by an agent from successful past work. In the sources behind this post, **AWM** ([Agent Workflow Memory](https://arxiv.org/abs/2409.07429)) and **ReasoningBank** ([ReasoningBank: Scaling Agent Self-Evolving with Reasoning Memory](https://proceedings.iclr.cc/paper_files/paper/2026/hash/980ea04d23d1f6908964eba2a74afe45-Abstract-Conference.html)) are associated with textual skills, while **Voyager** ([Voyager: An Open-Ended Embodied Agent with Large Language Models](https://arxiv.org/abs/2305.16291)), **ASI** ([Inducing Programmatic Skills for Agentic Tasks](https://arxiv.org/abs/2504.06821)), and **PolySkill** ([PolySkill: Learning Generalizable Skills Through Polymorphic Abstraction for Continual Learning](https://proceedings.iclr.cc/paper_files/paper/2026/hash/e350897ed832f9cad6f2e223e7acad6d-Abstract-Conference.html)) are examples of code skills. Those papers carry far more implementation detail than is summarised here, so it's best not to infer more than the labels above.

A memory is a note saying, "The front door sticks." A skill is the routine for getting inside: "Turn the handle, lift the door slightly, then push."

A fact about one particular website or account may become outdated. A general procedure, such as checking filters before scanning results, may be useful in many settings. Keeping these two kinds of knowledge separate can make it easier to reuse procedures while updating environment-specific details.

**Practical implication:** Store durable facts as memories, and store repeatable methods as skills. If a skill depends on a changing interface, make that dependency explicit rather than treating it as timeless knowledge.

---

## 2. Progressive disclosure: load detail only when it's needed

Loading every skill into an agent's active instructions can crowd the context window. That can raise costs and distract the model from the task at hand. Progressive disclosure addresses this by loading information in layers.

| Level | What the agent gets | Plain-language version |
|---|---|---|
| **1. Metadata index** | A small YAML header with a skill's name and trigger description | A table of contents |
| **2. Skill instructions** | The `SKILL.md` body, loaded when the skill appears relevant | The recipe or how-to guide |
| **3. Supporting assets** | Scripts, assets, and reference files, used when needed | Tools and supplies for carrying out the recipe |

The [agent-skills specification](https://agentskills.io/specification) formalises exactly this split: only a name and description (roughly 100 tokens) are loaded at startup, the full `SKILL.md` body is pulled in when the skill is activated, and files under `scripts/`, `references/`, or `assets/` are read on demand. **Hermes** documents the same pattern as an explicit three-step loading sequence via `skills_list()` and `skill_view(name)`, then `skill_view(name, path)` for a specific reference file ([NousResearch Hermes Agent](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/skills.md)). **OpenHands** points developers at the same AgentSkills `SKILL.md` format for progressive disclosure ([OpenHands docs](https://docs.openhands.dev/sdk/guides/skill)), and a source-code study of coding agents describes the identical "index in prompt, then `skill_view`, then linked assets" chain ([Harness Engineering](https://arxiv.org/html/2609.00006v1)).

Think of a repair manual. You don't carry the whole manual open on your workbench. You look at the index, open the relevant instructions for the repair, and fetch a specific tool only when the procedure calls for it.

The agent can discover what skills exist without paying the attention cost of reading every full instruction. It can then load the detailed workflow, and any scripts or references, only when they are relevant. One budget-constrained study of web agents makes the cost side concrete: adding skill and memory modules is not automatically worth the extra tokens ([Are Online Skill and Memory Modules Always Worth Their Tokens?](https://arxiv.org/pdf/2606.15017)).

**Practical implication:** Keep the initial index compact and the skill descriptions clear enough to help the agent choose the right one. Progressive disclosure reduces clutter, but it does not guarantee a good choice. Poor triggers can still cause the wrong skill to be loaded.

---

## 3. Text skills and code skills: flexibility versus speed

Induced skills can be represented as natural-language procedures or executable code. The trade-off here is not a simple ranking; the two representations are useful under different conditions.

| Dimension | Textual skills (e.g., AWM, ReasoningBank) | Code skills (e.g., Voyager, ASI, PolySkill) |
|---|---|---|
| **Execution style** | Natural-language instructions and step-by-step guidance | Python or Bash functions exposed as callable tools |
| **Adaptability** | Higher: the model can interpret instructions flexibly when a site's interface changes slightly | Lower or more brittle: hardcoded selectors or API parameters can break when they change |
| **Step efficiency** | Lower: the agent may need to make separate tool calls for each sub-step | Higher: one function can perform many low-level actions |
| **Verification** | Often assessed through softer LLM-as-a-Judge checks | Can be checked programmatically with linters and automated unit tests |

A **text skill** is like giving a capable colleague a checklist: it is easy to adapt when circumstances shift, but the colleague still has to perform each step.

A **code skill** is like a machine that carries out the checklist quickly and consistently. But if the machine relies on an old button layout, a small interface change can stop it.

### PolySkill's proposed mitigation

PolySkill addresses code brittleness through an abstract base-class schema. For example, a shared interface such as `AbstractShoppingSite.search_product()` defines the operation that a shopping site implementation should provide. Site-specific subclasses, such as `AmazonWebsite` and `TargetWebsite`, then implement that operation for each site. The PolySkill paper frames the failure it targets in similar terms: code skills work well on the original website but break when the interface shifts ([PolySkill, ICLR 2026](https://proceedings.iclr.cc/paper_files/paper/2026/hash/e350897ed832f9cad6f2e223e7acad6d-Abstract-Conference.html)).

In plain language: the agent calls a standard-purpose method, while each provider-specific adapter handles the local details. That can make it easier to update a provider's implementation without changing every workflow that uses it. It does not eliminate brittleness; the site-specific implementation still needs maintenance when the site changes.

Text workflows can be a better fit when interfaces change often or when the steps need interpretation. Code workflows can be a better fit when the process is repeated frequently, the environment is stable enough, and speed or consistent execution matters.

A useful rule of thumb is: **automate stable, repeated actions; keep changing or ambiguous steps flexible.** A hybrid can make sense too: use code for reliable operations and natural-language guidance for decisions or exceptions.

---

## 4. Skills need a lifecycle, including deciding what to forget

A skill library can grow without limit. That makes it harder to retrieve the useful items and may slow inference. Three maintenance phases show up repeatedly.

### Admission control: check before storing

Before adding a newly induced skill, a judge model or reward verifier executes the candidate workflow or code to check whether it actually succeeds.

**Analogy:** Don't add a new recipe to the family cookbook just because someone wrote it down; try it first.

**Practical implication:** A successful-looking trace is not necessarily a reliable reusable skill. Testing before admission can filter out procedures that only appeared to work.

### Failure reflection: learn from what went wrong

An agent can extract a negative lesson from an unsuccessful attempt. For example: "Don't page through thousands of results; apply category filters first." Systems built on reasoning memory describe this explicitly, storing structured lessons from both successful and failed rollouts ([ReasoningBank, ICLR 2026](https://proceedings.iclr.cc/paper_files/paper/2026/hash/980ea04d23d1f6908964eba2a74afe45-Abstract-Conference.html)).

**Analogy:** A pilot's checklist records not only the normal procedure, but also mistakes that are worth avoiding next time.

**Practical implication:** Failures can improve future behavior if the system turns them into specific, reusable guidance, not merely a vague note that "the task failed."

### Memory consolidation: prune infrequently used skills

**TroVE** prunes skills based on how often they are invoked relative to the total number of tasks solved. Its own framing is a toolbox that is generated, grown, and *periodically pruned* so the functions stay verifiable and efficient ([TroVE, ICML 2024](https://arxiv.org/abs/2401.12869)). An example threshold heuristic given in the source material is to drop functions whose cumulative invocation count falls below roughly **½ log₁₀(N)**, where **N** is the number of tasks solved.

Treat that number as a paraphrase, not a quoted result. I could confirm the periodic-pruning mechanism in the TroVE paper, but not that exact formula, so the ½ log₁₀(N) figure stays **unconfirmed**.

**Analogy:** Periodically clear out a toolbox: keep the tools that are repeatedly useful, and reconsider the ones that are rarely used.

**Practical implication:** Pruning can reduce clutter and improve the odds of retrieving a useful skill. But infrequent use does not always mean a skill is unimportant: an uncommon emergency procedure might be valuable precisely because it is rarely needed. Frequency is a helpful signal, not a perfect measure of value.

---

# Diagnostic exercise

## 1. When would you choose code skills for AWS or GCP consoles, and how would you reduce UI-change brittleness?

I'd lean toward **code skills** when the cloud-console task is:

- Repeated often, with many predictable low-level steps.
- Stable enough that the actions can be tested and maintained.
- Costly or error-prone to perform manually, so a verified routine offers real value.
- Important to verify systematically, for example where automated checks can confirm that the operation completed as expected.

I'd lean toward **text skills** when the console workflow changes frequently, depends on interpretation, or needs to adapt to interface changes that are hard to anticipate. The source material does not cover AWS or GCP interfaces specifically, so this is a decision framework rather than a claim about any particular console.

To mitigate brittleness, I'd apply the **PolySkill-style separation of common operation from provider-specific implementation**:

1. Define a stable, abstract operation, for example a common "find the target resource" or "apply the requested configuration" method.
2. Put AWS- and GCP-specific behavior behind separate implementations of that operation.
3. Keep changing UI details out of the shared workflow where possible.
4. Test the provider-specific implementation after interface changes, and use those checks as part of admission or maintenance.

The main trade-off remains: code can be faster and easier to test, but it can still break when the underlying interface or API changes. An abstraction limits how widely a change spreads; it doesn't make the change disappear.

## 2. Why might 10 retrieved skills perform worse than 1 or 2, and how does consolidation help?

The likely mechanism described here is **context distraction**. A large collection of retrieved skills adds competing instructions and irrelevant detail to the active context. The agent has to decide which instructions apply, and extra material can crowd out the information most useful for the current task. So retrieval can hurt if it returns too much or too many weakly relevant skills. The budget-constrained study above points in the same direction: skill and memory modules carry a real token cost, and that cost is not always repaid ([Are Online Skill and Memory Modules Always Worth Their Tokens?](https://arxiv.org/pdf/2606.15017)).

This is a useful caution, not proof that "fewer is always better." The aim is to retrieve a small number of **well-targeted** skills, not to impose an arbitrary limit regardless of the task.

Memory consolidation helps by shrinking the library and improving retrieval precision: it can remove skills that are seldom used, and keep the collection from becoming an ever-growing pile of competing procedures. But frequency-based pruning has a real limitation: a rare, high-value skill could be removed simply because it is rarely needed. Admission checks, task relevance, and retention of critical procedures matter alongside usage counts.

---

## A few takeaways, and open questions

- **Memory is not the same as skill:** one captures useful facts; the other captures a way of acting.
- **Load in layers:** an index can be cheap to inspect, while detailed instructions and executable assets are loaded on demand.
- **Choose representation to fit the task:** text is flexible; code is efficient and more directly testable, but can be brittle.
- **Treat a skill library as something to curate:** test new skills, learn from failures, and prune carefully.

One unresolved question is **who gets to judge whether a skill is good enough to store**. A judge model or reward verifier can help, but the sources don't say how its standards are set or how false successes are caught. Another is **how relevance is measured at retrieval time**: even a carefully maintained library can distract the agent if it returns the wrong skills. Those are not small implementation details; they determine whether a memory system makes an agent more capable or simply gives it more things to get confused by.

---

### FAQ

**What is the difference between agent memory and agent skills?**
Memory stores facts, events, and environment details, such as a token that a site expects in request headers. A skill stores a procedure, such as the sequence for searching a catalogue, comparing options, and verifying the result. Memory answers "what is true here," while a skill answers "how do I do this."

**What is progressive disclosure in agent skill loading?**
It is a layered loading scheme. The agent first sees only a compact index of skill names and trigger descriptions, then loads the full `SKILL.md` instructions when a skill looks relevant, and finally pulls scripts, references, or assets only for the steps that need them. The [agent-skills specification](https://agentskills.io/specification) recommends keeping the metadata tier near 100 tokens and the instruction body under roughly 5,000 tokens.

**Why do code skills break more often than text skills?**
Code skills hardcode assumptions, such as DOM selectors, endpoint paths, or API parameter names. When a site or console changes those details, the function fails immediately. Text skills are read and reinterpreted at run time, so a capable model can absorb small interface shifts without a code change.

**How do you stop a skill library from growing out of control?**
Use a lifecycle: test a candidate skill before it is admitted, convert failures into specific negative lessons, and periodically prune skills that are rarely invoked. Consolidation improves retrieval precision, but it should not be purely frequency-based, because a rarely used procedure may still be critical when it is finally needed.

**Is retrieving more skills always worse for an agent?**
No. Retrieving many weakly relevant skills adds competing instructions and crowds the context, but retrieving a small set of well-targeted skills is exactly the goal. The problem is relevance and volume, not retrieval itself.
