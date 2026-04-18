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
Every direct response will carry [Session: <real orchestrator>].
Every delegation to a sub-agent will carry [Delegating to: <model>] — <purpose>.
```

Then immediately analyze the first message. **Starting with the very first response after activation, apply the honest announcement rule (see "Model indicator" section).**

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

### Model indicator (MANDATORY and HONEST)

**Technical truth:** the orchestrator model (the one writing your response) is **fixed for the entire session**. It CANNOT become a different model when writing directly — it can only *delegate* a sub-task to another model via the `Agent(model=…)` tool.

There are therefore two distinct annotations. **Never conflate them. Never lie.**

#### 1. `[Session: <orchestrator>]` — on EVERY direct response

First line of every response you write yourself (text, analysis, synthesis, non-Agent tool calls like Read/Edit/Bash). State the real session model, the one fixed by the user in the harness. Never lie about this value — if the session is Opus 4.7, write `[Session: Opus 4.7]`, even if you would *like* to appear lighter.

Format:
```
[Session: <Haiku 4.5 | Sonnet 4.6 | Opus 4.7>]
```

Example at the top of a response:
```
[Session: Opus 4.7]
Here is my answer...
```

#### 2. `[Delegating to: <model>] — <purpose>` — only when you actually spawn a sub-agent

Print this line **immediately before** each `Agent(model=…)` call. The `<model>` must exactly match what you pass to `model:`. If you are not spawning an `Agent`, do not write this line — a tag without real delegation is a lie.

Format:
```
[Delegating to: <Haiku 4.5 | Sonnet 4.6 | Opus 4.7>] — <sub-task purpose>
```

Example:
```
[Delegating to: Sonnet 4.6] — implementing the auth module
<Agent(model="sonnet", ...) call>
```

#### What is NOT allowed

- Writing `[Model: Sonnet 4.6]` on a response that the Opus orchestrator writes itself → lie.
- Omitting `[Session: …]` on a direct response → opaque, forbidden.
- Writing `[Delegating to: X]` without calling `Agent(model=X, …)` right after → theater, forbidden.
- Changing the value of `[Session: …]` mid-session → technically impossible, therefore a lie.

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

1. **Absolute honesty about the model** — `[Session: <orchestrator>]` on every direct response (the real model, never a lie). `[Delegating to: <model>] — <purpose>` only when an `Agent(model=…)` is actually spawned.
2. **Every decision is independent** — Don't follow a sequence. Evaluate at each step.
3. **Context dictates** — The situation dictates the model, not a predefined workflow.
4. **Transparent for the user** — They never have to guess which model is reasoning: it's announced, and true.
5. **Escalation = intelligence** — Recognizing your limits and handing off is smart.
6. **No waste** — Don't use an overpowered model for a simple task.

## Reference prompts

See `references/phases.md` for prompt templates adapted to each type of task
(clarification, planning, code, test, debug, security). These are guides, not scripts.
