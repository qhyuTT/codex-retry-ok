# codex-retry-ok

[English](README.md) | 中文

`codex-retry-ok` 是一个简单的 Shell 脚本，用来并发重复执行最小化的 `codex exec` 请求，直到任意一次 Codex 最终回复严格等于 `OK`，或者达到全局最大尝试次数。

默认会启动 3 个 worker，执行的命令等价于：

```bash
codex exec --skip-git-repo-check --json --ephemeral "只回复 OK"
```

它会实时打印 `codex exec --json` 输出的 JSONL 内容。脚本不会保存日志文件，也不会创建日志目录。

## 适用场景

- 想快速确认当前 Codex CLI 登录状态、模型配置和自定义 URL 是否可用。
- 遇到临时高峰、短暂失败或非预期回复时，希望自动重试。
- 希望用小并发更快等到一次成功响应。
- 需要在终端里实时观察 Codex JSONL 事件流。

## 依赖

运行前需要确保本机已经安装并配置好：

- `codex`
- `jq`
- `bash`

同时需要你已经可以正常运行 Codex CLI。例如：

```bash
codex exec --skip-git-repo-check --json --ephemeral "只回复 OK"
```

如果你的 Codex CLI 已经登录，脚本会直接使用当前 Codex 配置和登录缓存，不需要在脚本里额外写 API key。

## 安装

克隆仓库：

```bash
git clone https://github.com/qhyuTT/codex-retry-ok.git
cd codex-retry-ok
```

确认脚本有执行权限：

```bash
chmod +x codex-retry-ok.sh
```

## 基本使用

直接运行。默认会启动 3 个 worker 并发尝试，成功收到 `OK` 后会播放 macOS 提示音：

```bash
./codex-retry-ok.sh
```

默认 prompt 是：

```text
只回复 OK
```

如果任意一次 Codex 的最终 agent message 是 `OK`，脚本会停止其他 worker，退出并返回成功：

```text
Succeeded on attempt 1 by worker 1.
```

如果不需要提示音：

```bash
BEEP_ON_SUCCESS=0 ./codex-retry-ok.sh
```

## 自定义 Prompt

可以传入自己的 prompt：

```bash
./codex-retry-ok.sh "只回复 OK"
```

脚本的成功判断仍然是：最后一条 `agent_message` 去掉首尾空白后，必须严格等于 `OK`。

## 重试参数

可以通过环境变量调整重试行为：

```bash
MAX_ATTEMPTS=300 ./codex-retry-ok.sh
```

| 参数 | 默认值 | 说明 |
| --- | ---: | --- |
| `MAX_ATTEMPTS` | `120` | 全局最大尝试次数，不是每个 worker 的次数 |
| `CONCURRENCY` | `3` | 并发 worker 数量 |
| `BEEP_ON_SUCCESS` | `1` | 成功收到 `OK` 后是否播放 macOS 提示音，`0` 表示关闭 |
| `SUCCESS_SOUND` | `Glass` | 成功提示音名称或完整声音文件路径 |

如果只想串行重试，可以把并发数设为 1：

```bash
CONCURRENCY=1 ./codex-retry-ok.sh
```

脚本会在 worker 之间共享尝试计数、成功标志和最后失败摘要。某个 worker 失败后会等待 1 秒，再领取下一次全局 attempt。

## 成功提示音

默认会在成功收到 `OK` 时播放 macOS 系统提示音：

```bash
./codex-retry-ok.sh
```

显式开启提示音：

```bash
BEEP_ON_SUCCESS=1 ./codex-retry-ok.sh
```

关闭提示音：

```bash
BEEP_ON_SUCCESS=0 ./codex-retry-ok.sh
```

指定其他系统声音：

```bash
BEEP_ON_SUCCESS=1 SUCCESS_SOUND=Ping ./codex-retry-ok.sh
```

也可以指定完整声音文件路径：

```bash
BEEP_ON_SUCCESS=1 SUCCESS_SOUND=/System/Library/Sounds/Hero.aiff ./codex-retry-ok.sh
```

只测试提示音，不执行 Codex：

```bash
SUCCESS_SOUND=Ping ./codex-retry-ok.sh --test-sound
```

macOS 常见系统声音包括：

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

提示音功能只在 macOS 上调用。脚本会优先用 `afplay` 前台播放系统声音文件；如果声音文件不可用，会尝试用 `osascript -e 'beep 3'` 兜底。其他系统会自动跳过，不影响脚本主流程。

## 输出行为

脚本会把 `codex exec --json` 的输出实时打印到终端。例如：

```jsonl
{"type":"thread.started","thread_id":"..."}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}
{"type":"turn.completed","usage":{"input_tokens":7028,"cached_input_tokens":0,"output_tokens":17,"reasoning_output_tokens":10}}
```

并发模式下，不同 worker 的 JSONL 行可能交错出现，但每一行会完整打印，不会被其他 worker 打断。

如果某次结果不是 `OK`，脚本会打印 worker、attempt、退出码和重试原因：

```text
Worker 2 non-OK result on attempt 2, exit=0: no parseable agent OK response
```

## 退出码

- `0`：成功拿到最终回复 `OK`。
- `1`：达到最大重试次数后仍未拿到 `OK`。
- `2`：`MAX_ATTEMPTS` 或 `CONCURRENCY` 参数不是正整数。
- `127`：缺少 `codex` 或 `jq` 命令。

## 注意事项

- 脚本不会写入日志文件。
- 脚本不会修改你的 Codex 配置。
- 脚本默认会在成功收到 `OK` 后播放系统提示音；设置 `BEEP_ON_SUCCESS=0` 可以关闭。
- 脚本默认并发数是 3。更高并发可能更快等到成功，但也会增加请求量和触发限流的风险。
- 脚本使用当前终端环境中的 Codex CLI 配置、登录状态、自定义 provider、自定义 base URL 等设置。
- 如果当前目录不是 Git 仓库，脚本中的 `--skip-git-repo-check` 会跳过 Codex 的 Git 仓库检查。
- 每次 Codex 调用仍使用 `--ephemeral`，共享的是脚本内部状态，不是共享同一个 Codex 会话上下文。
- 如果你希望保存输出，可以在运行时自己使用 `tee`：

```bash
./codex-retry-ok.sh | tee output.jsonl
```

## 常见问题

### 为什么一直重试？

因为脚本只把最终 agent message 严格等于 `OK` 视为成功。以下情况都会继续重试：

- Codex 返回了临时高峰提示。
- Codex 命令退出失败。
- 输出中没有可解析的 `agent_message`。
- 回复是 `OK` 以外的文本。

### 并发会不会共享同一个 Codex 会话？

不会。脚本共享的是内部调度状态，包括全局 attempt 计数、成功标志和最后失败摘要。每次请求仍然是独立的 `codex exec --ephemeral` 调用，避免多个并发请求写入同一个会话造成竞态或上下文污染。

### 为什么要安装 jq？

脚本用 `jq` 解析 `codex exec --json` 输出的 JSONL 事件，并从中提取最后一条 `agent_message.text` 来判断是否成功。

### 会不会使用 API key？

脚本本身不设置 API key。它只调用本机的 `codex exec`，因此认证方式取决于你当前 Codex CLI 的配置和登录状态。
