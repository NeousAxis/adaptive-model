# Adaptive Model

A Claude Code skill + harness-enforced hooks that route each step of your work to the optimal Claude model (Haiku, Sonnet, Opus) and make the model announcement **honest and verifiable**.

Two layers:

1. **The skill** ([`SKILL.md`](SKILL.md)) — the decision engine: evaluates cognitive complexity, decision risk, and work state at each step, then picks the model.
2. **The hooks** ([`hooks/`](hooks/)) — harness-level enforcement that the declared model is (a) always announced and (b) not a lie.

Without the hooks, the skill is just a guideline Claude can drift from. With the hooks, the runtime blocks any response that omits or fakes the tag.

## Why the hooks matter

A skill is a document Claude reads and tries to follow. Models drift — especially on formatting rules. Anyone who has used Claude long enough has seen it quietly stop following a rule after a few turns.

Hooks run in Claude Code's harness, not in the model. They can:

- Inject a reminder into every user turn (so the rule is always in context)
- Verify the response after the fact and block it if non-compliant
- Cross-check what the model claims against server-generated truth (the API-reported model ID, the actual tool parameters)

This repo ships all three.

## What the annotations mean

Two tags, two meanings. Never conflate them. Never lie.

### `[Session: <orchestrator>]` — first line of every direct response

The orchestrator model is **fixed for the entire session**. It cannot become a different model when writing directly — it can only *delegate* a sub-task to another model via `Agent(model=…)`. The session tag must be truthful.

Example:
```
[Session: Opus 4.7]
Here is my answer…
```

### `[Delegating to: <model>] — <purpose>` — immediately before a real `Agent(model=…)` call

Only written when a sub-agent is actually spawned. The model in the tag must match the model parameter passed to `Agent`.

Example:
```
[Delegating to: Sonnet 4.6] — implementing the auth module
<Agent(model="sonnet", ...)>
```

## Hook suite

| File | Event | Blocking | What it verifies |
|------|-------|----------|------------------|
| [`hooks/adaptive-model-reminder.sh`](hooks/adaptive-model-reminder.sh) | `UserPromptSubmit` | no | Injects a `<system-reminder>` on every user turn so the rule is always in context |
| [`hooks/adaptive-model-verify.sh`](hooks/adaptive-model-verify.sh) (Gate 1) | `Stop` | **yes** | Response starts with `[Session: …]` |
| [`hooks/adaptive-model-verify.sh`](hooks/adaptive-model-verify.sh) (Gate 2) | `Stop` | **yes** | The declared model matches the real session model — cross-checked via the API-generated `.message.model` field in the transcript, which Claude cannot fake |
| [`hooks/adaptive-model-verify.sh`](hooks/adaptive-model-verify.sh) (Gate 3) | `Stop` | **yes** | No phantom `[Delegating to: …]` tags (a tag without a matching `Agent` tool call) |
| [`hooks/adaptive-model-delegation-verify.sh`](hooks/adaptive-model-delegation-verify.sh) | `PostToolUse:Agent` | no (systemMessage) | The last `[Delegating to: X]` tag matches the `model` parameter actually passed to `Agent` |

### What each failure mode triggers

| Failure | How it is caught |
|---------|-------------------|
| I forget the `[Session:]` tag | Gate 1 blocks |
| I write `[Session: Sonnet 4.6]` while running Opus 4.7 | Gate 2 blocks (cross-check with the API) |
| I write `[Delegating to: X]` without spawning `Agent` | Gate 3 blocks |
| I call `Agent(model="haiku")` after `[Delegating to: Opus]` | `PostToolUse` emits a visible `systemMessage` |
| Unknown future model ID not yet in the mapping table | Gate 2 logs a WARN, does not block (forward compat) |
| `Agent` called without a preceding tag | Currently allowed (internal delegations, meta-agents) |

### One-shot bypass

For meta-discussions about the skill itself, or intentionally plain answers:

- Include `#no-session-tag` in your user message, **or**
- Include `ADAPTIVE_MODEL_BYPASS=1` in your user message

The Stop hook sees the marker in the last user message and exits silently for that one response. The next turn, the rule resumes.

## Installation

### 1. Clone the skill

```bash
git clone https://github.com/NeousAxis/adaptive-model.git ~/.claude/skills/adaptive-model
```

### 2. Install the hooks

```bash
mkdir -p ~/.claude/hooks
cp ~/.claude/skills/adaptive-model/hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/adaptive-model-*.sh
```

### 3. Wire them into `~/.claude/settings.json`

Merge the `hooks` block from [`examples/settings.json`](examples/settings.json) into your existing settings. Do **not** replace the file — preserve your existing permissions, plugins, env vars, etc.

Reference shape:
```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/adaptive-model-reminder.sh", "timeout": 5 }] }],
    "Stop":              [{ "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/adaptive-model-verify.sh",    "timeout": 10 }] }],
    "PostToolUse":       [{ "matcher": "Agent", "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/adaptive-model-delegation-verify.sh", "timeout": 10 }] }]
  }
}
```

### 4. Activate in the current session

Claude Code's settings watcher may not pick up newly created hook files in a session that started before them. Either:

- Open `/hooks` in Claude Code (reloads the config), or
- Restart the session

New sessions pick them up automatically.

## Debugging

Both verification hooks write to `/tmp/adaptive-model-verify.log` and `/tmp/adaptive-model-delegation.log` on every run (log rotates at 100 KB). Inspect them when something unexpected happens:

```bash
tail -f /tmp/adaptive-model-verify.log
```

The log shows, per invocation:
- transcript path
- extracted `actual_model_id` (server truth)
- mapped `actual_name`
- parsed `claimed_name`
- the first ~120 bytes of the turn text (as `od -c` for invisible characters)
- delegation tag / Agent call counts

## The decision engine (short version)

At each step, ask: **"What does this specific step require?"**

**Cognitive complexity**
- Low (rephrase, clarify) → Haiku
- Medium (code, test, execute a clear plan) → Sonnet
- High (design, arbitrate, debug the impossible) → Opus

**Decision risk**
- Easily reversible → Sonnet
- Structural → Opus
- No risk → Haiku

**Current state**
- Still clarifying → Haiku
- Plan clear, executing → Sonnet
- Stuck / need to step back → Opus

Full decision engine, rules, escalation logic, and prompt templates in [`SKILL.md`](SKILL.md) and [`references/phases.md`](references/phases.md).

## Architecture rationale

The skill alone could not enforce honest annotation — Claude kept drifting, and on multiple occasions wrote `[Session: Sonnet 4.6]` while the orchestrator was in fact Opus 4.7. That's not style drift, it is a lie.

The fix is structural, not exhortative: the harness (which is not Claude) runs the hooks and has access to the server-generated `.message.model` field for every assistant message. That field is set by Anthropic's API, not by the model itself. It cannot be faked. Gate 2 uses it to ground-truth every tag.

This is also why the bypass exists: a rule this strict needs an explicit escape valve, or it becomes impossible to ever discuss the system itself.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

PRs welcome. Especially useful:
- New model IDs as new versions ship (add to the `case` in `adaptive-model-verify.sh`)
- Tests for edge cases in the transcript parsing
- Refinements to the decision heuristics
