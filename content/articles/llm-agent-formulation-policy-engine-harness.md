Title: What Actually Makes an LLM an Agent: The Formal Formulation, Policy Engine, and Harness
Date: 2026-09-17
Category: AI Agents
Tags: llm-agents, agent-architecture, pomdp
Slug: llm-agent-formulation-policy-engine-harness
Authors: Sijan Bhandari
Summary: A working formalization of LLM agents as a POMDP split into policy engine and harness, with the doubts and failure seams the math exposes.

---

## Where the Definition Starts, and Why It Feels Both Right and Weird

I sat down to write out "what an agent actually is" and immediately hit the usual problem: every definition sounds obvious until you try to pin it down, and then nothing is obvious.

The textbook definition, an agent is anything that **perceives its environment through sensors and acts on it through actuators**, is fine as far as it goes. It's Russell & Norvig's line, and it's satisfyingly general. A thermostat qualifies. A Roomba qualifies. So does, apparently, a language model wrapped in some Python.

But here's my first honest doubt: this definition is so general it barely excludes anything. A rock doesn't perceive, fine, but almost every piece of software with an event loop technically "senses" and "acts." The definition gives me a necessary condition at best. What actually separates an agent from, say, a cron job?

I think the answer, and this is where the modern formalization earns its keep, is that an agent's *next action depends on its accumulated history of interaction*, rather than a fixed schedule or a static mapping. That's what the formalization below is really capturing.

## The Modern Framing: A Decision Process Running Over Two Moving Parts

The way I've come to think about LLM-based agentic systems is as a discrete-time, Markov-like decision process. Honestly, it's closer to a **POMDP** (partially observable MDP) than a clean MDP, and I'll push on that in a second. It's implemented across two distinct components:

- the **Language Model Policy Engine**, and
- the **Software Harness**.

The architecture looks roughly like this:

```
                 +---------------------------------------+
                 |            Harness Engine             |
                 |  (State, Dispatch, Validation, Cache) |
                 +-------------------+-------------------+
                                     |
                   Appends Tokens    |   Emits Tool
                   (Observations)    |   Calls (Actions)
                                     v
                 +-------------------+-------------------+
                 |    LLM Policy Engine  π_θ(a_t | h_t)  |
                 |     (Next-Token Prediction & CoT)     |
                 +---------------------------------------+
```

I want to flag the arrows, because they're the whole story. The model only ever *emits tokens*. Some of those tokens are reasoning, some are tool calls the harness recognizes as actions. The harness only ever *appends tokens back*: the stdout of a shell command, a file diff, an error message, which become observations. Nothing in this loop "understands" the environment directly; everything is mediated by token streams in both directions. Once that clicked for me, a lot of framework marketing started looking like elaborations on this one loop.

## The Formalization, Piece by Piece, With the Places It Made Me Uneasy

### Environment, $\mathcal{S}$

The external state space: a code repository, a file system, a web DOM, a shell. This is the thing the agent is supposedly acting *in*. My unease: I never actually see $\mathcal{S}$. I see observations of it. In the shell case especially, the state is enormous and mostly hidden. What's in memory, what background jobs are running, what the last command mutated.

### Observation, $o_t \in \mathcal{O}$

The context token sequence received at time $t$: stdout, file diffs, DOM trees, tool execution results. This is where the "POMDP" label stops being pedantry and starts being load-bearing. Is a shell observable? Definitely not fully. I can run `ls` and get a partial, lossy view; the observation is a *projection* chosen by whoever wrote the tool wrapper.

And the projection is lossy in a way that matters. A diff tells me what changed, and the *why* stays invisible. A truncated stdout gives me the beginning of the story only. So the agent is reasoning from a filtered channel, and the filter is a design decision, not a law of nature. That's an underappreciated degree of freedom. If you're building harnesses, the wrapper you write around each tool is doing more to shape the agent's competence than most model choices.

