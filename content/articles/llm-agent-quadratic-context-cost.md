Title: Why LLM Agent Costs Scale Quadratically With Context Size ?
Date: 2026-09-19
Category: AI Agents
Tags: ai-agents, llm, context-window
Slug: llm-agent-quadratic-context-cost
Authors: Sijan Bhandari
Summary: Each agent step re-reads the whole transcript. Total token cost grows as $$O(N^²)$$, not linearly - the math behind it, and how prompt caching brings it back down.

If you're running LLM agents in production, the most dangerous economic trap in the design isn't a bad model or a bad prompt - it's quadratic token growth. In a multi-turn agent loop, every step re-processes the entire accumulated conversation, so cost doesn't scale with the number of steps. It scales with the *square* of the number of steps. Understanding why that's true - and what actually fixes it - is the difference between an agent that's viable at scale and one that quietly eats your budget.

## The trap: your agent re-bills the full transcript every single call

Here's the mechanic that surprises people the first time they see an agent bill: an LLM is stateless. When your agent calls the model at step 10, the API doesn't "remember" steps 1-9. The harness re-sends the entire transcript - system prompt, every reasoning trace, every tool output, every error message - and the model re-processes all of it as input tokens.

That's exactly how practitioners describe it: "naive agent loops rebill prior context on every call, so input token cost grows quadratically as tool outputs and reasoning traces accumulate" [Augmentcode](https://www.augmentcode.com/guides/ai-agent-loop-token-cost-context-constraints).

The consequence is a brutal multiplier. The same analysis found that "a 20-step loop can consume over 10x the tokens a simple per-step estimate suggests" [Augmentcode](https://www.augmentcode.com/guides/ai-agent-loop-token-cost-context-constraints). Your spreadsheet says 20 calls * 2K tokens. Reality says 420K tokens - because by call 20, the context is 40K tokens deep and every one of the 20 calls paid to re-read it.

## The math: $$O(N^²)$$, and why your per-step estimate is always wrong

Let's make it concrete. Suppose each interaction step adds a net *k* new tokens (tool output, the model's action, the observation) to the context window, and the agent runs *N* steps in a naive ReAct loop with no compaction or caching.

At step *t*, the context window contains roughly *t·k* tokens - and prefill processes all of them. So the total token operations across the run is:

$$\sum_{t=1}^{N} t \cdot k = \frac{kN(N+1)}{2} \approx \mathcal{O}(kN^2)$$

