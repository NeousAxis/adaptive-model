---
name: adaptive-model
description: |
  Intelligent orchestration mode that activates ONCE at the start of a session and remains active
  for the entire conversation. Once active, every user message is automatically routed to the
  optimal LLM model (Haiku, Sonnet, Opus) based on the nature of the request. The user doesn't
  have to do anything — routing is transparent and automatic.
  Trigger this skill from the FIRST non-trivial message of the session: app creation,
  feature implementation, multi-step project, refactoring, integration, or any request
  that will require several exchanges. Examples: "I'd like an app that...",
  "how do I build a system for...", "add a payment module", "develop a feature",
  "integrate Telegram with...", "build me an agent that...", "let's work on...".
  Do NOT trigger for: an isolated factual question, a typo, a single command.
---

# Adaptive Model — Session Decision Engine

This skill activates only once at the start of a session. From that point on, at EVERY action
(user message, internal step, sub-task), you independently evaluate which model is most
relevant and use it. There is NO predetermined sequence.

## Activation

On activation, display:

```
Adaptive Model active.
The optimal model will be automatically selected at each step.
```

Then immediately analyze the first message.

## The decision engine

At each step, ask yourself: **"What does this specific step require?"**

### The 3 decision axes

**1. Required cognitive complexity**
- Low (rephrase, clarify, answer quickly) → Haiku
- Medium (code, test, execute a clear plan) → Sonnet
- High (design, arbitrate, debug the impossible, audit) → Opus

**2. Decision risk**
- Easily reversible (writing code that can be fixed) → Sonnet
- Structural (architecture, technical choices that impact everything else) → Opus
- No risk (discussion, brainstorming) → Haiku

**3. Current state of the work**
- Still clarifying the need → Haiku
- Plan is clear, execution phase → Sonnet
- Stuck, going in circles → Opus
- Need to step back and re-evaluate → Opus

### Routing by CAPABILITY, not by model name

You NEVER route to a model by its version number ("send this to Opus 4.8"). You route to the **tier** whose current model has the capabilities the task requires. Because the aliases `haiku` / `sonnet` / `opus` always point to the latest version of each tier, **every new model is adopted automatically with its improved capabilities, without editing this skill.**

Describe the task's need along these dimensions, then pick the tier that best covers them AMONG those available:

| Capability dimension | Low need → | Medium need → | High need → |
|---|---|---|---|
| Reasoning depth | Haiku | Sonnet | Opus |
| Cost sensitivity / high volume | Opus | Sonnet | Haiku (cheapest first) |
| Speed / latency required | Opus | Sonnet | Haiku (fastest first) |
| Stakes / irreversibility | Haiku | Sonnet | Opus |
| Autonomy on a long task | Haiku | Sonnet | Opus |

**Golden rule: always express the need in RELATIVE capabilities ("the deepest-reasoning tier available"), never in an absolute version.** This way the skill never goes stale when a new model ships — it picks up the new capability automatically.

#### Technical ceiling to know (don't work around it blindly)

- The `Agent(model: …)` tool only accepts 3 aliases: `haiku`, `sonnet`, `opus`. You CANNOT pass a full identifier (`claude-opus-4-8-…`) to a sub-agent. Stay on the aliases.
- No machine-readable feed lists a model's "properties" (benchmarks, price, speed). Any absolute-value table goes stale — hence the RELATIVE dimensions above.
- Consequence: a new **version** of an existing tier is picked up on its own (alias). A model of a **radically new type** cannot be routed automatically — the user must name it and say which tier to map it to.

#### Roster discovery at startup (optional — only if an API key is present)

On activation, you MAY confirm the actually-available models and spot an unknown one. Without an API key, skip this step silently (the aliases are enough):

```bash
if [ -n "$ANTHROPIC_API_KEY" ]; then
  curl -s https://api.anthropic.com/v1/models \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    | grep -o '"id":"[^"]*"'
fi
```

If a returned model matches no known tier (Haiku/Sonnet/Opus), **flag it to the user** and ask which tier to map it to — then route via the matching alias. Otherwise, change nothing.

### Example decisions (NOT fixed rules)

These examples illustrate the reasoning. Every real situation is different —
it's up to you to judge by combining the 3 axes.

| Situation | Likely decision | Reasoning |
|-----------|-----------------|-----------|
| User vaguely describes what they want | Haiku | Low complexity, just need to clarify |
| Choose between 3 possible architectures | Opus | Structural decision, high complexity |
| Plan validated, need to code the auth module | Sonnet | Execution, clear plan, reversible risk |
| Sonnet failed twice on the same bug | Opus | Stuck, needs deep diagnosis |
| User says "just add a console.log" | Sonnet | Trivial, no orchestration needed |
| User wants a security audit of the code | Opus | Expertise, high risk, global view |
| User is discussing variable names | Haiku | Light discussion, no heavy decision |
| Need to integrate an unknown external API | Opus | Research + technical decision |
| Tests pass, need to fix a failing test | Sonnet | Execution, clear context |
| Sonnet fixed the test but the fix is dubious | Opus | Verification, judgment required |

### What MUST NOT happen

- Using Opus to copy-paste boilerplate code → waste
- Using Haiku to design an architecture → weak result
- Using Sonnet to solve a problem after 2 failures → going in circles
- Following a fixed "Phase 1 → Phase 2 → Phase 3" sequence without thinking → the opposite of this skill

## Technical implementation

For each action requiring a sub-agent, use the Agent tool with the chosen model:

```
Agent(model: "haiku", prompt: "...")
Agent(model: "opus", prompt: "...")
Agent(model: "sonnet", prompt: "...")
```

### Context passing

Each sub-agent receives in its prompt:
1. What the user asked (original context)
2. What has already been done (results of previous steps)
3. What it needs to do now (specific instruction)

The prompt must be complete and self-contained — the sub-agent has no access to the conversation.

### Model indicator

On each model change, display a discreet line so the user can see which model is reasoning:

```
→ Opus: architecture evaluation
```

Show it only when the model changes, not on every micro-action. Use the tier name (Haiku / Sonnet / Opus), never a hardcoded version number.

### Tracking

Use TodoWrite for multi-step projects. Each major task = 1 todo.

## Automatic escalation

When a Sonnet agent is stuck (2 failed attempts, or it explicitly states it cannot solve
the problem):

1. Sonnet describes the problem, what it tried, why it's stuck
2. You evaluate: can Opus help? (answer is almost always yes)
3. You spawn Opus with full context: plan + code + error + attempts
4. Opus diagnoses and produces a fix or a new plan
5. You decide whether Sonnet or Opus executes the follow-up (depending on fix complexity)

## User control

The user always retains control:
- "use Opus for this" → you comply
- "just code it, no need for a plan" → you switch to Sonnet
- "think harder" → you switch to Opus
- "go fast" → you use the fastest suitable model

## Rules

1. **Route by capability, not by version** — Pick the tier whose current model fits the need. The aliases auto-adopt new model versions; never hardcode a version number.
2. **Every decision is independent** — Don't follow a sequence. Evaluate at each step.
3. **Context dictates** — The situation dictates the model, not a predefined workflow.
4. **Transparent for the user** — A discreet indicator shows which model is reasoning when it changes.
5. **Escalation = intelligence** — Recognizing your limits and handing off is smart.
6. **No waste** — Don't use an overpowered model for a simple task.

## Reference prompts

See `references/phases.md` for prompt templates adapted to each type of task
(clarification, planning, code, test, debug, security). These are guides, not scripts.