### Trajectory History, $h_t \in \mathcal{H}$

The accumulated sequence of prompts, reasoning traces, actions, and observations:

$$h_t = (o_0, a_0, o_1, a_1, \dots, o_t)$$

This is the object I actually care about, more than $\mathcal{S}$. Everything the model conditions on lives here. Which raises a question I don't have a clean answer to: is the trajectory the state, or a summary of the state? In the strict POMDP picture, the belief state is a distribution over $\mathcal{S}$; here, the "belief state" is literally just... a growing transcript. We do belief-state representation by writing. It works embarrassingly often, and I can't fully articulate why compression-to-prose preserves what matters.

There's also a practical tension. $h_t$ grows without bound while the context window doesn't, so real harnesses truncate or summarize or cache. Each of those interventions is a place where information silently leaves the system, and none of them come with a guarantee about *which* information left.

### Policy, $\pi_\theta$

An autoregressive LLM, parameters $\theta$, predicting a distribution over action tokens conditioned on the history:

$$\pi_\theta(a_t \mid h_t) = \prod_{k=1}^{|a_t|} P_\theta\!\left(t_{t,k} \mid h_t,\; t_{t,1}, \dots, t_{t,k-1}\right)$$

I like that this equation is honest: it's just next-token prediction, iterated over the length of the action. No magic inside the model. The "agent-ness" lives somewhere else entirely, which I'll get to below.

The factorization also quietly tells you something about error behavior. The whole action is a product of token probabilities, so an action's likelihood decays multiplicatively with its length. Long, precise tool calls are inherently fragile in a way short ones aren't. That's a free insight from just reading the equation carefully, and it matches what I see in practice: models write beautiful three-paragraph plans and then drop a closing brace. If you're debugging an agent that keeps failing on long structured outputs, the math already predicted it.

### Action, $a_t \in \mathcal{A}$

The generated tokens that serialize intent, and there are exactly three kinds: an intermediate **chain-of-thought** reasoning trace, a structured **tool call**, or a **termination call**. What strikes me here is that CoT is an action too. It does nothing to the environment. It's an action whose entire effect is on $h_{t+1}$, on the agent's own future context. Thinking is writing yourself a better observation, in a sense. Once I framed it that way, "reasoning tokens" stopped feeling like a separate category.

Though I'll admit a lingering doubt: is CoT always *meaningful* action, or sometimes just the model filling space because the harness template asked for a thought first? Probably both, depending on the step.

### Reward, $r_t \in \mathcal{R}$

A scalar score assigned at trajectory termination or intermediate steps: binary unit-test pass/fail, $r \in \{0, 1\}$; LLM-as-a-judge rubric scores; human feedback. This is the piece I trust least.

Sparse binary rewards are clean but blind. A fail gives you no gradient toward *what went wrong*. LLM-as-a-judge is dense but gameable and noisy, and I keep asking myself: if the judge is another LLM, aren't we just measuring one policy against another policy's priors? The honest answer is that reward design here is doing a lot of quiet work, and nobody has settled it. If someone shows you a benchmark score, the reward function behind it deserves as much scrutiny as the model.

## The Engine vs. Harness Separation: The Insight I'd Actually Keep

The claim I'd underline, because it corrected a confusion I had for a long time: **a raw LLM is just a token-predicting machine, not an agent.** Nothing about the weights knows what a file system is or how to run `bash`. Agentic behavior *emerges from the coupling* of two layers:

- **The Model (Policy Engine):** generates candidate thought-and-action token sequences conditioned on $h_t$.
- **The Harness (System Control Loop):** the software wrapper, think OpenHands or mini-swe-agent, responsible for:
  1. maintaining the context history $h_t$ and enforcing prompt templates;
  2. parsing and validating the tool-call tokens the model emits;
  3. interfacing with the sandbox environment to execute side effects, like running bash scripts and modifying files;
  4. returning execution outputs as new observation tokens appended to $h_t$.

