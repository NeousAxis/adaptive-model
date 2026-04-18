#!/bin/bash
# PostToolUse hook on Agent: verify [Delegating to: X] tag matches the real
# model parameter passed to Agent(). Non-blocking — reports via systemMessage.

set -u

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""')
if [ "$tool_name" != "Agent" ]; then exit 0; fi

actual_alias=$(printf '%s' "$input" | jq -r '.tool_input.model // ""')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

log=/tmp/adaptive-model-delegation.log
if [ -f "$log" ] && [ "$(wc -c < "$log")" -gt 102400 ]; then rm -f "$log"; fi

# Concat all assistant text since the last user message (same turn).
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  turn_text=$(jq -rs '
    . as $all
    | ([range(0; $all | length)]
        | map(select(
            $all[.].type == "user"
            and (
              ($all[.].message.content | type == "string")
              or ($all[.].message.content | map(select(.type == "text")) | length > 0)
            )
          ))
        | last // -1
      ) as $idx
    | $all[$idx+1:]
    | map(select(.type == "assistant"))
    | map(.message.content
        | if type == "array" then
            map(select(.type == "text") | .text) | join("")
          else
            . // ""
          end
    ) | join("")
  ' "$transcript" 2>/dev/null)
else
  turn_text=""
fi

# Last [Delegating to: X] tag in the turn.
last_tag_line=$(printf '%s' "$turn_text" | grep -oE '\[Delegating to:[[:space:]]*[^]]+\]' | tail -n 1)
claimed=$(printf '%s' "$last_tag_line" | LC_ALL=C sed -n 's/\[Delegating to:[[:space:]]*\([^]]*\)\].*/\1/p' | LC_ALL=C sed -e 's/[[:space:]]*$//')

# Map Agent alias (opus|sonnet|haiku) -> expected family word.
case "$actual_alias" in
  opus)   family="Opus" ;;
  sonnet) family="Sonnet" ;;
  haiku)  family="Haiku" ;;
  "")     family="" ;;  # no explicit model -> inherit; skip
  *)      family="" ;;  # unknown alias
esac

{
  printf -- '--- %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'actual_alias:  %s\n' "$actual_alias"
  printf 'family:        %s\n' "$family"
  printf 'last_tag:      %s\n' "$last_tag_line"
  printf 'claimed:       %s\n' "$claimed"
} >> "$log" 2>&1

emit() { jq -n --arg m "$1" '{systemMessage: $m}'; }

# Case 0 — no model alias supplied (Agent inherits default). Skip.
if [ -z "$actual_alias" ]; then exit 0; fi

# Case 1 — unknown alias (forward compat): WARN, don't block.
if [ -z "$family" ]; then
  emit "[adaptive-model] WARN: unknown Agent model alias \"$actual_alias\" — delegation-tag check skipped."
  exit 0
fi

# Case 2 — Agent called but no [Delegating to: ...] tag in the turn.
if [ -z "$last_tag_line" ]; then
  emit "[adaptive-model] DELEGATION NOT ANNOUNCED: Agent(model=\"$actual_alias\") was called but no [Delegating to: ...] tag preceded it. Announce delegations before spawning sub-agents."
  exit 0
fi

# Case 3 — tag present, check family match (case-insensitive, substring).
if printf '%s' "$claimed" | grep -qi "$family"; then
  exit 0
fi

# Case 4 — lie: claimed family != actual family.
emit "[adaptive-model] LIE DETECTED: you claimed [Delegating to: $claimed] but Agent was actually called with model=\"$actual_alias\" (family: $family). The annotation and the real tool parameter must match."
exit 0
