Title: LLM Agent Costs Are Quadratic: The Token Trap and the Prompt Caching Fix
Date: 2026-09-19
Category: AI Agents
Tags: ai-agents, llm-costs, prompt-caching
Slug: llm-agent-quadratic-token-cost-prompt-caching
Authors: Sijan Bhandari
Summary: An agent loop re-bills the whole transcript every step, so input cost grows with the square of the steps. The math, a worked example, the caching fix.

Your spreadsheet says 20 model calls at 2,000 tokens each. Your invoice says 420,000 tokens.

That gap isn't a billing bug. A multi-turn agent re-sends its entire transcript on every call, so input cost scales with the square of the step count, and a per-step estimate undershoots by an order of magnitude. Below I work through the arithmetic, show where the money actually goes, and give you the caching rules that pull the curve back down to something you can afford.

## Why your agent re-bills the entire transcript every call

An LLM is stateless. Call the model at step 10 and the API has no memory of steps 1 through 9. So the runtime re-sends everything: the system prompt, every reasoning trace, every tool output, every error string. The model re-processes all of it as input tokens.

Practitioners describe the mechanic plainly. "Naive agent loops rebill prior context on every call, so input token cost grows quadratically as tool outputs and reasoning traces accumulate" [AugmentCode](https://www.augmentcode.com/guides/ai-agent-loop-token-cost-context-constraints).

The multiplier gets ugly fast. The same analysis found that a 20-step loop generating 1,000 tokens per step produces 210,000 cumulative input tokens, against the 20,000 a per-step estimate predicts [AugmentCode](https://www.augmentcode.com/guides/ai-agent-loop-token-cost-context-constraints).

So your sheet says 20 calls at 2K tokens. Reality says 420K, because by call 20 the transcript is 40K deep and each of the 20 calls paid to read it again.

### What actually fills the transcript

In production loops, tool outputs and reasoning traces dominate. The user's opening prompt is a rounding error next to them. One `grep` across a large repo, or one database dump, can add thousands of tokens in a single step. Every one of those tokens gets copied into the input of every call that follows.

## The arithmetic behind O(S²)

Make it concrete. Say each step adds j net new tokens (tool output, the model's action, the observation), and the agent runs S steps with no compaction and no caching.

At step s the window holds roughly s·j tokens, and prefill processes all of them. Aggregating over the run gives:

```
aggregate over s = 1..S of (s · j)  =  j·S(S+1)/2  ≈  O(j·S²)
```

That's the triangle number. Step 1 costs j. Step 10 costs 10j. Step 50 costs 50j. The full run comes to about 1,275·j tokens. Every rectangle in the cost picture is as wide as its token count, and the total area grows with the square of the conversation length, the same framing used in the "Expensively Quadratic" analysis of the agent cost curve [exe.dev](https://blog.exe.dev/expensively-quadratic).

### A worked example at $3 per million input tokens

Assume j = 2,000 new tokens per step and input pricing of $3 per million tokens. That rate sits inside the range for current frontier models, roughly $2.50 to $5 per million input tokens [Waxell](https://waxell.ai/blog/ai-agent-context-window-cost), and matches Claude Sonnet 4.6 at $3 input and $15 output per million [Metacto](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration), [IntuitionLabs](https://intuitionlabs.ai/articles/claude-pricing-plans-api-costs).

| Steps (S) | Cumulative input tokens | Cumulative input cost | Naive estimate (S × j) | Multiplier |
|---|---|---|---|---|
| 5 | 30K | $0.09 | 10K | 3x |
| 10 | 110K | $0.33 | 20K | 5.5x |
| 20 | 420K | $1.26 | 40K | 10.5x |
| 50 | 2.55M | $7.65 | 100K | 25.5x |

The bottom row is where this stops being hypothetical. A "50-step agent" that looks like a 100K-token job on paper is a 2.5-million-token job. And that counts input only. Output tokens bill at about 5 to 6 times the input rate on these models [exe.dev](https://blog.exe.dev/expensively-quadratic), [Waxell](https://waxell.ai/blog/ai-agent-context-window-cost), so they land on top of this.

(A caution: $3 per million is a stand-in rate. Always price against your actual model and provider.)

## Two different quadratics, and only one is yours to fix

This distinction decides what you can change.

1. **The billing quadratic.** Cumulative token spend grows as O(S²) because the loop re-sends the full transcript each turn. That's an architecture decision, and it's the one this post is about.
2. **The attention quadratic.** Within a single call, self-attention computes relationships between every pair of tokens, so per-call compute grows roughly O(m²) with context length m. You can't engineer that away, and it isn't why your cumulative bill explodes.

Blame for the blowup belongs to the transcript-resending behavior, and that behavior lives in your loop. Which means the biggest lever is also yours to pull.

## Why the bill keeps climbing

Two forces feed the quadratic. Context windows have grown enormous, commonly exceeding 200,000 tokens in 2026 [Waxell](https://waxell.ai/blog/ai-agent-context-window-cost), so agents rarely hit a hard wall that would force you to manage context. The loop just keeps appending.

The second force is price asymmetry. Frontier rates run from about $1 to $25 per million tokens depending on model and token type [Metacto](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration), and output tokens sit at the expensive end every time. A bloated transcript inflates the input side of every call, and the input side is where the quadratic lives.

## Stop re-reading the prefix

If the quadratic comes from re-processing the same token prefix on every call, the fix is to stop re-processing it. That's what KV caching and prefix caching do.

A transformer converts each input token into key/value tensors during prefill. When the first 38K tokens of this call are identical to the first 38K of the last call, and in an agent loop they almost always are, the provider reuses those tensors instead of recomputing them. Prefill work on the shared prefix is skipped, and those tokens bill at a discount.

The savings show up in the providers' own price sheets:

- Reused input tokens cost 80% to 90% less than fresh ones. Anthropic prices cache reads at 0.1x the base input rate, so Sonnet 4.6 reads cost $0.30 per million against $3.00 standard, a 90% saving [Metacto](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration), [PE Collective](https://pecollective.com/tools/claude-pricing-guide/).
- OpenAI discounts reused input tokens by up to 95%. Cache writes cost 1.25x standard and reads cost 0.1x on most models (0.05x on GPT-6.1 Sol). One write plus nine full reads comes to 2.15x ordinary input, against 10x with no caching [OpenAI](https://developers.openai.com/api/docs/guides/prompt-caching).
- At the serving layer, a 90% KV cache hit rate means the server skips 90% of that prefill work, cutting effective compute cost per request by 80% to 90% [Spheron](https://www.spheron.network/blog/context-engineering-production-ai-agents-kv-cache-long-context/).

### Three rules that make prefix caching work

Providers match on exact token prefixes. Change something early in the sequence and everything after it is invalidated. Three rules follow.

1. **Keep the system prompt and tool definitions byte-stable** at the front of the context. A timestamp at position 100 busts the cache for the next 40,000 tokens.
2. **Append, don't rewrite.** Stable-prefix design, where each call's context is the previous context plus new tokens, makes an agent loop cache-friendly by construction.
3. **Budget for cache writes.** Anthropic applies a 1.25x to 2x write premium depending on cache lifetime [TechSpire](https://technspire.com/en/blog/anthropic-prompt-caching-pricing-mechanics). On long transcripts that still comes out far ahead, because you pay a one-time premium against a recurring quadratic.

What caching does, stated honestly: it cuts the constant on the quadratic by about an order of magnitude. The curve shape stays the same. For most agent workloads, that's the difference between an unviable cost curve and a manageable one.

## What to check next

- **Log `cached_tokens` separately** from total input tokens on every call. Your real cost trend is the cache-miss input volume, not the raw input count.
- **Set a context budget per task type.** If a task routinely runs past 30 to 50 steps, the quadratic is working against you, and prompt tweaking won't change that.
- **Order prompts for prefix stability.** Static instructions first, volatile content last. This is cache engineering as much as prompt engineering.
- **Treat context management as a decision.** Compaction (summarizing older turns to shrink the base) lowers the quadratic's starting point, but it carries its own serious risk: it's how agents silently lose their own safety rules. That failure mode deserves its own post: [how context compaction makes agents forget rules](https://blog.sijanb.com.np/articles/2026/09/ai-agent-context-compaction-safety-rules/).

---

### FAQ

**Why do LLM agent costs grow quadratically?**

Because the model is stateless. Every step re-sends the full transcript, so the tokens billed at step s scale with s. Aggregate that over S steps and you get S(S+1)/2, which is O(S²) in the number of steps [AugmentCode](https://www.augmentcode.com/guides/ai-agent-loop-token-cost-context-constraints).

**Is that the same as attention being O(m²)?**

No. Attention's quadratic is a per-call compute property, and it holds for a single request. The agent cost quadratic is a cumulative billing property caused by resending history on every call. You live with the first one. You engineer away the second.

**How much does prompt caching actually save?**

Provider-published discounts on reused input tokens reach 90% on Anthropic cache reads, priced at 0.1x base input [Metacto](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration), and up to 95% on OpenAI [OpenAI](https://developers.openai.com/api/docs/guides/prompt-caching). Your real number depends on your hit rate, which is why you should log cached tokens separately.

**Does a bigger context window make my agent more expensive?**

Only indirectly. A larger window doesn't raise the per-token price. It removes the pressure to manage context. With frontier input pricing around $2.50 to $5 per million tokens [Waxell](https://waxell.ai/blog/ai-agent-context-window-cost), an unmanaged transcript fills fast and re-bills faster.

**Does context compaction fix the quadratic?**

It lowers the starting point, not the shape. Compaction shrinks the base that the quadratic compounds on, so it does help. It also adds a new failure mode, since summarized turns can drop the constraints an agent was following.
