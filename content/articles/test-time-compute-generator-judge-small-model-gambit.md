Title: Test-Time Compute Explained: Why Sampling More Beats Training Bigger, and When It Doesn't
Date: 2026-09-25
Category: AI Scaling
Tags: test-time-compute, llm-scaling, reward-models
Slug: test-time-compute-generator-judge-small-model-gambit
Authors: Sijan Bhandari
Summary: A working breakdown of test-time compute: reach curves, judge ceilings, budget splitting, and the FLOP ledger that decides small model vs big model.


Sampling a small model 258 times can beat a model 14* larger. Crank up the query volume and the same trick shrinks to 16 draws, and it loses. The variable that flips the outcome is your traffic forecast.

If you only ever read single-accuracy benchmark tables, that sounds like nonsense. It makes sense the moment you stop asking "how good is this model?" and start asking "how good is this model at a given question-time budget?" That second question has a curve as its answer, and the curve is where all the interesting engineering lives.

This post walks through test-time compute from the ground up: the generator and judge decomposition, an unbiased estimator for sampling coverage, why aggregate curves bend into power laws, why majority voting saturates, how to split a fixed budget, and a FLOP ledger for the train-big-vs-sample-small decision. Every number below was recomputed with code rather than recalled, and the doubts are left in. The framing follows Snell et al. (2024), with the coverage results from Brown et al. (2024) and the power-law derivation from Schaeffer et al. (2025).

### The Core Idea

Once a model is trained, its weights **w** are frozen. Everything that follows is about one question: how do we get more out of a frozen model at the moment we ask it a question?

The answer: instead of one attempt, make **many attempts and then judge them**. That's it. "Test-time compute" just means spending extra arithmetic at question time, in the form of extra attempts, extra reasoning chains, extra checking, to raise accuracy without touching the weights.

**Analogy.** A student who has finished studying (training is done) can still do better on an exam by drafting the answer three times and picking the best one. The studying didn't change; the answering behavior did.

**Why it matters.** This reframes "how good is a model?" The honest answer is never a single number. It's a curve: accuracy as a function of how much question-time effort you're willing to pay. Two models with identical one-shot scores can be wildly different at high budgets.

### The Two Knobs: Generator and Judge

