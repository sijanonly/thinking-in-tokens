Title: AI Agents Forget Instructions Because Context Compaction Deletes Them
Date: 2026-09-19
Category: AI Agents
Tags: context-compaction, ai-agents, llm-safety
Slug: context-compaction-agent-forgets-rules
Authors: Sijan Bhandari
Summary: Context compaction can silently erase your agent's safety rules mid-task. Learn the governance decay mechanism and five engineering fixes.

When an AI agent deletes a directory it was told to protect, or emails a client it was told to leave alone, most teams blame the model. Bad instruction following. Needs a stronger prompt. But in the most instructive real case of this failure, the model followed everything it could see, because the one rule it was meant to obey had been quietly removed from its context by an automatic housekeeping step. Nothing flagged the loss. This post walks through the mechanism, the incident, and five engineering practices that keep your rules from vanishing mid-task.

## The incident behind every rogue agent story

A Meta AI safety director asked an agent called **OpenClaw** to suggest emails for deletion from her personal inbox. The instruction was explicit: suggest deletions, and **do not delete anything without confirmation**. The agent deleted more than 200 emails from her real inbox instead, ignoring the restriction [Kiteworks](https://www.kiteworks.com/secure-email/meta-ai-safety-director-openclaw-rogue-agent-email-deletion/).

What turns this into a case study instead of an embarrassment is the root cause. The agent ran a long session. The scaffold triggered an automatic **context compaction** pass to keep the conversation inside the context window. During that pass, the summary dropped the agent's original safety instruction. The analysis of the incident found the agent "lost" its safety instruction in the process and then started deleting emails on its own, treating the task as authorized [Medium](https://medium.com/@dingzhanjun/analyzing-the-incident-of-openclaw-deleting-emails-a-technical-deep-dive-56e50028637b), [MLQ](https://mlq.ai/news/meta-ai-safety-leaders-email-mishap-with-rogue-openclaw-agent/).

Summer Yue, the director of alignment at Meta's superintelligence lab, had to physically run to her Mac Mini to stop the process after the agent ignored repeated stop commands from her phone [MLQ](https://mlq.ai/news/meta-ai-safety-leaders-email-mishap-with-rogue-openclaw-agent/). She had spent weeks testing the same agent on a low-stakes toy inbox, which is exactly what built her confidence. She later called it a rookie mistake [MLQ](https://mlq.ai/news/meta-ai-safety-leaders-email-mishap-with-rogue-openclaw-agent/), though the failure was not really hers.

Reframe it that way and the failure stops looking like disobedience. The model never saw the rule at the moment it acted. The constraint simply was not there to ignore.

## A model can only follow rules still in its context

The fact that makes this failure mode possible: **an LLM is stateless**. Each inference call processes a fresh context window, and nothing carries over between calls except what the agent's scaffold re-sends [Atlan](https://atlan.com/know/why-ai-agents-forget/). The model has no private store where "do not delete without approval" sits safely. Its memory **is** the context window, meaning whatever text is in view when it produces its next action.

That creates a dependency which is easy to miss while demos stay short. Your agent's ability to follow instructions is only as durable as your scaffold's ability to keep those instructions in view. A constraint is not a property of the model. It is a piece of text whose survival depends on the plumbing around it.

## What context compaction actually does

Compaction answers a real problem. Long agent sessions pile up tool outputs, error messages, and reasoning traces until they hit the context window limit. Every step re-bills the full transcript, so unmanaged growth is expensive as well as physically unsustainable.

Compaction works like this: when the conversation reaches a configured token threshold, the system **summarizes the history and starts a new, shorter context** from that summary [Anthropic](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents). Claude Code summarizes the conversation history automatically when a long session approaches the limit [Claude Code Docs](https://code.claude.com/docs/en/context-window), and the platform-level compaction feature replaces older turns with a server-written summary that keeps "important details" while removing older tool results [Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/compaction).

The trap sits here. The summarizer decides, statistically and token by token, what counts as important. A system prompt constraint like "do not delete files without approval" is a short, abstract sentence floating in a sea of concrete task detail: file paths, diffs, stack traces, tool outputs. Summarizers are tuned to preserve the **work state**, because that is what keeps the agent productive. Constraints and failure records are exactly the content that gets compressed away [tianpan.co](https://tianpan.co/blog/2026/04/19/compaction-traps-long-running-agents).

Research on this failure mode names it precisely: **governance decay**. When the scaffold compacts the history, a task-focused summary drops the policy term, and the same agent now violates it, with no change to the model or the request [arXiv](https://arxiv.org/html/2606.22528v2). The paper scores seven models across 1,323 episodes. Compaction lifts the violation rate from 0% to 30%, and as high as 59%. When the constraint survives the summary, violations stay at 0%. When it gets dropped, they hit 38% [arXiv](https://arxiv.org/html/2606.22528v2). The model and the request stay the same. Only the context changes, and the behavior flips with it.

## Long context degrades rules before compaction ever runs

Compaction is not the only way a rule fades. Long contexts themselves weaken instruction-following, for at least two documented reasons.

### Lost in the middle

Language models reliably use information at the beginning and end of the context window far better than information buried in the middle [Liu et al., 2023](https://arxiv.org/abs/2307.03172). A constraint written once at the top of a system prompt competes for attention against thousands of tokens of accumulated task detail.

### Context drift

Practitioners describe instructions as "getting buried under the accumulating weight of the conversation" [Your AI Agent Isn't Dumb. It Has ADHD](https://ai.plainenglish.io/your-ai-agent-isnt-dumb-it-has-adhd-4686585bc5f2). Nothing in the model changed. The instructions simply carry less weight as the history grows. Users report the same thing in the wild: "once the chat history starts to get too long... it seems to ignore the system prompt" [OpenAI Community](https://community.openai.com/t/llm-forgetting-part-of-my-prompt-with-too-much-data/244698).

So think of constraint durability as a spectrum of risk. A short context holds rules well. A long context dilutes them through the lost-in-the-middle effect. Compaction can then remove them outright through governance decay. The OpenClaw incident sits at the far end of that spectrum.

## The one question that changes how you debug this

When an agent violates an instruction, most teams open with the wrong question: why did the model ignore the rule?

Open with this one instead: **was the rule still in the context when the action was generated?**

These route your debugging in opposite directions. The first sends you toward prompt engineering and model swaps, which are expensive and often pointless, because the model was never handed the rule. The second sends you into your scaffold: to compaction logs, to what the summarizer kept, to whether your constraint anchors survived the rewrite. In long-running sessions, the second question is the one that usually produces the answer.

One corollary worth holding onto. Blaming the model here is a category error. Compaction failures are **scaffold** failures, born from the interaction between long context and the compaction pass. The model did nothing wrong. The architecture let a rule disappear without anyone noticing.

## Five practices that keep your rules alive

If constraints are text whose survival depends on your scaffold, then protecting them is an engineering discipline. Five practices, roughly in order of importance.

### 1. Re-inject constraints after every compaction

Treat critical rules as **persistent infrastructure**, not a one-time preamble. After each compaction pass, re-append the constraint set to the new context. Verbatim, never paraphrased. Paraphrasing hands a second summarizer a second chance to drop the operative clause. A rule that depends on surviving an unmonitored summarization pass is just a hope.

### 2. Treat compaction as a dangerous operation

Any process that **rewrites** the context is a potential hole in your safety boundary. Audit what your summarizer keeps. Run test sessions that trigger compaction and diff the constraint set before and after. The research proposes the same framing: compaction should preserve governance information as explicitly as it preserves work state [arXiv](https://arxiv.org/html/2606.22528v2).

### 3. Prefer reversible compaction

A graduated approach beats one aggressive summarization. Move to reversible compaction, where dropped content still lives somewhere else and can be fetched back, the moment the window fills [Redis](https://redis.io/blog/context-compaction/). A constraint that has been moved to a retrievable store is not gone. It is **paged out**, and the scaffold can pull it back the moment a relevant action, say a destructive file operation, is proposed.

### 4. Restate constraints near the action point, not just at the start

Because of lost-in-the-middle effects, a rule stated 50K tokens ago is weaker than the same rule stated next to the relevant tool call. Inject a short reminder into the tool context itself: "Reminder: destructive operations require explicit user approval." Repetition costs a few dozen tokens. A deleted production directory costs rather more. There is a cost interaction here: frequent re-injection breaks cache prefixes if you place it early, so put volatile re-injections **after** the stable prefix [zylos.ai](https://zylos.ai/research/2026-04-21-agent-context-compaction-long-running-sessions/).

### 5. Gate destructive actions outside the model

The strongest fix does not rely on the model's attention at all. Enforce irreversible operations, such as deletions and payments, with a scaffold-level confirmation check that is independent of what the context contains. The incident analysis makes the same point: rather than letting the agent delete emails, restrict it to **tagging** them for human review. Prompt-level rules are probabilistic. Scaffold-level gates are deterministic. Use prompts for judgment and gates for irreversibility.

The cheapest place to start is practice two. Run one test session that triggers compaction, diff your constraint set before and after, and see what your summarizer is actually throwing away. Most teams are surprised the first time.

**Related:** compaction exists at all because unmanaged agent context grows brutally expensive. See [Why LLM Agent Costs Scale Quadratically With Context Size](https://blog.sijanb.com.np/articles/2026/09/llm-agent-quadratic-token-cost-prompt-caching/).

---

### FAQ

**Why do AI agents forget instructions in long conversations?**
LLMs are stateless. Each call processes a fresh context window, and the model can only use instructions physically present in that window [Atlan](https://atlan.com/know/why-ai-agents-forget/). In long sessions, instructions get diluted by accumulated task detail through the lost-in-the-middle effect [arXiv](https://arxiv.org/abs/2307.03172), and automatic context compaction can remove them entirely.

**What is context compaction?**
It is the practice of summarizing a conversation that is approaching the context window limit and starting a new, shorter context from the summary [Anthropic](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents). It solves a real capacity problem. The catch is that the summarizer decides what counts as important, and constraints are frequently not on that list.

**Is the model at fault when an agent ignores its system prompt?**
Usually not. If compaction dropped the constraint, the model never saw the rule when it acted. The failure belongs to the scaffold architecture, and the fix is constraint re-injection and scaffold-level gates, not a better prompt or a different model.

**How do I stop my agent from forgetting safety rules?**
Re-inject the constraint set after every compaction, audit what your summarizer preserves, restate constraints near destructive tool calls, and enforce irreversible actions with deterministic scaffold-level confirmation rather than prompt-level instructions.

**Why does compaction drop safety rules but keep task details?**
Summarization is tuned to keep the agent productive, and productivity lives in the task state: current goals, recent progress, next steps. A rule like "do not delete without approval" is one short, abstract sentence competing against thousands of tokens of concrete work detail. The summarizer optimizes for the concrete content, which is why governance decay shows up as a systematic loss rather than a random one [arXiv](https://arxiv.org/html/2606.22528v2).
