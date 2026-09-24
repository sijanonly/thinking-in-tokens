Title: Long-Context and State Management for AI Agents
Date: 2026-09-23
Category: AI Agents
Tags: ai-agents, tool-calling, grammar-constrained-decoding
Slug: how-ai-agents-turn-text-into-actions
Authors: Sijan Bhandari
Summary: Long-context AI agents slow down as history grows. Here is how KV caching and context compaction keep latency under control.

## Why an Agent Run Is a Marathon

An agent does not answer one question and stop. It runs for hours or days: calling tools, reading outputs, fixing errors, trying again. Every step lands in its conversation history, which I will write as h_t, and by the end of a long run that history balloons to tens or hundreds of thousands of tokens. That is far more than fits comfortably in a model's working memory, and far more than the prefill step can chew through for free.

Picture a detective working a long case. Every note, every interview transcript, every dead-end lead gets stapled into the case file. The file grows until the detective spends more time re-reading the file than detecting.

Three techniques handle that growth, and they build on each other. I take them in the order you need them, then walk through two failures that show why ordering and placement matter more than most teams expect.

## Pillar 1: KV Caching and Prefix Reuse (RadixAttention)

### The plain-language version

When a transformer processes text it converts every token into Key and Value representations, which act as a pre-digested summary of each word that the attention mechanism can consume. Producing those summaries is the expensive part.

Here is the waste. At every turn, the agent's prompt looks like this:

System instructions + tool definitions + everything that happened so far + one new thing

The "everything that happened so far" block is identical to the previous turn. Recomputing its summaries every single time is like a chef re-chopping vegetables for a stew, every bowl served, when the vegetables were already chopped yesterday.

### How the fix works

Engines like vLLM and SGLang store those pre-computed summaries (the KV cache) in GPU memory, organized as a radix tree. Think of a shared filing system where identical text prefixes point to the same cached blocks. When a new turn arrives, the engine notices that the first 99% of the prompt has not changed, skips the recomputation, and does fresh work only on the newly appended observation. That boundary is the prefix cache boundary: the static prefix is a cache hit, and only the new token delta gets computed.

Run the numbers and the payoff is obvious. Without prefix caching, prefill cost scales with the square of context length, O(N²), because every token has to look at every other token. With it, you pay once and reuse.

### The catch: cache invalidation

The cache survives only while the prefix stays byte-for-byte identical. If the harness edits one token in the history, say by retroactively rewriting an old message, the prefix hash changes and every cached block after that point gets thrown away. All that re-chopping happens again.

So the practical rule: treat the historical prompt as immutable and append-only. Choices that look cosmetic, such as where you insert a timestamp or how you format a retry message, carry real latency consequences. I will show the worst version of this below.

## Pillar 2: Positional Encodings and RoPE

### The plain-language version

A model needs to know where each token sits in the sequence, because meaning depends on order. The dominant technique is RoPE (Rotary Position Embedding): each token's representation gets rotated by an angle proportional to its position, like the hands of a clock. Token 5 rotates a little. Token 5,000 rotates a lot.

### What happens when context gets too long

The rotations were calibrated during training, when the model saw positions only up to some training context length L_train, say 8,000 tokens. Push an agent's trajectory past that limit and the rotation angles enter territory the model never saw. Attention scores implode. The ability to connect related pieces of text collapses, and reasoning quality falls off a cliff. It is like a clock whose hands keep spinning past 12 and start meaning something the clock was never designed to express.

### The fix: frequency-domain interpolation

Instead of letting the angles fly blind, engines interpolate in the frequency domain. YaRN is the example I keep running into. Interpolation smoothly stretches the positional scale so a model trained at 8k tokens can operate at 128k. Slow the whole clock down, and the familiar range covers a much longer span.

I want to be honest about the tradeoff. The stretching works, yet it still carries a cost. The model now reasons in a regime that only approximates its training distribution, which is one reason long-context performance stays shakier than short-context performance even after the scaling tricks land.

