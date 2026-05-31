# Adaptive Model

A Claude Code skill that intelligently routes each step of your work to the optimal Claude model (Haiku, Sonnet, or Opus) based on what the task actually requires.

No more manually picking models. No rigid "Phase 1 → Phase 2 → Phase 3" workflows. Just continuous, contextual decisions.

## What it does

Once activated at the start of a session, Adaptive Model stays on for the entire conversation. At every action — user message, internal step, sub-task — it evaluates three axes and picks the right model:

1. **Cognitive complexity** — how hard is this step?
2. **Decision risk** — how structural or reversible is it?
3. **Current state** — are we clarifying, executing, or stuck?

Examples:

| Situation | Model | Why |
|-----------|-------|-----|
| User vaguely describes what they want | Haiku | Low complexity, just clarify |
| Choose between 3 possible architectures | Opus | Structural, high complexity |
| Plan validated, code the auth module | Sonnet | Clear execution |
| Sonnet failed twice on the same bug | Opus | Stuck, needs deep diagnosis |
| "Just add a console.log" | Sonnet | Trivial |
| Full security audit of the code | Opus | Expertise + global view |

## Key features

- **Routes by capability, not by version name** — it targets a *tier* (Haiku/Sonnet/Opus), and the tier aliases always resolve to the latest model, so **new Claude models are adopted automatically with zero edits to the skill**
- **Transparent model switching** — a discreet indicator shows when the model changes
- **Automatic escalation** — when Sonnet gets stuck, Opus is spawned with full context
- **User override** — say "use Opus" or "go fast" and the skill respects it
- **No waste** — never uses an overpowered model for a trivial task
- **Every decision is independent** — no predetermined sequence

## Future-proof by design

The skill never routes by a hardcoded model version. It describes what a task *needs* (reasoning depth, speed, cost, stakes) and picks the tier that provides it. Because `haiku` / `sonnet` / `opus` resolve to the newest model in each tier, a new release (e.g. a newer Opus) is picked up automatically — no table of version numbers to maintain, nothing to go stale.

The only case requiring a human: a model of a *radically new type* (not just a new version of an existing tier). The Agent tool only accepts the three tier aliases, so the skill flags an unknown model and asks which tier to map it to.

## Installation

Clone this repo into your Claude Code skills directory:

```bash
git clone https://github.com/NeousAxis/adaptive-model.git ~/.claude/skills/adaptive-model
```

Or copy the files manually so the structure looks like:

```
~/.claude/skills/adaptive-model/
├── SKILL.md
└── references/
    └── phases.md
```

The skill will appear in your available skills list and can be triggered automatically on multi-step requests, or explicitly via `/adaptive-model`.

## How it activates

Adaptive Model is designed to fire on the first non-trivial message of a session:

- ✅ "I'd like an app that…"
- ✅ "Add a payment module"
- ✅ "Integrate Telegram with…"
- ✅ "Build me an agent that…"
- ❌ Isolated factual questions, typos, single commands

On activation, it announces itself and then evaluates the first request.

## Structure

- [SKILL.md](SKILL.md) — the main skill file with the decision engine, capability-based routing, rules, and escalation logic
- [references/phases.md](references/phases.md) — prompt templates by task type (clarification, planning, code, test, debug, security)

## Philosophy

> Every decision is independent. Context dictates the model. Recognizing your limits and handing off is intelligent. Don't waste an overpowered model on a simple task. Route by capability, never by a version number.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

Issues and PRs welcome. If you have refinements to the decision heuristics, escalation rules, or templates, open a PR.
