Title: How AI Agents Turn Text Into Actions: Tool Calling, JSON, CodeAct, and MCP
Date: 2026-09-22
Category: AI Agents
Tags: ai-agents, tool-calling, grammar-constrained-decoding
Slug: how-ai-agents-turn-text-into-actions
Authors: Sijan Bhandari
Summary: A model predicts tokens. Deterministic software turns them into actions. Inside grammar masking, JSON vs CodeAct, and MCP credential isolation.

## The Core Loop: Five Steps From Prediction to Action

Here's the puzzle worth sitting with for a second. A large language model is, mechanically, a very fancy autocomplete. It outputs one token at a time, each one chosen by probability. Yet somehow it reads your file, books your flight, and runs your code.

So how does a coin-flipping text machine produce a reliable, deterministic action?

The answer is the central trick of the entire field: the model never "acts." It writes text, and separate software agrees to read that text as an instruction. Everything below is the machinery that makes that agreement trustworthy enough to ship.

If you're building or debugging anything agentic, this is the mental model you need. Let's build it up piece by piece.

Most explanations of AI agents blur together two completely different halves of the system. One half is probabilistic: the model guessing words. The other half is boring, deterministic software that parses, type-checks, and executes. The magic lives in the handoff between them.

| Step | Plain Name | What Actually Happens |
| --- | --- | --- |
| 1 | Predict | The model computes a raw score (a logit) for every word in its vocabulary, the ranked list of everything it could say next. |
| 2 | Mask | A grammar engine crosses out the illegal options, setting their scores to negative infinity. |
| 3 | Emit | The model picks from only the surviving words, producing a clean tool call like `{"city":"Pgh"}`. |
| 4 | Parse and Route | Separate software reads the function name and arguments, validates the types, and routes the request. |
| 5 | Execute and Observe | The tool runs in a sandbox, and the result gets appended back into the model's context as new text. |

That last step is what closes the loop. The tool's answer becomes part of the conversation, which means the model's next prediction is now informed by reality instead of by its own imagination.

If you're a developer, this maps almost exactly onto a debug cycle. Write a change, run it, read the output, adjust. The model is the programmer. The sandbox is the test run. The observation is the console log.

Remove that return arrow from the bottom back to the top, and you no longer have an agent. You have a one-shot query.

## Part 1: How the Action Gets Written: Rigid JSON vs. Free Code

There are two competing philosophies for how the model writes its action, and the choice matters far more than it first appears.

### Structured JSON Schemas

Each tool is declared as a rigid object: argument names, types, descriptions. The model's job is to fill in the blanks.

```json
{"name": "read_file", "arguments": {"path": "main.py"}}
```

Think of it as a printed form with labelled boxes. Easy to validate and easy to constrain. It audits cleanly too. But one form equals one action, so if you need ten actions, you pay for ten round-trips.

### Programmatic Code (CodeAct)

Instead of filling a form, the model writes a script: actual Python or Bash.

This is a bigger deal than it sounds, because code is a meta-tool. It natively handles loops, conditionals, variable assignment, and nested function calls, all in a single turn.

Want to process fifty files? In JSON you either build a bespoke `process_many` tool or loop fifty times. In code, you write `for f in files:` and you're done.

Published research on CodeAct reports that it reduces required interaction turns and increases task success rates compared to rigid JSON tool calls. That intuitively makes sense. Fewer round-trips means fewer chances for the model to drift off track.

### The Honest Tradeoff

Code as a meta-tool is genuinely more powerful. That is precisely the problem.

A rigid JSON form constrains the model's blast radius. The worst it can do is call one wrong function with valid arguments. A model writing arbitrary Bash can do anything Bash can do.

The expressiveness that makes CodeAct win benchmarks is the same expressiveness that makes sandboxing and permissions load-bearing rather than nice-to-have. Power and risk are the same dial.

## Part 2: How Malformed Output Is Made Impossible

Here's a problem you might not have considered. Because the model is probabilistic, it will, reliably and annoyingly, emit broken JSON. A trailing comma. A missing closing brace. A parameter key it invented out of thin air.

The naive fix is retries: try, fail, try again. Slow and wasteful.

The clever fix is to make malformed output physically ungeneratable, to never let the model write an illegal token in the first place. This is grammar-constrained decoding, and the logic is elegant.

Three ideas stack.

### 1. JSON Requires a Context-Free Grammar (CFG)

A regex (a finite-state automaton) is like a checkout scanner. It reads one symbol at a time and has nowhere to store memory of how deep it has gone. Fine for a phone number. Useless for JSON.

Why? Because JSON nests arbitrarily: an object inside an array inside an object. To answer "are these brackets balanced?" you need to remember how many are currently open. A regex literally cannot. A context-free grammar can express that recursive structure.

### 2. Enforcing a CFG Requires a Pushdown Automaton (PDA)

A pushdown automaton is a finite-state machine with one extra piece of equipment: a memory stack.

The analogy that sticks best is sticky notes. Every `{` pushes a note onto the pile. Every `}` peels one off. If the pile is empty and you see another `}`, something is wrong.

That stack is the entire difference between "can check brackets" and "can't."

### 3. Logit Masking at Every Single Token

At each decoding step, high-performance inference engines (vLLM, SGLang, and friends, often via XGrammar) do the following:

