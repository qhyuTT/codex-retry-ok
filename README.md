# codex-retry-ok

`codex-retry-ok` 是一个简单的 Shell 脚本，用来重复执行一次最小化的
`codex exec` 请求，直到 Codex 最终回复严格等于 `OK`，或者达到最大重试次数。

脚本默认执行的命令等价于：

```bash
codex exec --skip-git-repo-check --json --ephemeral "只回复 OK"
```

它会实时打印 `codex exec --json` 输出的 JSONL 内容，不会保存日志文件，也不会创建日志目录。

## 适用场景

- 想快速确认当前 Codex CLI 登录状态、模型配置和自定义 URL 是否可用。
- 遇到临时高峰、短暂失败或非预期回复时，希望自动重试。
- 需要在终端里实时观察 Codex JSONL 事件流，而不是事后查看日志。

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

直接运行：

```bash
./codex-retry-ok.sh
```

默认 prompt 是：

```text
只回复 OK
```

如果 Codex 的最终 agent message 是 `OK`，脚本会退出并返回成功：

```text
Succeeded on attempt 1.
```

## 自定义 prompt

你也可以传入自己的 prompt：

```bash
./codex-retry-ok.sh "只回复 OK"
```

脚本的成功判断仍然是：最后一条 `agent_message` 去掉首尾空白后，必须严格等于 `OK`。

## 重试参数

可以通过环境变量调整重试行为：

```bash
MAX_ATTEMPTS=300 INITIAL_DELAY=1 MAX_DELAY=5 ./codex-retry-ok.sh
```

参数说明：

| 参数 | 默认值 | 说明 |
| --- | ---: | --- |
| `MAX_ATTEMPTS` | `120` | 最大尝试次数 |
| `INITIAL_DELAY` | `1` | 第一次失败后的基础等待秒数 |
| `MAX_DELAY` | `15` | 退避等待的最大秒数 |

脚本在失败后会进行指数退避，并额外加入少量随机抖动，避免所有请求以完全固定的间隔重试。

## 输出行为

脚本会把 `codex exec --json` 的输出实时打印到终端。例如：

```jsonl
{"type":"thread.started","thread_id":"..."}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}
{"type":"turn.completed","usage":{"input_tokens":7028,"cached_input_tokens":0,"output_tokens":17,"reasoning_output_tokens":10}}
```

如果本次结果不是 `OK`，脚本会打印重试原因和下一次等待时间：

```text
Non-OK result, exit=0: no parseable agent OK response
Sleeping 3s before retry.
```

## 退出码

- `0`：成功拿到最终回复 `OK`。
- `1`：达到最大重试次数后仍未拿到 `OK`。
- `127`：缺少 `codex` 或 `jq` 命令。

## 注意事项

- 脚本不会写入日志文件。
- 脚本不会修改你的 Codex 配置。
- 脚本使用当前终端环境中的 Codex CLI 配置、登录状态、自定义 provider、自定义 base URL 等设置。
- 如果当前目录不是 Git 仓库，脚本中的 `--skip-git-repo-check` 会跳过 Codex 的 Git 仓库检查。
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

### 为什么要安装 jq？

脚本用 `jq` 解析 `codex exec --json` 输出的 JSONL 事件，并从中提取最后一条
`agent_message.text` 来判断是否成功。

### 会不会使用 API key？

脚本本身不设置 API key。它只调用本机的 `codex exec`，因此认证方式取决于你当前
Codex CLI 的配置和登录状态。
