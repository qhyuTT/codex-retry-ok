# codex-retry-ok

A small shell script that runs:

```bash
codex exec --skip-git-repo-check --json --ephemeral "只回复 OK"
```

It prints Codex JSONL output in real time and retries until the final agent
message is exactly `OK`, or until `MAX_ATTEMPTS` is reached.

## Usage

```bash
./codex-retry-ok.sh
```

Pass a custom prompt:

```bash
./codex-retry-ok.sh "只回复 OK"
```

Tune retry behavior:

```bash
MAX_ATTEMPTS=300 INITIAL_DELAY=1 MAX_DELAY=5 ./codex-retry-ok.sh
```

## Notes

- The script uses your current Codex CLI login and configuration.
- It does not write log files.
- It requires `codex` and `jq` to be available in `PATH`.
