Title: Long-Context and State Management for AI Agents
Date: 2026-09-23
Category: AI Agents
Tags: ai-agents, llm-inference, context-management
Slug: long-context-state-management-ai-agents
Authors: Sijan Bhandari
Summary:  Learn why long-running AI agents slow down, and how prefix caching, RoPE scaling, and context compaction affect latency and retrieval.

Blog Title: Why Long-Running AI Agents Slow Down with KV Caching and Context Compaction  
Slug: long-running-ai-agents-kv-cache-rope-context-compaction  
Category: AI Agents  
Meta Description: Learn why long-running AI agents slow down, and how prefix caching, RoPE scaling, and context compaction affect latency and retrieval.  
Tags: ai-agents, llm-inference, context-management


A run that lasts hours or days keeps adding tool calls, outputs, errors, and retries to its conversation history, h_t. That history can grow to tens or hundreds of thousands of tokens. The challenge is keeping the useful parts available without repeatedly paying to process the same text or burying important evidence. I'll walk through three techniques, then two failures that show why placement and ordering matter.

## Why long-running agents slow down

Picture a detective working a long case. Every note, interview transcript, and dead-end lead gets stapled into the case file. Eventually, the detective spends more time rereading the file than detecting.

Three parts of the stack deal with that growth: KV prefix caching, positional encoding, and context compaction. They solve different problems, and none makes the others unnecessary.

## How KV caching speeds up repeated agent prompts

### What prefix caching reuses

A transformer builds Key and Value representations as it processes tokens. In a multi-turn agent, each new prompt often contains the same system instructions, tool definitions, and prior history, followed by one new observation. Recomputing the shared prefix wastes work.

It's like a chef chopping the same vegetables for every bowl of stew after the vegetables were already prepared. Engines such as vLLM and SGLang can cache the KV state for shared prefixes and reuse it on later requests. SGLang's RadixAttention organizes reusable cache entries to find shared prefixes; vLLM's Automatic Prefix Caching skips computation for a matching prefix. [SGLang paper](https://par.nsf.gov/servlets/purl/10524135) [vLLM documentation](https://docs.vllm.ai/en/latest/features/automatic_prefix_caching/)

That only helps when the new request actually shares a prefix with cached work. Prefix caching reduces repeated prompt-prefill work. It doesn't remove the cost of processing new tokens or generating the response.

### Why changing an old token costs latency

Prefix caching depends on matching prompt prefixes. If the runtime rewrites an old message, changes a timestamp, or reformats a retry block, the reusable prefix ends at the first changed token, subject to the cache's block boundaries. Later blocks no longer match that prefix, so the engine has to process the unmatched remainder again.

The practical rule is simple: treat historical prompt content as immutable and append-only when possible. A timestamp or retry-format change can look cosmetic and still affect how much work the engine can reuse.