## Pillar 3: Context Compaction, or Deciding What to Forget

GPU memory is finite and attention still scales quadratically, so at some point the trajectory has to shrink. I reach for three escalating strategies.

### Strategy A: rule-based truncation

A large tool output, say a 5,000-line git diff or a huge log file, gets mechanically clipped. Keep the first ~50 lines and the last ~50 lines, discard the middle, and always preserve the system instructions and the recent turns.

The flaw is staring you in the face. You do not know which 4,900 lines mattered. If the bug sat on line 2,300, truncation deleted your evidence. This approach is cheap and predictable, and it is also dumb.

### Strategy B: LLM state summarization

A secondary LLM pass reads the old history (h_{1:t-k}) and compresses it into a structured snapshot with three fields:

- Goal: what the user originally asked for
- Completed sub-tasks: which tools ran and what happened
- Current state: what is pending and what comes next

Hundreds of raw tokens of history collapse into a compact state summary block that gets spliced into the prompt.

The flaw here is subtler. A summary keeps conclusions and discards the evidence. If the agent later needs to re-examine the exact error message from turn 12, because the situation changed and the old conclusion no longer holds, that verbatim detail may be gone. Summarization loses information in ways you cannot predict in advance. My honest read: this is the least-solved problem in the whole stack. What to keep depends on what the future will ask for, and you find out you kept the wrong things only after the agent fails.

### Strategy C: memory tiering

Instead of holding everything in the active prompt, old turns get offloaded to an external vector database or key-value store, a searchable archive the agent can query on demand. The prompt stays lean and the memory lives outside it.

The tradeoff: retrieval becomes a step that can fail or run slow, and the agent has to know what to ask for, which is itself a reasoning task. Retrieval quality deserves its own post, so treat this as an open door for now.

These strategies layer together in practice. Real systems clip the obviously verbose tool outputs, summarize the settled history, and offload the long tail to external storage.

## Two Agent Failures, Worked Through

### Failure 1: the timestamp that breaks everything

Scenario: the harness injects a dynamic timestamp, Current Time: 2026-09-17 07:04:45, into the middle of the system prompt on every turn. What happens to the prefix KV cache, and what does it do to latency?

This is close to a worst-case placement. Remember the rule from Pillar 1: the KV cache is valid only for the portion of the prompt that is byte-for-byte identical to the previous turn's prompt, and the cache boundary stops at the first changed token.

Because the timestamp sits in the middle of the system prompt:

- Everything before the timestamp, the first part of the system prompt, still matches the previous turn, so those KV blocks stay cached. A small win, and that is all you get.
- Everything after the timestamp, meaning the rest of the system prompt, all tool definitions, and the entire trajectory history, now sits behind a changed token. The prefix hash for that region no longer matches. The cache for all of it is invalidated.
- On every single turn the engine has to recompute the K/V projections for the full remainder of the prompt, the same O(N²)-scaled prefill work that prefix caching exists to avoid. As the trajectory grows to tens of thousands of tokens, that recomputation grows with it, turn after turn.

Latency impact: dramatic and compounding. A timestamp injected at the very end of the prompt would cost almost nothing, since only a few tokens recompute. Injected in the middle of the system prompt, it turns every turn into a full prefill of the entire history. Static content first, dynamic content last. A dynamic timestamp belongs at the tail of the prompt, if anywhere at all.

There is a design irony here worth naming. The timestamp carries almost no information value to the model, and its position silently destroys the single biggest inference optimization available. Harness-level implementation details like this, invisible to the model itself, dominate real-world agent latency.

### Failure 2: why "lost in the middle" hurts agents more

Empirical studies show long-context models retrieve facts at the head and the tail of the context window far more accurately than facts buried in the middle. The shape is the U-shaped attention curve. Picture a person skimming a long document by reading the first page and the last page carefully and only glancing at the pile in between.

Now connect that to Strategy A. Agent trajectories are structurally built so the middle gets stuffed with exactly the material that matters most:

