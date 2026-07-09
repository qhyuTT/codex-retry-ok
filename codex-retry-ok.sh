#!/usr/bin/env bash
set -u

prompt=${1:-"只回复 OK"}
max_attempts=${MAX_ATTEMPTS:-120}
concurrency=${CONCURRENCY:-3}
beep_on_success=${BEEP_ON_SUCCESS:-1}
success_sound=${SUCCESS_SOUND:-Glass}

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

if ! is_positive_integer "$max_attempts"; then
  echo "MAX_ATTEMPTS must be a positive integer" >&2
  exit 2
fi

if ! is_positive_integer "$concurrency"; then
  echo "CONCURRENCY must be a positive integer" >&2
  exit 2
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex command not found in PATH" >&2
  exit 127
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq command not found in PATH" >&2
  exit 127
fi

play_success_sound() {
  if [[ "$beep_on_success" != "1" ]]; then
    return
  fi

  if [[ "$(uname -s)" != "Darwin" ]]; then
    return
  fi

  sound_path=$success_sound
  if [[ "$sound_path" != /* ]]; then
    sound_path="/System/Library/Sounds/${success_sound}.aiff"
  fi

  if command -v afplay >/dev/null 2>&1 && [[ -f "$sound_path" ]]; then
    afplay "$sound_path" >/dev/null 2>&1
    return
  fi

  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'beep 3' >/dev/null 2>&1
  fi
}

if [[ "${1:-}" == "--test-sound" ]]; then
  beep_on_success=1
  play_success_sound
  exit 0
fi

state_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-retry-ok.XXXXXX")
worker_pids=()

printf '1\n' > "$state_dir/next_attempt"

kill_running_processes() {
  local pid_file
  local pid

  if [[ -z "${state_dir:-}" || ! -d "$state_dir" ]]; then
    return
  fi

  for pid_file in "$state_dir"/codex.* "$state_dir"/producer.*; do
    if [[ ! -f "$pid_file" ]]; then
      continue
    fi

    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done
}

cleanup() {
  kill_running_processes

  if ((${#worker_pids[@]} > 0)); then
    kill "${worker_pids[@]}" >/dev/null 2>&1 || true
    wait "${worker_pids[@]}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${state_dir:-}" && -d "$state_dir" ]]; then
    rm -rf "$state_dir"
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_lock() {
  local lock_dir=$1

  while ! mkdir "$lock_dir" 2>/dev/null; do
    if [[ -f "$state_dir/success" ]]; then
      return 1
    fi
    sleep 0.05
  done
}

release_lock() {
  rmdir "$1" 2>/dev/null || true
}

print_stdout() {
  local line=$1
  local lock_dir="$state_dir/print.lock"

  acquire_lock "$lock_dir" || return 0
  printf '%s\n' "$line"
  release_lock "$lock_dir"
}

claim_attempt() {
  local lock_dir="$state_dir/attempt.lock"
  local attempt

  acquire_lock "$lock_dir" || return 1

  if [[ -f "$state_dir/success" ]]; then
    release_lock "$lock_dir"
    return 1
  fi

  attempt=$(cat "$state_dir/next_attempt")
  if (( attempt > max_attempts )); then
    release_lock "$lock_dir"
    return 1
  fi

  printf '%d\n' $((attempt + 1)) > "$state_dir/next_attempt"
  release_lock "$lock_dir"
  printf '%d\n' "$attempt"
}

record_failure() {
  local worker_id=$1
  local attempt=$2
  local status=$3
  local reason=$4
  local lock_dir="$state_dir/result.lock"

  acquire_lock "$lock_dir" || return 0
  printf 'attempt %d, worker %d, exit=%d: %s\n' "$attempt" "$worker_id" "$status" "$reason" > "$state_dir/last_result"
  release_lock "$lock_dir"
}

record_success() {
  local worker_id=$1
  local attempt=$2
  local lock_dir="$state_dir/result.lock"

  acquire_lock "$lock_dir" || return 1

  if [[ -f "$state_dir/success" ]]; then
    release_lock "$lock_dir"
    return 1
  fi

  printf '%d %d\n' "$attempt" "$worker_id" > "$state_dir/success"
  release_lock "$lock_dir"
  return 0
}

run_attempt() {
  local worker_id=$1
  local attempt=$2
  local reply=""
  local status=0
  local line
  local text
  local fifo="$state_dir/worker-$worker_id-attempt-$attempt.fifo"
  local producer_file="$state_dir/producer.$worker_id"
  local codex_file="$state_dir/codex.$worker_id"

  printf '[%s] worker %d attempt %d/%d\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$worker_id" "$attempt" "$max_attempts" >&2

  mkfifo "$fifo"
  current_fifo=$fifo

  (
    codex_pid=""

    stop_producer() {
      if [[ -n "$codex_pid" ]]; then
        kill "$codex_pid" >/dev/null 2>&1 || true
        wait "$codex_pid" >/dev/null 2>&1 || true
      fi
      exit 143
    }

    trap stop_producer INT TERM

    codex exec --skip-git-repo-check --json --ephemeral "$prompt" 2>&1 &
    codex_pid=$!
    printf '%d\n' "$codex_pid" > "$codex_file"
    wait "$codex_pid"
    printf '__CODEX_RETRY_EXIT_STATUS__:%d\n' "$?"
  ) > "$fifo" &
  current_producer_pid=$!
  current_producer_file=$producer_file
  current_codex_file=$codex_file
  printf '%d\n' "$current_producer_pid" > "$producer_file"

  while IFS= read -r line; do
    if [[ "$line" == __CODEX_RETRY_EXIT_STATUS__:* ]]; then
      status=${line#__CODEX_RETRY_EXIT_STATUS__:}
      continue
    fi

    print_stdout "$line"

    text=$(
      jq -r '
        select(.type == "item.completed" and .item.type == "agent_message")
        | .item.text // empty
      ' <<<"$line" 2>/dev/null || true
    )

    if [[ -n "$text" ]]; then
      reply=$text
    fi
  done < "$fifo"

  wait "$current_producer_pid" >/dev/null 2>&1 || true
  rm -f "$fifo" "$producer_file" "$codex_file"
  current_producer_pid=""
  current_fifo=""
  current_producer_file=""
  current_codex_file=""

  local trimmed_reply
  trimmed_reply=$(printf '%s' "$reply" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  if [[ "$trimmed_reply" == "OK" ]]; then
    record_success "$worker_id" "$attempt"
    return 0
  fi

  local reason
  reason=$(
    printf '%s' "$trimmed_reply" \
      | tr '\n' ' ' \
      | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ *//' -e 's/ *$//' \
      | cut -c 1-240
  )

  if [[ -z "$reason" ]]; then
    reason="no parseable agent OK response"
  fi

  record_failure "$worker_id" "$attempt" "$status" "$reason"
  printf 'Worker %d non-OK result on attempt %d, exit=%d: %s\n' "$worker_id" "$attempt" "$status" "$reason" >&2
  return 1
}

run_worker() {
  local worker_id=$1
  local attempt
  current_producer_pid=""
  current_fifo=""
  current_producer_file=""
  current_codex_file=""

  trap - EXIT
  trap 'if [[ -n "$current_codex_file" && -f "$current_codex_file" ]]; then kill "$(cat "$current_codex_file")" >/dev/null 2>&1 || true; fi; if [[ -n "$current_producer_pid" ]]; then kill "$current_producer_pid" >/dev/null 2>&1 || true; wait "$current_producer_pid" >/dev/null 2>&1 || true; fi; if [[ -n "$current_fifo" ]]; then rm -f "$current_fifo"; fi; if [[ -n "$current_producer_file" ]]; then rm -f "$current_producer_file"; fi; if [[ -n "$current_codex_file" ]]; then rm -f "$current_codex_file"; fi; touch "$state_dir/done.'"$worker_id"'"; exit 143' INT TERM

  while [[ ! -f "$state_dir/success" ]]; do
    attempt=$(claim_attempt) || break
    run_attempt "$worker_id" "$attempt" || true

    if [[ -f "$state_dir/success" ]]; then
      break
    fi

    sleep 1
  done

  touch "$state_dir/done.$worker_id"
}

worker_count=$concurrency
if (( worker_count > max_attempts )); then
  worker_count=$max_attempts
fi

for worker_id in $(seq 1 "$worker_count"); do
  run_worker "$worker_id" &
  worker_pids+=("$!")
done

result=1
while true; do
  if [[ -f "$state_dir/success" ]]; then
    result=0
    break
  fi

  done_count=$(find "$state_dir" -maxdepth 1 -name 'done.*' -type f | wc -l | tr -d ' ')
  if (( done_count >= worker_count )); then
    break
  fi

  sleep 0.1
done

if (( result == 0 )); then
  kill_running_processes
  kill "${worker_pids[@]}" >/dev/null 2>&1 || true
  wait "${worker_pids[@]}" >/dev/null 2>&1 || true

  read -r success_attempt success_worker < "$state_dir/success"
  play_success_sound
  printf 'Succeeded on attempt %d by worker %d.\n' "$success_attempt" "$success_worker" >&2
  exit 0
fi

wait "${worker_pids[@]}" >/dev/null 2>&1 || true

if [[ -s "$state_dir/last_result" ]]; then
  last_result=$(cat "$state_dir/last_result")
else
  last_result="no attempts were run"
fi

printf 'Failed after %d attempts. Last result: %s\n' "$max_attempts" "$last_result" >&2
exit 1