Every question-time strategy decomposes into exactly two decisions [Snell et al., 2024](https://arxiv.org/abs/2408.03314):

- **The generator**: how candidate attempts are produced. Repeated independent draws, step-by-step revision with a scratchpad, or branching out a search tree.
- **The judge**: how one answer is chosen from the pile. Unweighted majority vote, scoring by an outcome-level reward model (whole answer right or wrong), or a step-level reward model (checking each move in the chain).

One honest observation: this decomposition is cleaner in theory than in practice, because the two knobs aren't independent. A generator that produces a diverse pile makes the judge's job easy; a generator that collapses into near-identical drafts makes even a perfect judge nearly useless. Most real systems tune both knobs simultaneously and the attribution gets murky.

### Measuring the Ceiling: Unbiased reach@k

The first thing you want to know is the **ceiling**: if we draw **m** independent attempts, does *at least one* succeed?

Two quantities live here, and people constantly conflate them:

| Quantity | What it measures | Whose knob it belongs to |
|---|---|---|
| **Reach** (coverage) | Is a correct answer somewhere in the pile of m? | Generator |
| **Precision r** | Does the judge pick that correct answer when it exists? | Judge |

To estimate reach fairly from **n** total draws of which **c** were correct, naive counting inflates the number, because it silently uses all n attempts to score a k-of-a-kind event. The unbiased estimator from [Chen et al., 2021](https://arxiv.org/abs/2107.03374) asks: what's the chance a random subset of k draws contains zero correct ones?

$$\text{reach}@k = 1 - \frac{\binom{n-c}{k}}{\binom{n}{k}}$$

The factorial form explodes numerically (binomials like C(1000, 500) overflow floating point), so in practice you compute the product of ratios instead:

$$\text{reach}@k = 1 - \prod_{i=1}^{k}\left(1 - \frac{c}{\,n - k + i\,}\right)$$

In code (I ran this against the direct binomial form across several small (n, c) pairs and both agree to floating-point precision, so the product form is faithful, not just convenient):

```python
import numpy as np

def reach_at_k(correct: int, total: int, k: int) -> float:
    """Numerically stable unbiased reach estimator."""
    if correct == 0:
        return 0.0
    if k > total - correct:
        return 1.0
    denom = np.arange(total - correct + 1, total + 1)
    return 1.0 - np.prod(1.0 - k / denom)
```

**Why it matters.** Reach is the generation ceiling; realized accuracy can never exceed it. Any benchmark table that reports a single accuracy without the reach curve is hiding where the bottleneck actually lives.

### Why the Aggregate Curve Bends: Exponential per Problem, Power Law Overall

Here's the subtlest result in the module.

**Per problem:** if a fixed problem has single-attempt success odds **q**, the miss rate after m draws decays exponentially:

$$\text{miss}(m) = (1-q)^m \approx e^{-qm}$$

Fast. That's the blue curve: it flattens onto 100% quickly.

**Across a benchmark:** problems aren't uniform. Difficulty is heavy-tailed near zero, meaning a mass of nearly-impossible problems and a few easy ones. When you integrate that fast exponential decay over a heavy left tail of the form f(q) ∝ q^(α−1) near zero, the exponential cancels into a power law [Schaeffer et al., 2025](https://arxiv.org/abs/2502.17578):

$$\text{miss}_{\text{agg}}(m) = \int_0^1 f(q)(1-q)^m\,dq \;\propto\; m^{-\alpha}$$

So aggregate reach grows like a power of m: slow, unbounded but plodding. That's the amber curve in the chart. It keeps climbing when the blue one has already flatlined.

The log-log diagnostic: fitting ln(−ln(reach)) = ln(−a) + b·ln(m) by linear regression recovers b ≈ −α. The slope of your straight line *is* the tail exponent of your difficulty distribution.

**Why it matters.** This single result explains why "just sample more" looks perpetually promising on aggregate dashboards while feeling useless on the specific problem you're stuck on. The aggregate headline number is being carried by mid-difficulty problems; the tail of near-zero-q problems barely moves at any realistic budget.

**My doubt here.** The α you fit on one benchmark does *not* transfer. A different benchmark has a different difficulty tail, so a power-law fit is a description, and not a law of nature. Teams that extrapolate "at 10* compute we'll hit 90%" using someone else's α are quoting a curve fitted on different problems.

### The Selection Ceiling: Why Voting Saturates

Drawing more attempts only buys *reach*. Converting reach into a delivered answer is the judge's job, and this is where most systems quietly break.

**Majority voting plateaus.** Voting picks the most common answer. But model errors aren't scattered uniformly: they *cluster* along plausible-looking wrong paths (a sign slip here, a dropped term there). When wrong answers gang up into a dominant wrong mode, the vote confidently selects it even when a correct answer sits in the pile. The documented gap is stark. On MATH, coverage exceeds **95%** at m = 1000 draws for Llama-3-8B while majority voting saturates around **~41%** [Brown et al., 2024](https://arxiv.org/abs/2407.21787). Over half of the correctness that exists is simply never harvested.

**The general decomposition.** With judge precision r:

$$\text{realized accuracy} \approx \text{reach}(m) \times r$$

The uncomfortable corollary: **if r < 1, accuracy plateaus at r no matter how large m gets.** Compute spent past that point is burned.

**Analogy.** You've filled a haystack with 1000 needles and one real pin. Reach = the pin is in the haystack. Precision = your magnet actually attracts pins and not needles. With a bad magnet, adding more hay helps nobody.

**Why it matters, plus a tradeoff.** The highest-leverage engineering decision in a sampling pipeline is usually the judge, and the sample count plays second fiddle. There's a genuine tradeoff hiding in the judge choice: step-level judges (per-move scoring) are more precise but expensive and gameable; whole-answer judges are cheap but coarse; voting is free but blind to *why* an answer is right. There's no dominant choice, only a budget-dependent one.

### Splitting the Budget: More Drafts vs. Longer Drafts

With a fixed arithmetic budget **B**, you can spend it two ways: many **independent attempts** (broad, parallel), or fewer attempts each given **more sequential reasoning and revision steps** (deep, sequential). The budget split is controlled by one exponent:

$$\text{steps} = \lfloor B^{s} \rfloor, \qquad \text{attempts} = \left\lfloor \frac{B}{\text{steps}} \right\rfloor$$

**The allocation rule** [Snell et al., 2024](https://arxiv.org/abs/2408.03314), and it's beautifully intuitive:

- **Hard problems (q ≈ 0):** sequential revision circles in place. The model keeps "fixing" its draft without generating new information. Sequential gain is ~zero. Push everything parallel (**s → 0**) to let independent attempts explore.
- **Easy problems (q well above 0):** revision genuinely repairs small errors. Push sequential (**s → 1**).

**Analogy.** If you keep striking out on a crossword clue, one more careful re-read of your same wrong guess won't help. You need a *different* guess. If you're one letter off on an easy clue, staring longer does help. Match the strategy to the struggle.

The payoff: difficulty-adaptive splitting reaches the same accuracy as uniform splitting with up to **4* less compute**. Snell et al. report the gain as compute-optimal scaling beating a best-of-N baseline by more than 4*.

**An honest observation.** The catch is that "which bin is this problem in?" is exactly what you don't know in advance. Estimating q per problem at inference time is itself a research problem, and mis-binning (treating a hard problem as easy) actively hurts. The 4* figure is the *ceiling* of the idea, and not a floor you get for free.

### Train Bigger, or Sample Smaller? The Load-Ratio Ledger

The strategic question underneath everything: should compute go into **training a bigger model**, or **training smaller and sampling it repeatedly**?

The FLOP ledger (counting ≈ 6·params·tokens for training, ≈ 2·params·tokens per inference token) gives a clean answer. Let the big model have **M**-times more parameters than the small one. Equal total budgets leave the small model a pile of leftover compute, which converts into **A** affordable draws per query:

$$A \;=\; M \;+\; \frac{3}{R}\,(M-1), \qquad R = \frac{\text{inference demand}}{\text{training volume}}$$

(Here **R** is the deployment load: how much total inference traffic you'll serve, relative to how much training compute the model consumed.)

**Two regimes:**

- **Low load (R ≪ 1):** with R = 0.16, A ≈ **258** draws. The small model sampled 258* crushes a model 14* larger. Sampling wins hugely.
- **High load (R ≫ 1):** with R = 22, A ≈ **16** draws. The sampling advantage evaporates. Pretraining the bigger model is the better buy.

**Intuition for why R enters at all.** Training cost is paid *once*; inference cost is paid *per query*. If you serve enormous traffic, the per-query sampling overhead multiplies across millions of queries and dwarfs the one-time training saving. If you serve little traffic (say, a self-improvement loop on your own data), sampling is nearly free.

**Why it matters.** This is a deployment-shaped decision. The right model size depends on your traffic forecast, which means a lab's optimal training decision and your company's optimal buying decision can legitimately differ.

### Worked Self-Test (Both Numbers Computed, Not Estimated)

**Question 1: samples to reach 50% reach when single-attempt success q = 0.05.**

Solve the reach equation for the draw count:

$$1-(1-q)^m = 0.5 \;\Rightarrow\; m = \frac{\ln(0.5)}{\ln(1-0.05)} = \frac{\ln 0.5}{\ln 0.95} \approx 13.51$$

Since draws come in whole numbers, you need **m = 14**. Check: at m = 13, reach = 1 − 0.95¹³ ≈ 0.487 (just short); at m = 14, reach = 1 − 0.95¹⁴ ≈ 0.512 (clears 50%). Verified numerically. The answer is **14 draws**.

**Question 2: affordable draws at shrink factor 5* and high load R = 10.**

$$A = M + \frac{3}{R}(M-1) = 5 + \frac{3}{10}(4) = 5 + 1.2 = 6.2 \;\Rightarrow\; \lfloor A \rfloor = 6 \text{ draws}$$

**Verdict: test-time compute loses in this scenario, decisively.** You can afford 6 draws, but Question 1 says you need 14 just to reach coin-flip coverage on a problem this hard. You're at less than half the required budget, and that's before the judge's precision r further discounts realized accuracy below even the 6-draw reach. In this high-throughput regime, the pretraining route is the better buy, exactly what the R ≫ 1 regime predicts.

### Remaining Doubts, Questions, and Open Threads

- **The judge is the unsung bottleneck.** Most of the field's energy goes into generators; the numbers here (95% reach vs. ~41% voting) suggest judge quality is where the biggest untapped gains sit. But better judges cost FLOPs too. Nobody in this framework prices the verifier's own compute into the ledger, which feels like an accounting gap.
- **Is the power law a law or a coincidence?** The heavy-tail derivation is elegant, but it's conditional on a specific near-zero density shape. Real benchmarks are lumpy. I'd treat fitted exponents as fingerprints of a dataset, and not constants of nature.
- **Difficulty-adaptive allocation assumes you can measure difficulty.** In deployment you often can't, at least not cheaply. The 4* saving is real but contingent on an oracle-ish input.
- **The R formula assumes fixed parameter counts and clean FLOP accounting.** Real deployments have memory, latency, and batching constraints that bend the tradeoff boundary. A small model sampled 258* may be *latency*-infeasible even when FLOP-feasible.
- **One question worth chasing next:** how do these curves change when samples aren't independent, for example sequential revision chains where attempt m+1 is conditioned on attempt m? The independence assumption underlies both the reach estimator and the exponential decay, and correlated attempts are precisely what revision produces.

**Sources:** all content is a faithful re-expression of the provided module, which draws on [Snell et al. (2024)](https://arxiv.org/abs/2408.03314) for the two-knob formalization and compute-optimal allocation, [Chen et al. (2021)](https://arxiv.org/abs/2107.03374) for the unbiased reach estimator, [Schaeffer et al. (2025, *How Do Large Language Monkeys Get Their Power (Laws)?*)](https://arxiv.org/abs/2502.17578) for the exponential-to-power-law result, and [Brown et al. (2024, *Large Language Monkeys*)](https://arxiv.org/abs/2407.21787) for the MATH coverage and voting figures. All arithmetic above was computed and cross-checked with actual code execution in this session.

---

## FAQ

**Q: What is test-time compute in one sentence?**
A: Extra arithmetic spent at question time (repeated sampling, longer reasoning chains, verification) to raise a frozen model's accuracy without retraining it.

**Q: Why does majority voting stop improving after a certain number of samples?**
A: Model errors cluster on plausible wrong paths, so a dominant wrong mode can win the vote even when a correct answer exists in the pile. Voting precision saturates below 1, and realized accuracy plateaus at that precision no matter how many extra samples you add.

**Q: What is the difference between reach (pass@k) and accuracy?**
A: Reach asks whether a correct answer exists anywhere in m draws; accuracy asks whether the system actually delivers that answer. The unbiased reach@k estimator corrects for the inflation that comes from scoring a k-of-a-kind event with all n draws.

**Q: Does sampling more always help?**
A: Per problem, success odds decay exponentially, so sampling helps a lot at first and then stops. Across a whole benchmark, aggregate coverage climbs like a power law, so the headline number keeps improving even when your specific hard problem barely moves. A fitted exponent belongs to one dataset's difficulty tail and won't transfer to another.

**Q: When is training a smaller model and sampling it heavily the right call?**
A: When your deployment load ratio R is low, meaning total inference traffic is small relative to training compute. At R = 0.16 a small model affords roughly 258 draws per query; at R = 22 it affords about 16, and pretraining the bigger model wins instead. The answer is shaped by your traffic forecast, and FLOP feasibility still leaves latency and batching constraints to check.