That sum is the classic triangle number. Step 1 costs *k*. Step 10 costs 10k. Step 50 costs 50k - and the run as a whole costs ~1,275k, not 50k. The width of every rectangle in the cost picture is the number of tokens, and the total area grows with the square of the conversation length - the same framing used in the widely-shared "Expensively Quadratic" analysis of the LLM agent cost curve [exe.dev](https://blog.exe.dev/expensively-quadratic).

### A worked example (illustrative, using $3 per million input tokens)

Assume k = 2,000 net new tokens per step, input pricing of $$\$3$$ per million tokens - in the range of current frontier model pricing of roughly $$\$2.50-\$5$$ per million input tokens [Waxell](https://waxell.ai/blog/ai-agent-context-window-cost), and consistent with models like Claude Sonnet at $3 input / $15 output per million tokens [IntuitionLabs](https://intuitionlabs.ai/articles/claude-pricing-plans-api-costs):

| Steps (N) | Cumulative input tokens | Cumulative input cost | Naive estimate (N * k) | Multiplier |
|---|---|---|---|---|
| 5 | 30K | $0.09 | 10K | 3* |
| 10 | 110K | $0.33 | 20K | 5.5* |
| 20 | 420K | $1.26 | 40K | 10.5* |
| 50 | 2.55M | $7.65 | 100K | 25.5* |

The last row is the punchline: a "50-step agent" that looks like a 100K-token job on paper is actually a 2.5-million-token job. And this only counts input. Output tokens - which typically cost 4-8* more per million than input - sit on top of this. (One caution: these figures use $3/1M as a stand-in rate; always price against your actual model and provider.)

## Two different quadratics - don't conflate them

A point worth pinning down precisely, because it changes what you can fix and what you can't:

1. **The billing quadratic (fixable).** Cumulative token *spend* grows as O(N²) because the harness re-sends the full transcript every turn. This is an architecture decision, and it's the one this post is about.
2. **The attention quadratic (inherent, per-call).** Within any single call, self-attention computes relationships between every pair of tokens, so per-call compute grows roughly O(n²) with context length n. You can't engineer that away - but it's a per-call property, not the reason your cumulative bill explodes.

Blaming "the context window" or the model for the cost blowup misses the point. The transcript-resending behavior lives in *your* loop, which means the biggest lever is also *yours* to pull.

## Why the bill gets worse: long contexts + real pricing

Two forces compound the quadratic. First, context windows have grown enormous - commonly exceeding 200K tokens in 2026 [Waxell](https://waxell.ai/blog/ai-agent-context-window-cost) - which means agents rarely hit a hard wall that would otherwise force you to manage context. The loop just keeps appending.

Second, output-to-input price ratios amplify everything downstream: current frontier pricing runs from roughly $1 to $25 per million tokens depending on model and token type [Metacto](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration), with output tokens consistently the expensive side. A bloated transcript inflates the input side of every single call - and the input side is where the quadratic lives.

## The fix: stop re-reading what you've already read

If the quadratic comes from re-processing the same prefix of tokens every call, the fix is to not re-process it. That's exactly what **KV-caching** and **prefix caching** do.

The mechanism: a transformer converts each input token into key/value (KV) tensors during prefill. If the first 38K tokens of this call are identical to the first 38K tokens of the last call - and in an agent loop, they almost always are - those KV tensors can be reused instead of recomputed.

The savings are dramatic and verified:

- **Cache-hit input tokens cost 80-90% less than cache-miss tokens** [GMI Cloud](https://www.gmicloud.ai/en/blog/kv-cache-optimization-for-llm-inference-how-cache-aware-serving-reduces-cost-and-latency).
- OpenAI's prompt caching discounts reused input tokens **up to 90%** off the standard input rate [OpenAI](https://developers.openai.com/api/docs/guides/prompt-caching) - for example, GPT-5 mini bills cached input at $0.125 per million versus $1.25 standard [OpenAI Community](https://community.openai.com/t/understanding-gpt-5-mini-pricing-confusion-total-output-tokens-missing-bug/1345700).
- Anthropic's prompt caching prices cache reads at roughly **10% of the input rate** - e.g., $0.30 per million against Sonnet's $3 per million standard input [Metacto](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration), [PE Collective](https://pecollective.com/tools/claude-pricing-guide/).
- At the infrastructure level, "a 90% KV cache hit rate means the server skips 90% of that prefill work, reducing effective compute cost per request by 80-90%" [Spheron](https://www.spheron.network/blog/context-engineering-production-ai-agents-kv-cache-long-context/).

### The engineering rules that make caching actually work

Caching isn't automatic magic - providers match on exact token prefixes, and any change early in the sequence invalidates everything after it. Three rules follow:

1. **Keep the system prompt and tool definitions byte-stable** at the front of the context. A timestamp or a shuffled tool list at position 100 busts the cache for the remaining 40,000 tokens.
2. **Append, don't rewrite.** Stable-prefix design - where each call's context is the previous context plus new tokens - is what makes agent loops cache-friendly by construction.
3. **Watch cache-write premiums.** Some providers charge a premium on cache writes (Anthropic, for instance, applies a 1.25*-2* write premium depending on cache lifetime [TechSpire](https://technspire.com/en/blog/anthropic-prompt-caching-pricing-mechanics)). That's still overwhelmingly favorable for long transcripts - a one-time premium versus a recurring quadratic - but it belongs in your cost model.

The honest framing: caching doesn't repeal the quadratic - it changes the *constant* on it by roughly an order of magnitude. For most agent workloads, that converts an unviable cost curve into a manageable one.

## What to do next (practical checklist)

- **Log `cached_tokens` separately** from total input tokens on every call. Your true cost trend is the cache-*miss* input volume, not the raw input count.
- **Set a context budget per task.** If a task type routinely runs past ~30-50 steps, the quadratic is working against you structurally, not incidentally.
- **Structure prompts for prefix stability.** Static instructions first, volatile content last - this is cache engineering as much as prompt engineering.
- **Consider context management deliberately, not automatically.** Compaction (summarizing older turns to shrink the context) reduces the quadratic's base, but it carries its own serious risk - it's how agents *silently lose* their own safety rules. That failure mode deserves its own post: [how context compaction makes agents forget rules](https://blog.sijanb.com.np/articles/2026/09/context-compaction-agent-forgets-rules/)

## FAQ

**Why do LLM agent costs grow quadratically?**
Because the model is stateless: every step re-sends the full transcript, so the tokens billed at step *t* are proportional to *t*. Summed over *N* steps, total token operations scale as N(N+1)/2 ≈ O(N²) - quadratic in the number of steps [Augmentcode](https://www.augmentcode.com/guides/ai-agent-loop-token-cost-context-constraints).

**Is this the same as attention being O(n²)?**
No. Attention's quadratic is a per-call compute property. The agent cost quadratic is a *cumulative billing* property caused by resending history every call. The first you live with; the second you engineer away.

**How much does prompt caching actually save?**
Provider-published discounts on reused input tokens run up to 90% [OpenAI](https://developers.openai.com/api/docs/guides/prompt-caching), with Anthropic cache reads at roughly 10% of standard input price [Metacto](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration). Real-world savings depend on your cache hit rate - which is why you should be logging it.

**Does a bigger context window make my agent more expensive?**
Not by itself - but it removes the natural pressure to manage context, and with frontier input pricing at roughly $2.50-$5 per million tokens [Waxell](https://waxell.ai/blog/ai-agent-context-window-cost), an unmanaged transcript fills fast and re-bills faster.
