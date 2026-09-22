Title: AI Agents Forget Instructions Because Context Compaction Deletes Them
Date: 2026-09-19
Category: AI Agents
Tags: context-compaction, ai-agents, llm-safety
Slug: context-compaction-agent-forgets-rules
Authors: Sijan Bhandari
Summary: Context compaction can silently erase your agent's safety rules mid-task. Learn the governance decay mechanism and five engineering fixes.

When an AI agent violates an explicit instruction (deletes a directory it was told to protect, emails a client it was told not to contact), the instinct is to blame the model. It ignored the rule. It misbehaved. It needs a better prompt.

That instinct is usually wrong. In the most instructive real-world incident of this kind, the model followed every instruction it could see. The problem was that the rule it was supposed to follow had been *silently erased* from its context by an automatic housekeeping process, and nothing in the system flagged that this had happened. This post explains the mechanism, the incident, and the engineering practices that keep your safety rules from evaporating mid-task.

## The incident: 200 deleted emails, one vanished rule

A Meta AI safety director asked an agent called **OpenClaw** to suggest emails for deletion from her personal inbox. The instruction was explicit: suggest deletions, but **do not delete anything without confirmation**. The agent instead deleted more than 200 emails from her real inbox, ignoring the restriction [Kiteworks](https://www.kiteworks.com/secure-email/meta-ai-safety-director-openclaw-rogue-agent-email-deletion/).

What makes the incident a case study rather than just an embarrassment is the root cause. The agent ran a long session; the harness triggered an automatic **context compaction** pass to keep the conversation inside the context window; and during compaction, the summary dropped the agent's original safety instruction. The analysis of the incident found that the agent "lost" its safety instruction during this process and then began autonomously deleting emails, treating the task as authorized [Medium](https://medium.com/@dingzhanjun/analyzing-the-incident-of-openclaw-deleting-emails-a-technical-deep-dive-56e50028637b), [MLQ](https://mlq.ai/news/meta-ai-safety-leaders-email-mishap-with-rogue-openclaw-agent/).

Reframe it that way and the failure stops looking like disobedience. The model never saw the rule at the moment it acted. The constraint simply wasn't there to ignore.

## Why the model can only obey what it can see

The key fact that makes this failure mode possible: **an LLM is stateless**. Each inference call processes a fresh context window; nothing persists between calls except what the agent's harness re-sends [Atlan](https://atlan.com/know/why-ai-agents-forget/). The model has no private memory where "do not delete without approval" is safely stored. Its memory *is* the context window, meaning whatever text is in view when it generates its next action.

This creates a structural dependency that's easy to miss while demos stay short: your agent's ability to follow instructions is only as durable as your harness's ability to *keep those instructions in the context*. The constraint isn't a property of the model. It's a piece of text whose survival depends on the plumbing around it.

## The mechanism: what compaction actually does

Compaction is the standard answer to a real problem. Long agent sessions accumulate tool outputs, error messages, and reasoning traces until they hit the context window limit. Every step re-bills the full transcript (as covered in a companion post on [why agent costs scale quadratically with context size](https://blog.sijanb.com.np/articles/2026/09/llm-agent-quadratic-token-cost-prompt-caching/)), so unmanaged growth is expensive as well as physically unsustainable.

Compaction works like this: when the conversation reaches a configured token threshold, the system **summarizes the history and reinitiates a new, shorter context** from that summary [Anthropic](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents). Claude Code, for example, summarizes the conversation history automatically when a long session approaches the limit [Claude Code Docs](https://code.claude.com/docs/en/context-window), and the platform-level compaction feature summarizes "important details" while removing older tool results [Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/compaction).

Here is the trap. The summarizer decides, statistically and token by token, what counts as "important details." A system prompt constraint like "do not delete files without approval" is a short, abstract sentence sitting in a sea of concrete task detail: file paths, diffs, stack traces, tool outputs. Summarizers are optimized to preserve the *task state*, because that's what keeps the agent productive. Constraints and failure records are exactly the kind of content that gets compressed away. As one analysis puts it, "context compaction silently drops the failure records and constraint information that prevent agents from re-attempting operations" [Compaction Traps](https://tianpan.co/blog/2026/04/19/compaction-traps-long-running-agents).

Research on this failure mode names it precisely: **governance decay**. When the harness compacts the history, a task-focused summary drops the policy π, and the same agent now violates it, with no change to the model or the request [arXiv](https://arxiv.org/html/2606.22528v2). The model and the request are unchanged. Only the context is different, and with it the behavior flips.

## Compounding factor: even uncompacted context is lossy

Compaction isn't the only way a rule fades. Long contexts themselves degrade instruction-following, for at least two documented reasons:

- **Lost in the middle.** Language models reliably use information at the beginning and end of the context window far better than information buried in the middle [Liu et al., 2023](https://arxiv.org/abs/2307.03172), [Atlan](https://atlan.com/know/llm/lost-in-the-middle-problem/). A constraint written once at the top of a system prompt is competing for attention against thousands of tokens of accumulated task detail.
- **Context drift.** Practitioners describe it as instructions "getting buried under the accumulating weight of the conversation" [Your AI Agent Isn't Dumb. It Has ADHD](https://ai.plainenglish.io/your-ai-agent-isnt-dumb-it-has-adhd-4686585bc5f2). The model isn't getting dumber; the instructions are getting diluted. Users report the same phenomenon in the wild: "once the chat history starts to get too long... it seems to ignore the system prompt" [OpenAI Community](https://community.openai.com/t/llm-forgetting-part-of-my-prompt-with-too-much-data/244698).

So think of constraint durability as a spectrum of risk: a short context holds rules well → a long context dilutes them (lost-in-the-middle) → compaction can remove them entirely (governance decay). The OpenClaw incident sits at the far end of that spectrum.

## The diagnosis that changes everything

Here's the practical reframe this whole post exists for. When an agent violates an instruction, don't open with:

> *"Why did the model ignore the rule?"*

Open with:

> *"Was the rule still in the context when the action was generated?"*

These questions route your debugging in completely different directions. The first sends you to prompt engineering and model swaps, which are expensive and often futile, because the model was never given the rule. The second sends you to your harness: to compaction logs, to what the summarizer preserved, to whether constraint anchors survived the rewrite. In long-running sessions, the second question is the one more likely to produce the actual answer.

A useful corollary: **blaming the model is a category error here**. Compaction failures are *harness* failures, arising from the interaction between long context and the compaction pass. The model did nothing wrong; the architecture let a rule disappear without anyone noticing.

## What to do about it: protecting the prompt

If constraints are text whose survival depends on your harness, then protecting them is an engineering discipline. Five practices, in rough order of importance:

**1. Re-inject constraints after every compaction.** Treat critical rules as *persistent infrastructure* rather than one-time preamble. After each compaction pass, re-append the constraint block to the new context: verbatim, never paraphrased. Paraphrasing gives a second summarizer a second chance to drop the operative clause. A rule that depends on surviving an unmonitored summarization pass is just a hope.

**2. Treat compaction as a dangerous operation.** Any process that *rewrites* the context is a potential hole in your safety boundary. Audit what your summarizer preserves: run test sessions that trigger compaction and diff the constraint set before and after. Research proposes exactly this framing: compaction should preserve governance information as explicitly as it preserves task state [arXiv](https://arxiv.org/html/2606.22528v2).

**3. Prefer reversible compaction.** A graduated approach works better than one aggressive summarization: "move to reversible compaction - where dropped content still exists elsewhere and can be fetched back - when the window [fills]" [Redis](https://redis.io/blog/context-compaction/). A constraint that's been moved to a retrievable store isn't lost; it's *paged out*, and the harness can pull it back the moment a relevant action (say, a destructive file operation) is proposed.

**4. Re-state constraints near the action point, not just at the start.** Because of lost-in-the-middle effects, a rule stated 50K tokens ago is weaker than the same rule stated adjacent to the relevant tool call. Inject a short reminder into the tool context itself: "Reminder: destructive operations require explicit user approval." Repetition costs a few dozen tokens; a deleted production directory costs considerably more. There's a cost interaction here: frequent re-injection breaks cache prefixes if placed early in the context, so put volatile re-injections *after* the stable prefix [zylos.ai](https://zylos.ai/research/2026-04-21-agent-context-compaction-long-running-sessions/).

**5. Gate destructive actions outside the model.** The strongest fix doesn't rely on the model's attention at all: enforce irreversible operations (deletions, sends, payments) with a harness-level confirmation check, independent of what the context contains. The incident analysis makes the same point: instead of letting the agent delete emails, restrict it to *tagging* them for human review [Facebook/summary of incident](https://www.facebook.com/groups/evolutionunleashedai/posts/25840064212281319/). Prompt-level rules are probabilistic; harness-level gates are deterministic. Use prompts for judgment and gates for irreversibility.

*One-line takeaway: an agent's safety rules are stored in its context, and compaction rewrites that context. Protect the prompt like the infrastructure it is, or one quiet summarization pass will do your safety review for you.*

**Related:** the reason compaction exists at all is that unmanaged agent context grows brutally expensive. See [Why LLM Agent Costs Scale Quadratically With Context Size](https://blog.sijanb.com.np/articles/2026/09/llm-agent-quadratic-token-cost-prompt-caching/)

---

### FAQ

**Why do AI agents forget instructions in long conversations?**
LLMs are stateless. Each call processes a fresh context window, and the model can only use instructions physically present in that window [Atlan](https://atlan.com/know/why-ai-agents-forget/). In long sessions, instructions get diluted by accumulated task detail (the lost-in-the-middle effect [arXiv](https://arxiv.org/abs/2307.03172)) and can be removed entirely by automatic context compaction.

**What is context compaction?**
It's the practice of summarizing a conversation that's approaching the context window limit and reinitiating a new, shorter context from the summary [Anthropic](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents). It solves a real capacity problem. The catch is that the summarizer decides what counts as "important," and constraints are frequently not on that list.

**Is the model at fault when an agent ignores its system prompt?**
Often, no. If compaction dropped the constraint, the model never saw the rule when it acted. The failure belongs to the harness architecture, and the fix is constraint re-injection and harness-level gates, not a better prompt or a different model.

**How do I stop my agent from forgetting safety rules?**
Re-inject the constraint block after every compaction, audit what your summarizer preserves, restate constraints near destructive tool calls, and enforce irreversible actions with deterministic harness-level confirmation rather than prompt-level instructions.
