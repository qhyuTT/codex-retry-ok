#!/usr/bin/env bash
set -u

prompt=${1:-"只回复 OK"}
max_attempts=${MAX_ATTEMPTS:-120}
initial_delay=${INITIAL_DELAY:-1}
max_delay=${MAX_DELAY:-15}

if ! command -v codex >/dev/null 2>&1; then
  echo "codex command not found in PATH" >&2
  exit 127
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq command not found in PATH" >&2
  exit 127
fi

attempt=1
delay=$initial_delay

while (( attempt <= max_attempts )); do
  printf '[%s] attempt %d/%d\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$attempt" "$max_attempts" >&2

  reply=""
  status=0

  while IFS= read -r line; do
    if [[ "$line" == __CODEX_RETRY_EXIT_STATUS__:* ]]; then
      status=${line#__CODEX_RETRY_EXIT_STATUS__:}
      continue
    fi

    printf '%s\n' "$line"

    text=$(
      jq -r '
        select(.type == "item.completed" and .item.type == "agent_message")
        | .item.text // empty
      ' <<<"$line" 2>/dev/null || true
    )

    if [[ -n "$text" ]]; then
      reply=$text
    fi
  done < <(
    codex exec --skip-git-repo-check --json --ephemeral "$prompt" 2>&1
    printf '__CODEX_RETRY_EXIT_STATUS__:%d\n' "$?"
  )

  trimmed_reply=$(printf '%s' "$reply" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  if [[ "$trimmed_reply" == "OK" ]]; then
    printf 'Succeeded on attempt %d.\n' "$attempt" >&2
    exit 0
  fi

  reason=$(
    printf '%s' "$trimmed_reply" \
      | tr '\n' ' ' \
      | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ *//' -e 's/ *$//' \
      | cut -c 1-240
  )

  if [[ -z "$reason" ]]; then
    reason="no parseable agent OK response"
  fi

  if (( attempt == max_attempts )); then
    printf 'Failed after %d attempts. Last result: %s\n' "$max_attempts" "$reason" >&2
    exit 1
  fi

  jitter=$(( RANDOM % 5 ))
  sleep_for=$(( delay + jitter ))
  printf 'Non-OK result, exit=%d: %s\n' "$status" "$reason" >&2
  printf 'Sleeping %ds before retry.\n' "$sleep_for" >&2
  sleep "$sleep_for"

  delay=$(( delay * 2 ))
  if (( delay > max_delay )); then
    delay=$max_delay
  fi

  attempt=$(( attempt + 1 ))
done