### Where the Boundary Blurs

Reading that list, though, I have to be honest about a boundary that's blurrier than it looks. Duty 1, maintaining $h_t$, is partly a *model* concern too, because what the model attends to shapes the effective history, not just the raw bytes stored. Duty 2, validation, sits awkwardly in the middle: is rejecting a malformed tool call an environment observation ("your call failed, here's the parse error") or a harness policy decision ("you don't get to try that")? Both readings are defensible, and which one you pick changes how you'd train the thing.

Where exactly the model ends and the harness begins is, I've concluded, a convention. A useful one, but a convention. Someone could build the same system with the responsibilities split at a different line and it would still deserve the name "agent."

## The ReAct Loop, Seen from Inside

Put it all together and you get the standard **ReAct** (Reasoning + Acting) loop:

1. the model generates reasoning tokens (a scratchpad),
2. then action tokens;
3. the harness parses and executes the action;
4. the harness appends the observation to $h_t$;
5. repeat until a termination call.

It's almost embarrassingly simple when written out. A while loop with a language model inside. But the simplicity is deceptive, because every real failure I've debugged lives at one of the seams this formulation exposes:

- observations too lossy for the model to recover from (the POMDP bite),
- histories too long to fit (the $h_t$ problem),
- actions too long to be emitted reliably (the policy factorization),
- rewards too sparse to learn from (the $r_t$ problem).

The formulation is worth keeping precisely because it makes those failure modes legible. Each seam maps to a component, and each component maps to a place you can spend engineering effort.

## Questions I'm Deliberately Leaving Open

- If the agent's "belief state" is just a prose transcript, what exactly gets lost under context compression, and can we ever know without a ground-truth $\mathcal{S}$ to compare against?
- Is the Markov assumption even approximately true here? $o_{t+1}$ depends on the *entire* environment history, not just $h_t$. A file changed by a process the agent started ten steps ago still shows up in observations. So we're really in a non-Markov setting that we *pretend* is Markovian by stuffing history into the context. It works. I'd like to understand why.
- And the one I keep circling: when agentic behavior "emerges from the coupling," is the unit of agency the model-plus-harness system, or is it incoherent to ask? The formalism treats the harness as environment-side scaffolding, but the harness also holds the memory, the tools, and half the policy's effective context. Maybe the right unit of analysis is the loop itself.

That last question isn't rhetorical. I suspect how you answer it determines whether you spend your improvement budget on better models or better harnesses, and the current evidence says the harness budget is underspent.

---

### FAQ

**Q: Why is an LLM agent a POMDP instead of a plain MDP?**
Because the agent never observes the true environment state $\mathcal{S}$. It receives $o_t$, a lossy projection produced by tool wrappers like `ls`, diffs, or truncated stdout. When observations don't reveal the full state, the decision process is partially observable, so the agent has to reason from a filtered channel and maintain its own belief about what the environment actually looks like.

**Q: Is a raw LLM an agent on its own?**
No. The weights are a policy that predicts tokens conditioned on a history. They contain no knowledge of file systems, shells, or how to execute side effects. Agentic behavior emerges from coupling the model with a harness that stores history, parses tool calls, executes them against a sandbox, and appends the results back as observations.

**Q: Why do long tool calls fail more often than short ones?**
The policy factorizes an action as a product of token probabilities. Each additional token multiplies the action's total likelihood, so probability decays with length. A 500-token structured call has many more chances for one malformed character than a 10-token call, which is why models that plan eloquently still drop closing braces.

**Q: What actually separates an agent from a cron job or an event loop?**
The defining property is that the next action depends on the accumulated history of interaction. A cron job fires on a fixed schedule or static mapping regardless of what happened before. An agent conditions every decision on $h_t$, its full trajectory of prompts, reasoning, actions, and observations, so its behavior changes as the interaction accumulates.
