#!/bin/bash
# UserPromptSubmit hook: inject a harness-level reminder about the adaptive-model annotation rule.
# Output JSON goes to stdout; Claude Code treats hookSpecificOutput.additionalContext as injected system context.

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "CRITICAL HARNESS RULE (adaptive-model enforcement): your response MUST start with `[Session: <MODEL>]` on its very first line, where <MODEL> is your real session orchestrator model (Haiku 4.5 | Sonnet 4.6 | Opus 4.7). A Stop hook verifies this and will block the turn if the tag is missing. Never fake a different model (e.g. do not write `[Session: Sonnet 4.6]` if the session is Opus 4.7). If you call Agent(model=X), precede the call with `[Delegating to: <X>] — <purpose>`."
  }
}
EOF
