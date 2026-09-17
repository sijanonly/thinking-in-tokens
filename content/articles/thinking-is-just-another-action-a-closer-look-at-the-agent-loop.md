Title: Thinking Is Just Another Action: A Closer Look at the Agent Loop
Date: 2026-09-17
Category: AI Agents
Tags: ai-agents, harness, agent-loop, ReAct
Slug: thinking-is-just-another-action-a-closer-look-at-the-agent-loop
Authors: Sijan Bhandari
Summary: An LLM agent isn't the model - it's the loop: a token-predicting policy coupled to a software harness that executes tool calls and feeds observations back into a growing transcript. The piece walks through the POMDP-style formalization of that ReAct loop, flagging where it quietly breaks - lossy observations, unbounded histories, fragile long actions, and sparse rewards.


# The Formal Agent Formulation & Architecture

I sat down to write out "what an agent actually is" and immediately hit the usual problem: every definition sounds obvious until you try to pin it down, and then nothing is obvious.

## Where the definition starts, and why it feels both right and weird

The textbook definition - an agent is anything that **perceives its environment through sensors and acts on it through actuators** - is fine as far as it goes. It's Russell & Norvig's line, and it's satisfyingly general. A thermostat qualifies. A Roomba qualifies. So does, apparently, a language model wrapped in some Python.

But here's my first honest doubt: this definition is so general it barely excludes anything. A rock doesn't perceive, fine, but almost every piece of software with an event loop technically "senses" and "acts." So the definition gives me a necessary condition, not a sufficient one. What actually separates an agent from, say, a cron job? I think the answer - and this is where the modern formalization earns its keep - is that an agent's *next action depends on its accumulated history of interaction*, not just a fixed schedule or a static mapping. That's what the formalization below is really capturing.

## The modern framing: a decision process running over two moving parts

The way I've come to think about LLM-based agentic systems is as a discrete-time, Markov-like decision process - honestly, closer to a **POMDP** (partially observable MDP) than a clean MDP, and I'll push on that in a second - implemented across two distinct components:

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

I want to flag the arrows, because they're the whole story. The model only ever *emits tokens* - some of those tokens are reasoning, some are tool calls the harness recognizes as actions. And the harness only ever *appends tokens back* - the stdout of a shell command, a file diff, an error message - which become observations. Nothing in this loop "understands" the environment directly; everything is mediated by token streams in both directions. Once that clicked for me, a lot of framework marketing started looking like elaborations on this one loop.

## The formalization, piece by piece - with the places it made me uneasy

**Environment, $\mathcal{S}$** - the external state space: a code repository, a file system, a web DOM, a shell. This is the thing the agent is supposedly acting *in*. My unease: I never actually see $\mathcal{S}$. I see observations of it. And in the shell case especially, the state is enormous and mostly hidden - what's in memory, what background jobs are running, what the last command mutated.

**Observation, $o_t \in \mathcal{O}$** - the context token sequence received at time $t$: stdout, file diffs, DOM trees, tool execution results. This is where the "POMDP" label stops being pedantry and starts being load-bearing. Is a shell observable? Definitely not fully - I can run `ls` and get a partial, lossy view; the observation is a *projection* chosen by whoever wrote the tool wrapper. And the projection is lossy in a way that matters: a diff tells me what changed, not why, and a truncated stdout tells me the beginning of the story only. So the agent is reasoning from a filtered channel, and the filter is a design decision, not a law of nature. That's an underappreciated degree of freedom.

**Trajectory history, $h_t \in \mathcal{H}$** - the accumulated sequence of prompts, reasoning traces, actions, and observations:

$$h_t = (o_0, a_0, o_1, a_1, \dots, o_t)$$

This is the object I actually care about, more than $\mathcal{S}$. Everything the model conditions on lives here. Which raises a question I don't have a clean answer to: is the trajectory the state, or a summary of the state? In the strict POMDP picture, the belief state is a distribution over $\mathcal{S}$; here, the "belief state" is literally just... a growing transcript. We do belief-state representation by writing. It works embarrassingly often, and I can't fully articulate why compression-to-prose preserves what matters. There's also a practical tension: $h_t$ grows without bound while the context window doesn't, so real harnesses truncate, summarize, or cache - and each of those interventions is a place where information silently leaves the system.

**Policy, $\pi_\theta$** - an autoregressive LLM, parameters $\theta$, predicting a distribution over action tokens conditioned on the history:

$$\pi_\theta(a_t \mid h_t) = \prod_{k=1}^{|a_t|} P_\theta\!\left(t_{t,k} \mid h_t,\; t_{t,1}, \dots, t_{t,k-1}\right)$$