- The head of the context holds the system prompt and the user's original goal, which is important material sitting in the well-attended zone.
- The tail holds the most recent turns, also well attended.
- The middle accumulates long command outputs: stdout logs, git diffs, tool results, error dumps. That is precisely the region where models retrieve poorly.

So the agent's most information-dense evidence, what actually happened when the tool ran, gets deposited into the part of the context the model attends to worst. The danger compounds.

A subtle error message buried mid-trajectory may be effectively invisible when the agent later reasons about it. Compaction can make this worse by design: rule-based truncation keeps the head and tail of tool outputs and drops the middle, mirroring at the harness level the same head and tail bias the model already has. If the model attends to the head and tail anyway, and the harness deleted the middle, the two failure modes align perfectly.

The failure is also silent. The model does not announce that it could not see line 2,300. It reasons confidently with an incomplete picture, which is a hallucination risk that looks from the outside like the agent simply being wrong.

Mitigations that follow from this logic: put critical facts near the head or the tail, for example by restating key findings at the end of a tool output. Prefer summarization that lifts important findings out of the middle. Use memory tiering so bulky raw outputs never sit in the active context at all.

## What I Still Doubt

The caching rule generalizes well beyond engineering. Keeping the prefix stable is a contract between the harness and the inference engine. Break it casually, through timestamps or adaptive formatting or reordered messages, and you pay a tax that never shows up on a dashboard. It just shows up as the agent feeling slow.

Compaction is a judgment call wearing the costume of a technical decision. What to drop from the middle is a question about what the future will need, and the future is unknowable at compaction time. A summary preserves the map and loses the territory. Truncation preserves the edges of the territory and loses its center. Either one can gut an agent's ability to recover from a wrong early conclusion.

An honest doubt: memory tiering gets presented as the escape hatch, yet retrieval quality then becomes a fresh single point of failure. If the vector store misses the one log line that mattered, the agent fails anyway, just with a cleaner-looking prompt.

And a question I would want answered before building anything: how often does trajectory content actually need retroactive editing? If the answer is rarely, append-only design plus prefix caching is a huge free win. If the answer is often, the architecture needs a different plan from day one.

## The One Idea That Connects All Three Pillars

Attention is expensive, and it is biased. I attack that single problem at three layers. The engine layer owns the cache. RoPE scaling lives inside the model's own internals. The harness layer decides what enters the window at all. A robust agent stack needs all three, because each layer's failure mode gets covered by a different one.

---

### FAQ

**What exactly invalidates a KV prefix cache?**

Any byte change in the prompt before the point where fresh content begins. The cache is keyed on prefix hashes, so it holds only while the prefix stays byte-for-byte identical to the previous turn. A timestamp rewritten mid-prompt, a reordered message, or a reformatted retry block all change the hash. Everything after the changed token gets recomputed from scratch on the next turn.

**Can I fix long-context problems just by scaling RoPE to a bigger window?**

Partly. Frequency-domain interpolation such as YaRN lets a model trained at 8k tokens serve 128k, but the model then runs in a positional regime that only approximates its training distribution. Retrieval and reasoning degrade as you push further past the training length. Extending the window also does nothing about the U-shaped attention curve, so facts sitting in the middle stay hard to retrieve no matter how large the window grows.

**For long tool outputs, should I truncate or summarize?**

Both, at different points. Truncation is cheap and keeps verbatim edges while losing the center, so it suits outputs you know are mostly boilerplate, such as a repetitive log. Summarization keeps conclusions while losing verbatim evidence, so it suits settled history you will not need to re-examine line by line. When an output is bulky and only occasionally relevant, offload it to external storage and let the agent query it.

**Why did my agent get slower after someone added a timestamp to the prompt?**

Because the timestamp sits in the middle of the system prompt and invalidates the prefix cache for everything after it, including all tool definitions and the whole trajectory. Every turn becomes a full prefill of the entire history, and the cost scales quadratically, so it compounds as the trajectory grows. Moving dynamic content to the tail of the prompt keeps the static prefix cacheable.
