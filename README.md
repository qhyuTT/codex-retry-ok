# codex-retry-ok

English | [中文](README.zh-CN.md)

`codex-retry-ok` is a small Bash script that runs minimal `codex exec` requests concurrently until any final Codex agent message is exactly `OK`, or until the global attempt limit is reached.

By default, it starts 3 workers and runs commands equivalent to:

```bash
codex exec --skip-git-repo-check --json --ephemeral "只回复 OK"
```

It streams the JSONL output from `codex exec --json` to the terminal. It does not save log files or create log directories.

## Use Cases

- Quickly check whether the current Codex CLI login, model config, and custom URL are working.
- Retry automatically during temporary load, transient failures, or unexpected responses.
- Use small concurrency to get a successful response faster.
- Watch the Codex JSONL event stream live in the terminal.

## Requirements

Make sure these commands are installed and configured:

- `codex`
- `jq`
- `bash`

You should already be able to run Codex CLI directly, for example:

```bash
codex exec --skip-git-repo-check --json --ephemeral "只回复 OK"
```

The script uses your current Codex CLI configuration and login cache. It does not set an API key.

## Install

Clone the repository:

```bash
git clone https://github.com/qhyuTT/codex-retry-ok.git
cd codex-retry-ok
```

Make the script executable:

```bash
chmod +x codex-retry-ok.sh
```

## Usage

Run it directly. By default, it starts 3 workers and plays a macOS success sound after receiving `OK`:

```bash
./codex-retry-ok.sh
```

The default prompt is:

```text
只回复 OK
```

If any Codex final agent message is exactly `OK`, the script stops the other workers and exits successfully:

```text
Succeeded on attempt 1 by worker 1.
```

Disable the success sound:

```bash
BEEP_ON_SUCCESS=0 ./codex-retry-ok.sh
```

## Custom Prompt

Pass a custom prompt as the first argument:

```bash
./codex-retry-ok.sh "只回复 OK"
```

The success condition is unchanged: the last `agent_message` text, after trimming surrounding whitespace, must be exactly `OK`.

## Retry Options

Adjust retry behavior with environment variables:

```bash
MAX_ATTEMPTS=300 ./codex-retry-ok.sh
```

| Variable | Default | Description |
| --- | ---: | --- |
| `MAX_ATTEMPTS` | `120` | Global maximum attempt count, not per-worker |
| `CONCURRENCY` | `3` | Number of concurrent workers |
| `BEEP_ON_SUCCESS` | `1` | Whether to play a macOS success sound after receiving `OK`; use `0` to disable |
| `SUCCESS_SOUND` | `Glass` | macOS sound name or full sound file path |
| `ABORT_ON_RECONNECT` | `1` | Whether to abort the current attempt when a `Reconnecting... N/5` event appears; use `0` to let Codex finish its own reconnect flow |
| `ABORT_RECONNECT_AT` | `1` | Reconnect attempt number that triggers the abort; defaults to the first reconnect |
| `RECONNECT_ABORT_SLEEP` | `1` | Seconds a worker waits before claiming another attempt after aborting a reconnecting attempt |

To force serial retry behavior:

```bash
CONCURRENCY=1 ./codex-retry-ok.sh
```

Workers share the script's internal attempt counter, success flag, and last failure summary. After a failed attempt, a worker waits 1 second before claiming the next global attempt.

By default, if `codex exec --json` reports a high-demand reconnect, either as a
structured error event or as a plain-text line on stderr, such as:

```jsonl
{"type":"error","message":"Reconnecting... 1/5 (We're currently experiencing high demand, which may cause temporary errors.)"}
```

```text
Stream disconnected. Reconnecting... 1/5
```

the script aborts that attempt early, then lets the worker wait `RECONNECT_ABORT_SLEEP` seconds before claiming the next attempt. This avoids tying up a worker while Codex runs through its full internal reconnect sequence. To keep Codex's original reconnect behavior:

```bash
ABORT_ON_RECONNECT=0 ./codex-retry-ok.sh
```

## Success Sound

The default success sound uses a macOS system sound:

```bash
./codex-retry-ok.sh
```

Enable it explicitly:

```bash
BEEP_ON_SUCCESS=1 ./codex-retry-ok.sh
```

Disable it:

```bash
BEEP_ON_SUCCESS=0 ./codex-retry-ok.sh
```

Choose another system sound:

```bash
BEEP_ON_SUCCESS=1 SUCCESS_SOUND=Ping ./codex-retry-ok.sh
```

Use a full sound file path:

```bash
BEEP_ON_SUCCESS=1 SUCCESS_SOUND=/System/Library/Sounds/Hero.aiff ./codex-retry-ok.sh
```

Test the sound without running Codex:

```bash
SUCCESS_SOUND=Ping ./codex-retry-ok.sh --test-sound
```

Common macOS system sounds include:

```text
Basso
Blow
Bottle
Frog
Funk
Glass
Hero
Morse
Ping
Pop
Purr
Sosumi
Submarine
Tink
```

Sound playback only runs on macOS. The script first tries `afplay` with a system sound file. If that is unavailable, it falls back to `osascript -e 'beep 3'`. Other systems skip the sound step without affecting the main flow.

## Output

The script streams `codex exec --json` output to the terminal, for example:

```jsonl
{"type":"thread.started","thread_id":"..."}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}
{"type":"turn.completed","usage":{"input_tokens":7028,"cached_input_tokens":0,"output_tokens":17,"reasoning_output_tokens":10}}
```

In concurrent mode, JSONL lines from different workers may be interleaved, but each line is printed atomically.

If an attempt does not return `OK`, the script prints the worker, attempt, exit code, and reason:

```text
Worker 2 non-OK result on attempt 2, exit=0: no parseable agent OK response
```

## Exit Codes

- `0`: received final response `OK`.
- `1`: reached `MAX_ATTEMPTS` without receiving `OK`.
- `2`: `MAX_ATTEMPTS` or `CONCURRENCY` is not a positive integer.
- `127`: missing `codex` or `jq`.

## Notes

- The script does not write log files.
- The script does not modify your Codex configuration.
- The default concurrency is 3. Higher concurrency can reduce wall-clock time, but also increases request volume and rate-limit risk.
- The script uses the Codex CLI configuration, login state, custom provider, and custom base URL from the current terminal environment.
- `--skip-git-repo-check` lets Codex run even when the current directory is not a Git repository.
- Each Codex call still uses `--ephemeral`; the shared state is script-level scheduling state, not a shared Codex session.
- To save output yourself, use `tee`:

```bash
./codex-retry-ok.sh | tee output.jsonl
```

## FAQ

### Why does it keep retrying?

The script only treats a final agent message exactly equal to `OK` as success. It keeps retrying when:

- Codex returns a temporary load or failure message.
- Codex emits `Reconnecting... N/5` and the script aborts the attempt early by default.
- The Codex command exits with an error.
- The output has no parseable `agent_message`.
- The response is anything other than `OK`.

### Do concurrent workers share one Codex session?

No. Workers only share internal scheduling state: the global attempt counter, success flag, and last failure summary. Each request remains an independent `codex exec --ephemeral` call, avoiding races or context contamination from concurrent writes to the same session.

### Why is `jq` required?

The script uses `jq` to parse JSONL events from `codex exec --json` and extract the last `agent_message.text` for success detection.

### Does it use an API key?

The script does not set an API key. It only calls your local `codex exec`, so authentication depends on your current Codex CLI configuration and login state.