For standard full attention, the attention computation grows roughly with the square of sequence length, O(N²), because each token attends across the sequence. Prefix caching can avoid repeating shared-prefix computation across requests, but the attention work for new or unmatched text remains. [FlashAttention paper](https://arxiv.org/abs/2205.14135)

## What RoPE scaling changes in long contexts

### How rotary position embeddings work

A model needs positional information because token order matters. RoPE, or Rotary Position Embedding, applies position-dependent rotations to queries and keys, making relative position part of the attention calculation. [RoFormer paper](https://arxiv.org/abs/2104.09864)

The clock analogy helps: token 5 rotates by one amount; token 5,000 by another. But a model trained on shorter sequences may not handle positions far beyond that training range well. RoPE alone doesn't guarantee that a model can use an arbitrarily long context.

### How YaRN extends the context window

YaRN changes how RoPE frequencies are interpolated to extend a model's usable context. The paper reports extending Llama 2 models, trained with a 4,096-token context, to 128k; its 128k configuration was fine-tuned on 64k segments and evaluated beyond that length. So the example is not an 8k-to-128k extension. [YaRN paper](https://proceedings.iclr.cc/paper_files/2024/file/874a4d89f2d04b4bcf9a2c19545cf040-Paper-Conference.pdf)

I want to be honest about the tradeoff. A larger supported window doesn't mean the model uses every position equally well. Scaling RoPE addresses positional range; it doesn't solve the other ways long-context retrieval can fail.

## How to compact an agent's context

At some point, the trajectory has to shrink. I use three escalating strategies, each with a different failure mode.

### Strategy A, truncating oversized tool output

A large tool output, such as a 5,000-line git diff or log file, can be clipped mechanically. Keep the first ~50 lines and the last ~50, then preserve system instructions and recent turns.

The problem is obvious. You don't know which 4,900 lines mattered. If the bug sat on line 2,300, truncation deleted your evidence. This approach is cheap and predictable, and it's also dumb.

### Strategy B, summarizing old agent history

A secondary LLM pass can compress older history, h_{1:t-k}, into a structured snapshot with three fields:

- Goal: what the user originally asked for
- Completed sub-tasks: which tools ran and what happened
- Current state: what's pending and what comes next

Hundreds of raw tokens can collapse into a compact state block. The catch is that a summary keeps conclusions and discards evidence. If the agent later needs the exact error from turn 12 because the situation changed, that verbatim detail may be gone.

This is the least-solved problem in the stack, in my view. What to keep depends on what the future will ask for. You only learn you kept the wrong thing after the agent fails.

### Strategy C, putting old turns in external memory

Instead of keeping every old turn in the active prompt, offload it to an external vector database or key-value store. The prompt stays lean, and the agent can search the archive when it needs an old detail.

Retrieval adds another step that can fail or run slowly. The agent also has to know what to ask for, which is itself a reasoning task. Retrieval quality deserves its own post, so I'll leave that door open here.

In practice, these strategies can layer together: clip obviously verbose tool output, summarize settled history, and offload the long tail to external storage.

## Why a timestamp can break prefix caching

Suppose the runtime inserts a changing timestamp, such as "Current Time: 2026-09-17 07:04:45," in the middle of the system prompt on every turn. What happens to the KV cache?

Everything before the timestamp still matches, so that part may be reused. Tool definitions and the accumulated trajectory after it fall outside the matching prefix. On every turn, the engine must process that unmatched remainder again.

A timestamp at the very end of the full prompt would leave most of the stable prefix intact. Put dynamic content last, if it has to be in the prompt at all. The timestamp carries little information for the model, yet its placement can cut off reuse for a large part of the history. Runtime details the model never sees can dominate real agent latency.

## Why important tool output gets lost in the middle

Research on long-context models finds that performance can drop when relevant information sits in the middle of the input. In tests of multi-document question answering and key-value retrieval, performance was often strongest when the relevant fact appeared near the beginning or end. [Lost in the Middle](https://aclanthology.org/2024.tacl-1.9/)

Agent histories put a lot of tool output in exactly that middle region:

- The head holds the system prompt and the user's original goal.
- The tail holds the latest turns.
- Between them, stdout, git diffs, tool results, and error dumps accumulate.

That means the evidence of what actually happened when a tool ran may sit where retrieval is harder. A subtle error message buried mid-trajectory may be effectively invisible when the agent reasons about it later.

Compaction can make this worse. If truncation keeps the head and tail of a tool output and deletes the middle, the runtime removes some of the same content the model already struggles to retrieve. If line 2,300 in a 5,000-line output contains the bug, that detail can disappear before the agent gets another chance to inspect it.

The model won't announce that it missed the line. It may still reason confidently from an incomplete record, which looks from the outside like the agent is simply wrong.

Put critical facts near the head or tail, for example by restating a key finding at the end of a tool output. Summarize important findings before they get buried. And use external memory for bulky raw outputs that only matter occasionally.

## What I still doubt about agent memory

The caching rule extends beyond one inference engine. Keeping the prefix stable is a contract between the runtime and the engine. Break it with timestamps, adaptive formatting, or reordered messages, and the cost may show up only as an agent that feels slow.

Compaction is a judgment call dressed as a technical decision. A summary preserves the map and loses the territory. Truncation preserves the edges and loses the center. Either can leave an agent unable to recover from an early wrong conclusion.

I also doubt that memory tiering is an escape hatch. Retrieval quality becomes a new failure point. If the vector store misses the one log line that mattered, the agent fails anyway, just with a cleaner-looking prompt.

Before building anything, I'd want to know how often trajectory content actually needs retroactive editing. If the answer is rarely, append-only history gives prefix caching room to work. If it happens often, the architecture needs a different plan from day one.

## FAQ

### What invalidates an agent's KV prefix cache?

A change in earlier prompt text limits reuse to the unchanged prefix before it, and cache matching may also depend on block boundaries. A timestamp rewritten mid-prompt, a reordered message, or a reformatted retry block can all reduce how much cached work is reusable.

### Can RoPE scaling solve long-context problems by itself?

No. YaRN extends the positional range, and its paper reports Llama 2 extensions up to 128k. A bigger context window doesn't guarantee equal retrieval or reasoning quality at every position, especially for facts buried in the middle.

### Should I truncate or summarize long tool output?

Use truncation when the output is mostly repetitive and its edges are likely to be useful. Use summarization for settled history when preserving conclusions matters more than keeping every exact line. If a bulky output might be needed later, put it in external storage and retrieve it on demand.

### Why did an agent get slower after a timestamp was added?

If the timestamp sits in the middle of the prompt, the cache can only reuse the unchanged prefix before it. The engine then has to process the unmatched remainder again, including the history after that point. Moving dynamic text to the end preserves more of the stable prefix.

### What belongs in an agent's external memory?

Store bulky raw material that is too large to keep in the active prompt but may matter later, such as a long stdout log or a git diff. Keep the current goal, completed work, and pending state easy to access. Retrieval still needs to find the exact evidence the agent asks for.
