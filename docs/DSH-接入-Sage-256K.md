# DSH 接入 Sage-A1.5 256K（2026-10-21）

## 服务

- 配置：`E:\rlab\20-生产\PRJ-SAGE\交付\sage-serve-exact-256k.json`
- 端口：`8193`（OpenAI 兼容：`/v1/chat/completions`、`/v1/models`、`/props`）
- 模型 id：`sage-a1.5-q4_k_m`；`n_ctx=262144`；`--window 4 --lookup 0`（MTP 开）；默认 prefill（精确线）
- 当前进程：`python` PID 24800；`strata-poly` PID 16864；显存 **28,591 / 32,760 MiB**
- 重启命令（从 PolyStrata 目录，PATH 前置 CUDA 13.3）：
```powershell
$env:PATH = "E:\cuda-13.3\bin\x64;" + $env:PATH
cd "E:\视频\_flashnext\experiments\20261015-nemotron-on-strata\PolyStrata"
python -m serve.server --engine strata `
  --config "E:\rlab\20-生产\PRJ-SAGE\交付\sage-serve-exact-256k.json" --port 8193
```

## DSH 桌面

- 已加 provider `sage-local` 到 `C:\Users\Administrator\.dsh\profiles\desktop\cordis.patch.yml`（`llm-pi-ai` 下）。
- 备份：`...\cordis.patch.yml.bak-20261021-before-sage`
- 模型：`sage-a1.5-q4_k_m`，显示名 `Sage-A1.5 Q4_K_M（256K · 思考默认开 · MTP）`
- **当前 DSH 进程要重启一次**才会读新 provider；重启后模型选择器里选它。
- 没改默认模型（当前会话仍是 deepseek-flash），所以不影响本会话。

## DSH headless

- 独立 patch：`E:\视频\_agents\ownerwake\mcp\local-sage.patch.yml`
- 用法：`dsh_run(prompt=..., patch="E:\视频\_agents\ownerwake\mcp\local-sage.patch.yml")`，或 `dsh headless --patch <该文件> "<prompt>"`。

## 思考

- 配置 `reasoning_budget_tokens: 0` = **无上限**；模板默认 `enable_thinking`（开）。
- 实测（1+1）：**1024 token 全在 thinking，`finish=length`，content 为空**；`reasoning_content` 3239 字符。
- 无上限的代价：客户端 `max_tokens` 会被思考吃掉；DSH 里 `maxTokens=65536`，可能想很久才出答复/或到顶仍无答复。
- 要让它“先想一点再回答”，在请求里加 `reasoning_budget_tokens`（如 256/1024），或在 config 里把 0 改成该值。

### 思考循环（2026-10-21 实测 + 已修）

- DSH 请求头没有 temperature ⇒ 服务端默认 **greedy**；循环不是高温，是贪婪。
- 256K 配置已开 **`reasoning_loop_recovery: "recover"`**：检测到重复思考后，把 temperature 抬到 ≥1.0、presence_penalty 抬到 ≥1.5，用低 effort 指令续跑（top_p/top_k 不动，只恢复一次）。
- 证据：服务日志 6,031 thinking 后 `disconnect`；单测 `python -m unittest serve.test_reasoning_loop_recovery -v` ⇒ **18/18 OK**；服务日志有 `repeated reasoning detected at 2048 tokens`。
- 判据：开 ⇒ 出现 `repeated reasoning detected`；关 ⇒ 只有一遍、无 recovery 行。完整诊断：`E:\rlab\20-生产\PRJ-SAGE\详细\诊断-思考循环-20261021.md`。

## 当前进程

- `python` PID **21464**、`strata-poly` PID **20896**；显存 **28,557 / 32,760 MiB**。
- 配置已含 `reasoning_loop_recovery: "recover"`。

## 并发

- `strata-poly` **没有 `--batch`/`BGEN`/`batch_slots`**；`serve/server.py` 读不到 `INFO batch_slots` ⇒ **一个槽、FIFO 串行**。
- 实测：N=2/3/4 总墙钟 ≈ **N × 0.50 s**；每条延迟 = 队列位置 × 0.50 s；聚合恒 ~**211 tok/s**。
- ⇒ 2/3/4 并发**没有加速**；后到请求只是排队。DSH 单用户没问题；多用户要换有 batch 的引擎/路径。

## 停止

```powershell
Stop-Process -Id 24800 -Force
Get-Process strata* -ErrorAction SilentlyContinue | Stop-Process -Force
```
或直接关闭 server 窗口（若从窗口起）。

## 判据

- `/v1/models` 返回 `sage-a1.5-q4_k_m` 且 `meta.n_ctx=262144` ⇒ 服务对。
- `/props` 的 `default_generation_settings.n_ctx=262144` ⇒ 上下文对。
- 并发：N=4 总墙钟若 ≈0.5–0.7 s ⇒ 真并行（本机不是）；若 ≈2.0 s ⇒ FIFO（本机实测）。