I like that this equation is honest: it's just next-token prediction, iterated over the length of the action. No magic inside the model - the "agent-ness" is not in $\pi_\theta$ at all. The factorization also quietly tells you something about error behavior: the whole action is a product of token probabilities, so an action's likelihood decays multiplicatively with its length. Long, precise tool calls are inherently fragile in a way short ones aren't. That's a free insight from just reading the equation carefully, and it matches what I see in practice - models write beautiful three-paragraph plans and then drop a closing brace.

**Action, $a_t \in \mathcal{A}$** - the generated tokens that serialize intent, and there are exactly three kinds: an intermediate **chain-of-thought** reasoning trace, a structured **tool call**, or a **termination call**. What strikes me here is that CoT is an action too. It does nothing to the environment - it's an action whose entire effect is on $h_{t+1}$, on the agent's own future context. Thinking is writing yourself a better observation, in a sense. Once I framed it that way, "reasoning tokens" stopped feeling like a separate category. Though I'll admit a lingering doubt: is CoT always *meaningful* action, or sometimes just the model filling space because the harness template asked for a thought first? Probably both, depending on the step.

**Reward, $r_t \in \mathcal{R}$** - a scalar score assigned at trajectory termination or intermediate steps: binary unit-test pass/fail, $r \in \{0, 1\}$; LLM-as-a-judge rubric scores; human feedback. This is the piece I trust least. Sparse binary rewards are clean but blind - a fail gives you no gradient toward *what went wrong*. LLM-as-a-judge is dense but gameable and noisy, and I keep asking myself: if the judge is another LLM, aren't we just measuring one policy against another policy's priors? The honest answer is that reward design here is doing a lot of quiet work, and nobody has settled it.

## The engine vs. harness separation - the insight I'd actually keep from this lesson

The claim I'd underline, because it corrected a confusion I had for a long time: **a raw LLM is just a token-predicting machine, not an agent.** Nothing about the weights knows what a file system is or how to run `bash`. Agentic behavior *emerges from the coupling* of two layers:

- **The Model (Policy Engine):** generates candidate thought-and-action token sequences conditioned on $h_t$.
- **The Harness (System Control Loop):** the software wrapper - think OpenHands or mini-swe-agent - responsible for:
  1. maintaining the context history $h_t$ and enforcing prompt templates;
  2. parsing and validating the tool-call tokens the model emits;
  3. interfacing with the sandbox environment to execute side effects - running bash scripts, modifying files;
  4. returning execution outputs as new observation tokens appended to $h_t$.

Reading that list, though, I have to be honest about a boundary that's blurrier than it looks. Duty 1 - maintaining $h_t$ - is partly a *model* concern too, because what the model attends to shapes the effective history, not just the raw bytes stored. And duty 2 - validation - sits awkwardly in the middle: is rejecting a malformed tool call an environment observation ("your call failed, here's the parse error") or a harness policy decision ("you don't get to try that")? Both readings are defensible, and which one you pick changes how you'd train the thing. Where exactly the model ends and the harness begins is, I've concluded, a convention - a useful one, but a convention. Someone could build the same system with the responsibilities split at a different line and it would still deserve the name "agent."

## The ReAct loop, seen from inside

Put it all together and you get the standard **ReAct** (Reasoning + Acting) loop:

1. the model generates reasoning tokens (a scratchpad),
2. then action tokens;
3. the harness parses and executes the action;
4. the harness appends the observation to $h_t$;
5. repeat until a termination call.

It's almost embarrassingly simple when written out - a while loop with a language model inside. But the simplicity is deceptive, because every real failure I've debugged lives at one of the seams this formulation exposes: observations too lossy for the model to recover from (the POMDP bite), histories too long to fit (the $h_t$ problem), actions too long to be emitted reliably (the policy factorization), or rewards too sparse to learn from (the $r_t$ problem).

## Questions I'm deliberately leaving open

- If the agent's "belief state" is just a prose transcript, what exactly gets lost under context compression - and can we ever know without a ground-truth $\mathcal{S}$ to compare against?
- Is the Markov assumption even approximately true here? $o_{t+1}$ depends on the *entire* environment history, not just $h_t$ - a file changed by a process the agent started ten steps ago still shows up in observations. So we're really in a non-Markov setting that we *pretend* is Markovian by stuffing history into the context. It works. I'd like to understand why.
- And the one I keep circling: when agentic behavior "emerges from the coupling," is the unit of agency the model-plus-harness system, or is it incoherent to ask? The formalism treats the harness as environment-side scaffolding, but the harness also holds the memory, the tools, and half the policy's effective context. Maybe the right unit of analysis is the loop itself.

That last question isn't rhetorical. I suspect how you answer it determines whether you spend your improvement budget on better models or better harnesses - and the current evidence says the harness budget is underspent.
