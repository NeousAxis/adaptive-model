#!/bin/bash
# Stop hook: verify the last assistant message starts with "[Session: ".
# If it does not, return a blocking decision that forces Claude to fix the response.
# Input: CLAUDE_CODE_HOOK JSON on stdin; the payload contains transcript_path.

set -u

input=$(cat)

# Avoid loops: if Claude has already been re-prompted by this hook, stop blocking.
already_looped=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
if [ "$already_looped" = "true" ]; then
  exit 0
fi

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  # Can't verify — don't block.
  exit 0
fi

# One-shot bypass: if the last user message contains the marker, skip verification.
# Use case: meta-discussion about the skill itself, intentional plain answers, etc.
last_user=$(jq -rs '
  [ .[] | select(.type == "user") ]
  | last
  | .message.content
  | if type == "array" then
      map(select(.type == "text") | .text) | join("")
    else
      .
    end
' "$transcript" 2>/dev/null)

if printf '%s' "$last_user" | grep -qE '(#no-session-tag|ADAPTIVE_MODEL_BYPASS=1)'; then
  exit 0
fi

# A single Claude turn often produces MULTIPLE assistant JSONL entries (one per
# API response between tool calls). The `[Session: ...]` tag belongs at the very
# top of the turn — i.e. in the FIRST assistant text after the last user message.
# We therefore:
#   1) locate the last user message index
#   2) take all assistant entries after it
#   3) concatenate their text blocks in order -> this is the "turn text"
#   4) grab the model id from the first such entry (server-generated, un-fakable)
turn=$(jq -rs '
  . as $all
  # Find the last HUMAN user message. Tool results come back as type=="user" too
  # in Claude Code transcripts; distinguish by requiring a text block (or a string
  # content), not a tool_result block.
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
  | ($all[$idx+1:] | map(select(.type == "assistant"))) as $assistants
  | {
      model: ((($assistants | map(select(.message.model != null)) | first) // {}) | .message.model // ""),
      text: (
        $assistants
        | map(.message.content
            | if type == "array" then
                map(select(.type == "text") | .text) | join("")
              else
                . // ""
              end
        ) | join("")
      ),
      agent_calls: (
        $assistants
        | map(.message.content // [] | if type == "array" then . else [] end)
        | add // []
        | map(select(.type == "tool_use" and .name == "Agent"))
        | length
      )
    }
' "$transcript" 2>/dev/null)

actual_model_id=$(printf '%s' "$turn" | jq -r '.model // empty')
last_text=$(printf '%s' "$turn" | jq -r '.text // empty')
agent_calls=$(printf '%s' "$turn" | jq -r '.agent_calls // 0')

# Map Anthropic API model ID -> human name expected in the [Session: ...] tag.
case "$actual_model_id" in
  *opus-4-7*)   actual_name="Opus 4.7" ;;
  *opus-4-6*)   actual_name="Opus 4.6" ;;
  *opus-4-5*)   actual_name="Opus 4.5" ;;
  *sonnet-4-7*) actual_name="Sonnet 4.7" ;;
  *sonnet-4-6*) actual_name="Sonnet 4.6" ;;
  *sonnet-4-5*) actual_name="Sonnet 4.5" ;;
  *haiku-4-5*)  actual_name="Haiku 4.5" ;;
  *haiku-4-6*)  actual_name="Haiku 4.6" ;;
  *)            actual_name="" ;;  # unknown family/version -> skip honesty check
esac

# Strip BOM, leading whitespace and control chars before checking.
trimmed=$(printf '%s' "$last_text" | LC_ALL=C sed -e 's/^\xEF\xBB\xBF//' -e 's/^[[:space:][:cntrl:]]*//')

# Extract the model name the response CLAIMS on its first line, e.g. "Opus 4.7".
claimed_name=$(printf '%s' "$trimmed" | head -n 1 \
  | LC_ALL=C sed -n 's/^\[Session:[[:space:]]*\([^]]*\)\].*/\1/p' \
  | LC_ALL=C sed -e 's/[[:space:]]*$//')

# Debug log (rotate at 100 KB).
log=/tmp/adaptive-model-verify.log
if [ -f "$log" ] && [ "$(wc -c < "$log")" -gt 102400 ]; then rm -f "$log"; fi
{
  printf -- '--- %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'transcript: %s\n' "$transcript"
  printf 'actual_model_id: %s\n' "$actual_model_id"
  printf 'actual_name:     %s\n' "$actual_name"
  printf 'claimed_name:    %s\n' "$claimed_name"
  printf 'last_text (first 120 bytes, od -c):\n'
  printf '%s' "$last_text" | head -c 120 | od -c | head -n 8
  printf 'trimmed (first 40 bytes):\n%s\n' "$(printf '%s' "$trimmed" | head -c 40)"
} >> "$log" 2>&1

# Gate 1 — presence of the tag.
if ! printf '%s' "$trimmed" | grep -q '^\[Session: '; then
  jq -n '{
    decision: "block",
    reason: "Your response did not start with `[Session: <MODEL>]`. Prepend the exact line `[Session: <your real orchestrator model>]` at the very top of your response before finishing. Do not lie about the model."
  }'
  exit 0
fi

# Gate 2 — honesty of the tag vs the real API model.
# Skip when we cannot map the model id; better to pass than to false-positive.
if [ -z "$actual_name" ]; then
  if [ -n "$actual_model_id" ]; then
    # Forward-compat WARN: the mapping table is out of date.
    printf '[WARN %s] adaptive-model-verify: unmapped model id "%s" — honesty check skipped. Update the case in adaptive-model-verify.sh.\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$actual_model_id" >> "$log"
  fi
elif [ "$claimed_name" != "$actual_name" ]; then
  jq -n --arg actual "$actual_name" --arg claimed "$claimed_name" --arg id "$actual_model_id" '{
    decision: "block",
    reason: ("DISHONEST MODEL TAG. Your response claims `[Session: " + $claimed + "]` but the Anthropic API reports your real session model as `" + $id + "` (which maps to `" + $actual + "`). Rewrite the first line as exactly `[Session: " + $actual + "]`. Do not fake a lighter model.")
  }'
  exit 0
fi

# Gate 3 — phantom delegation tag: [Delegating to: ...] written without a real Agent call.
# Count occurrences (not lines) by using grep -oE + wc -l.
delegating_tags=$(printf '%s' "$last_text" | grep -oE '\[Delegating to:[[:space:]]*[^]]+\]' 2>/dev/null | wc -l | tr -d ' ')
delegating_tags=${delegating_tags:-0}
agent_calls=${agent_calls:-0}

{
  printf 'delegating_tags: %s\n' "$delegating_tags"
  printf 'agent_calls:     %s\n' "$agent_calls"
} >> "$log" 2>&1

if [ "$delegating_tags" -gt "$agent_calls" ]; then
  jq -n --arg n "$delegating_tags" --arg m "$agent_calls" '{
    decision: "block",
    reason: ("PHANTOM DELEGATION TAG. Your response contains " + $n + " `[Delegating to: ...]` annotations but only " + $m + " actual Agent tool call(s) were made this turn. Either spawn the delegation via Agent(model=...) or remove the tag. Do not announce delegations that never happen.")
  }'
  exit 0
fi

# Pass.
exit 0