1. Check the current PDA stack state against the model's entire vocabulary.
2. Assign a logit of negative infinity to any token that would break syntax or violate the schema.
3. Compute the softmax only over the surviving tokens.

A token that would produce bad syntax ends up with a probability of zero. The model cannot pick it, because it isn't on the menu.

The result: 100% syntactically valid tool calls, with no retries required.

### The Subtlety Worth Underlining

What this guarantees is syntax. Meaning stays out of reach.

The model can still emit perfectly valid JSON that calls the wrong tool with a nonsense argument. Grammar constraints make output well-formed. They do nothing to make it correct.

Valid JSON and correct intent are two different problems. Only the first one is solved here. Anyone who tells you constrained decoding "solves reliability" is describing half the picture.

### The Tradeoff Nobody Puts on the Slide

Masking isn't free.

- You're running a parser at every token, over the full vocabulary, on every generation. That's real throughput cost.
- The grammar itself must be written correctly. An over-tight grammar boxes the model into valid-but-useless output. An over-loose one lets garbage through.

Treat it as a genuine engineering knob. Nothing here switches itself on.

## Part 3: How the Action Executes Without Leaking Your API Keys

Now the tool call exists and it's syntactically perfect. The harness has to actually run it. And here, a boring-looking architectural choice has real security consequences.

### Direct REST / cURL

The harness fires an HTTP request at the endpoint. Simple, until you notice what happens when a coding agent runs curl directly inside a shell.

The secret API key lives in an environment variable (`$UPSTREAM_API_KEY`), and that variable is sitting inside the agent's own sandbox. The model, or anything that can read that sandbox, can simply look at it.

That's a credential-leak waiting to happen.

### Model Context Protocol (MCP)

MCP was developed to decouple execution from credentials.

The agent never touches the real key. It authenticates to an MCP server using a narrow, scoped token (`MCP_API_KEY`). The server validates the request, reaches behind the curtain to inject the sensitive upstream key itself, makes the real API call, and returns only the formatted result.

The LLM policy engine never sees or holds the raw upstream credential.

The analogy: it's a coat check. You hand over a claim ticket and the broker holds the actual secret. All the agent ever carries is a claim check that's worthless on its own.

### The Doubt I Can't Fully Shake

MCP adds a trusted middleman, and every added hop is added attack surface and added latency. You're now trusting the MCP server to be correctly configured and to not be the weak link.

The security win is real. Keeping the key out of the sandbox is unambiguously better. It is still a trade, and you pay for it with latency and with one more party you have to trust. You've moved the trust. You haven't eliminated it.

## Why Any of This Matters Outside a Research Paper

Three practical takeaways that change how you'd build or evaluate a system.

### 1. Tool Use Is Three Separable Design Decisions

Serialization format, the mechanism that guarantees well-formed output, and the execution protocol are independent choices with independent failure modes. If a tool-using system is flaky, you now have three specific places to look instead of one vague one.

### 2. Reliability Comes From the Harness

The loop can be trusted because deterministic software surrounds the model. The model's intelligence is beside the point here.

- Grammar masking kills malformed calls.
- Type-checking kills bad arguments.
- MCP kills credential leaks.
- The sandbox kills collateral damage.

The model supplies intent. The scaffolding supplies correctness. This is the single most useful mental model for anyone debugging an agent.

### 3. Ask About Blast Radius

Rigid JSON with a narrow scoped key is a tightly bounded system. CodeAct with direct REST is a vastly more capable system with a vastly larger radius.

Neither one wins in the abstract. Choose deliberately, and know which one you chose.

## The Bigger Point

The thing I find genuinely interesting here is how much of "AI capability" turns out to be plumbing.

The intelligence is the model's. The trustworthiness is the surrounding engineering's. We tend to credit the former and ignore the latter, and it is almost always the latter that decides whether the thing works in production.

---

### FAQ

**What is grammar-constrained decoding in LLMs?**

Grammar-constrained decoding restricts which tokens a model is allowed to generate, based on a formal grammar. At every decoding step, tokens that would violate the grammar or the JSON schema receive a logit of negative infinity, so the model physically cannot output malformed syntax. The result is guaranteed-valid tool calls without retry loops.

**Why can't JSON be validated with a regular expression?**

JSON allows arbitrary structural nesting, meaning objects inside arrays inside objects. A regex runs on a finite-state automaton, which has no memory of how deeply nested the input currently is. To check bracket balance you need to remember open brackets, and that requires a context-free grammar and a pushdown automaton with a memory stack.

**Does grammar-constrained decoding guarantee correct tool calls?**

No. This is the most common misconception. The guarantee it gives you is about syntax. Semantics are a separate matter, and the model can still emit perfectly valid JSON that calls the wrong function with a nonsense argument. Constrained decoding makes output well-formed. Making it correct is a different problem.

**CodeAct vs. JSON function calling: which should I use?**

It depends on your blast-radius tolerance. JSON schemas stay rigid and bounded, and they validate cleanly, which suits sensitive operations. CodeAct lets the model write executable code that handles loops, conditionals, and nested calls in a single turn, reducing interaction turns and improving task success rates. The catch: arbitrary code execution means a much larger blast radius, so sandboxing becomes mandatory rather than optional.
