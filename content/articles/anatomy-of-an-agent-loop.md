Title: The Anatomy of an Agent Loop: Why One LLM Call Is Not Enough
Date: 2026-09-24
Category: AI Agents
Tags: ai-agents, agent-loop, llm-tool-use
Slug: anatomy-of-an-agent-loop
Authors: Sijan Bhandari
Summary: The anatomy of an LLM agent loop: POMDP framing, the five stages, step budgets, and why one reply must be an action or a final answer, not both.


An LLM can write a plausible answer in one go. An **agent** goes further: it can take an action, observe what happened, and use that result to choose its next step. The key idea is a feedback loop between the model and the outside world. Interleaving reasoning traces with actions is what turned a text generator into something that can hold a task open across many turns [ReAct](https://arxiv.org/abs/2210.03629).

## 1. Why a single LLM call can fall short

An autoregressive Large Language Model (LLM), parameterized by \(\theta\), models the conditional probability \(P_\theta(x_t \mid x_{<t})\) over a vocabulary. A single forward pass produces a string of tokens, but a string alone cannot complete every real-world task.

Consider "remove debug statements from a codebase and verify the unit tests." A single response can suggest what to do. It cannot by itself make the changes, run the tests, or adapt to a failure. Four limits explain why:

- **It cannot act on its own.** Text that describes a code edit is not the same as changing a file.
- **It has a limited view of the conversation.** The context window has length \(L\); it cannot hold an unlimited history.
- **It cannot correct itself from runtime feedback unless the system provides it.** If a command fails, the model needs to see that failure before it can respond to it.
- **Its learned knowledge is not live access to the world.** Current files, running processes, and fresh external information must be retrieved or inspected when needed.

**Everyday analogy:** a single-turn LLM is like someone giving directions from memory. An agent is more like someone who can check the map, take a turn, see where they ended up, and adjust.

That observe-act-adjust pattern is the part most agent frameworks are actually built around, whether they call it a loop, a harness, or a graph of steps [Oracle](https://blogs.oracle.com/developers/what-is-the-ai-agent-loop-the-core-architecture-behind-autonomous-ai-systems) [Hugging Face](https://huggingface.co/learn/agents-course/en/unit1/agent-steps-and-structure).

## 2. The agent as a POMDP

A useful formal model is a **Partially Observable Markov Decision Process (POMDP)**:

\[
(\mathcal{S}, \mathcal{A}, \mathcal{O}, \mathcal{T}, \Omega, \mathcal{R}, \gamma)
\]

Think of the agent as working in a world it can only inspect through partial clues, such as tool outputs, rather than seeing every detail directly. The formal definition treats the agent as unable to observe the underlying system state directly and acting on a belief over that state [POMDP](https://en.wikipedia.org/wiki/Partially_observable_Markov_decision_process). The same framing has been pushed as a design lens for LLM applications generally, not only for classic robotics [TensorZero](https://www.tensorzero.com/blog/think-of-llm-applications-as-pomdps-not-agents/).

- **Environment state space \(\mathcal{S}\):** the true state of the outside world, such as file contents or active processes. The agent may not see all of it.
- **Action space \(\mathcal{A}\):**
  \[
  \mathcal{A} = \mathcal{A}_{\text{tool}} \cup \mathcal{L}_{\text{thought}} \cup \{a_{\text{final}}\}
  \]
  Actions can be executable tool calls, internal reasoning traces, or a signal that the agent is finished.
- **Observation space \(\mathcal{O}\):** information returned by the environment, such as standard output, errors, or search results.
- **Context history \(c_t\):** what the agent has been told and what it has observed so far:
  \[
  c_t = (g, a_1, o_1, a_2, o_2, \dots, a_{t-1}, o_{t-1})
  \]
  Here, \(g\) is the user's goal; the history records earlier actions and their observations.
- **Policy \(\pi_\theta\):** the model's rule for choosing its next action, given the history:
  \[
  a_t \sim \pi_\theta(a_t \mid c_t)
  \]
- **Transition dynamics \(\mathcal{T}\):** how an action changes the environment:
  \[
  \mathcal{T}(s_{t+1} \mid s_t, a_t)
  \]

The tuple also includes \(\Omega\), \(\mathcal{R}\), and \(\gamma\). In the usual POMDP interpretation, these describe the observation model, reward, and discount factor, respectively. The provided formulation names them but does not specify their particular values or definitions for this agent.

## 3. The five stages of the loop

The cycle can be written as:

\[
\text{Observation } o_t \xrightarrow{\text{Perception}} \text{Context } c_t \xrightarrow{\text{Decision } \pi_\theta} \text{Action } a_t \xrightarrow{\text{Execution } \mathcal{E}} \text{Feedback } o_{t+1} \xrightarrow{\text{Termination Check } \mathcal{X}} \text{Next Step}
\]

In plain language:

1. **Perception:** Collect the goal and the available observations into context \(c_t\).
2. **Decision:** Use the current context to select the next thought or action, according to \(a_t \sim \pi_\theta(\cdot \mid c_t)\).
3. **Action execution:** A parser identifies the tool and its arguments; the execution layer runs the action using \(\mathcal{E}(a_t)\).
4. **Feedback:** Add the resulting output, or the runtime exception, as a new observation \(o_{t+1}\) in the conversation.
5. **Termination check:** Apply \(\mathcal{X}(a_t)\). Stop if \(a_t = a_{\text{final}}\) or the maximum step budget \(T_{\text{max}}\) has been reached; otherwise continue.

```text
Goal + prior observations
          │
          ▼
   Perception / context c_t
          │
          ▼
   Decision π_θ → action a_t
          │
          ▼
   Execution E(a_t) in the world
          │
          ▼
   Observation o_{t+1} / error
          │
          └────────── back into context
                         │
                stop if final or
                T_max reached
```

The key difference from a one-off answer is the return path: tool output becomes new context for the next decision. The loop pattern holds whether one agent runs alone or several are wired into a graph, which is why "loop" and "graph" descriptions of the same system keep colliding [Inngest](https://www.inngest.com/blog/agent-loop-architecture).

## 4. The loop's core and its add-ons

A minimal agent loop needs three things: **an LLM, a tool registry, and a message context**. Other capabilities can be attached to make that loop more useful or reliable:

- **Memory (L11):** Helps manage limited context by keeping a short-term message history and, potentially, information in external stores.
- **Planning (L5):** Breaks a larger goal into smaller tasks or considers possible action sequences before acting.
- **Verification (L3):** Checks whether an action or result meets some criterion, for example whether unit tests pass.

The labels **L11**, **L5**, and **L3** are retained as supplied; their specific meaning is not defined in the description.

**Practical implication:** these add-ons do not replace the basic loop. They improve what the loop can remember, how it chooses steps, or how it checks the result.

## 5. What the Python example does

The provided implementation represents the loop with a `brain`, a dictionary of `tools`, and a list of `messages`. Each call to `step()` asks the brain for a reply, parses that reply, then either returns a final answer or runs a tool and adds its observation. `run()` starts with the task and repeats up to `max_steps`.

```python
class AgentLoop:
    def __init__(self, brain, tools):
        self.brain = brain        # Callable: π_θ(messages) -> string reply
        self.tools = tools        # Registry dict: {"tool_name": callable_fn}
        self.messages = []        # Context History c_t

    def step(self):
        # 1. Decision
        reply = self.brain(self.messages)
        self.messages.append({"role": "assistant", "content": reply})
        
        # 2. Parse Action & Termination Check
        kind, action, payload = parse_response(reply)
        if kind == "final":
            return True, payload  # Halts loop
        
        # 3. Execution & Feedback
        if action is not None:
            tool_name, args = action
            observation = self.tools[tool_name](args)
            self.messages.append({"role": "user", "content": f"Observation: {observation}"})
            
        return False, None

    def run(self, task, max_steps=10):
        self.messages = [{"role": "user", "content": task}]
        for _ in range(max_steps):
            is_final, output = self.step()
            if is_final:
                return output
        return "Error: Step budget exhausted."
```

**One important design detail:** this example assumes `parse_response(reply)` can classify the response as either final or an action. It does not specify how to handle a reply containing both.

That parse step is exactly where the loop is most brittle. Asking a model to emit free text and then guessing the intent with a regex is the failure mode that schema-constrained output was built to remove: the response is forced to conform to a supplied JSON Schema instead of being interpreted after the fact [OpenAI](https://openai.com/index/introducing-structured-outputs-in-the-api/) [Structured Outputs guide](https://developers.openai.com/api/docs/guides/structured-outputs).

## 6. Diagnostic exercise: action and final answer in one turn

**Scenario:** The agent emits both `execute_sql(...)` and "Final Answer: The total revenue is $5M" in the same output.

### What goes wrong if the parser stops at the final answer?

If the parser immediately returns the final answer, `execute_sql(...)` never runs. The system may report a result that was supposed to come from the query, even though the query did not happen. The conversation then claims completion while the environment remains unchanged, or at least unverified.

That creates a **state inconsistency**: the answer implies that work occurred, but the tool action was skipped. If some other part of the system executes the action independently, ordering can become unclear as well: the answer might be accepted before the action's result or error is known.

### What ordering makes the outcome deterministic?

Use a clear protocol: **a response may request an action or provide a final answer, but not both.** Treat a combined action-and-final response as invalid or ambiguous. If the action is present, execute it, record its observation (or exception), and ask the model for its next response using that updated context. Only accept a final answer on a later turn that contains no pending action.

In sequence:

```text
Generate reply
    ↓
Parse and validate: action OR final, not both
    ↓
If action: execute it
    ↓
Append observation or exception to messages
    ↓
Generate the next reply from updated messages
    ↓
If final: return it and halt
```

This rule makes the sequence deterministic: the environment action happens before the agent can finalize based on its result. It also gives the model a chance to revise its answer if execution fails.

Strict schemas help here, but they are not a guarantee of correct behavior. Function-calling benchmarks exist precisely because models still fail to produce valid, correctly chosen calls even under constrained decoding [Berkeley Function Calling Leaderboard](https://openreview.net/pdf?id=2GmDdhBdDk). Treat schema enforcement as a floor, not a proof of correctness.

## 7. What this means in practice

For a code-editing task, the loop can inspect files, make a change, run tests, read any failure output, and try a correction. For information gathering, it can search, inspect the returned evidence, and refine what it looks for next.

The practical benefit is narrower than "the agent gets smarter." It is that decisions can be **grounded in new observations**, and outcomes can be checked rather than merely asserted.

## 8. Tradeoffs and open questions

- **More capability, more moving parts:** parsers, tools, context management, and termination checks can each fail.
- **Actions may have side effects:** a tool call can alter files or systems. The loop needs clear rules for authorization, retries, and error handling.
- **More turns cost time:** feedback and verification improve reliability, but add steps.
- **Verification needs a standard:** "tests passed" is meaningful only if the right tests ran and their results were interpreted correctly.
- **Ambiguous outputs need a policy:** the combined action-and-final case illustrates why a strict response format can matter as much as the model's reasoning.

The loop has its own failure modes, and they are well documented. When a tool call fails, a reasoning trace can degrade into an infinite action loop or repeat the same failing step [ReWOO](https://arxiv.org/abs/2305.18323). That is common enough that static analysis tools now target runaway agent loops in real projects directly [IAL-Scan](https://arxiv.org/html/2607.01641v1).

A useful rule of thumb: **let the agent report success only after the relevant action has run and its result has been observed.**

---

### FAQ

**What is an agent loop in one sentence?**
A repeating cycle where the model reads the current context, chooses a tool action or a final answer, executes the action if one was chosen, and feeds the result back into the context for the next decision.

**Why model an LLM agent as a POMDP instead of just a while loop?**
The loop describes control flow; the POMDP describes what the agent can know. The agent never sees the true environment state directly, only observations such as stdout or an error string, so it acts on a belief rather than on ground truth. That distinction is what makes hidden state, partial feedback, and irreversible actions meaningful design concerns.

**What should happen if the model returns an action and a final answer in the same turn?**
Treat it as invalid or ambiguous. Execute the pending action first, append its observation or exception, and require a later turn to produce the final answer. Accepting the final answer immediately risks reporting a result the environment never produced.

**How does an agent know when to stop?**
Two checks: the action is an explicit final signal (\(a_{\text{final}}\)), or the step budget \(T_{\text{max}}\) is exhausted. The budget matters because a failing tool can otherwise keep the loop spinning. The Python example returns `"Error: Step budget exhausted."` when `max_steps` runs out, which is a hard stop rather than a success.

**Does adding memory, planning, or verification replace the basic loop?**
No. Those layers change what the loop can remember, how it picks a step, or how it judges a result. The three core pieces, an LLM, a tool registry, and a message context, still carry every turn.
