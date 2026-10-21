---
id: KP-SAGE-0011
title: Sage-256K 接入 DSH + 并发 FIFO 判定（poly 无 batch）
one_line: 8193 常驻 256K/MTP/思考无上限；DSH 桌面加 sage-local；并发 2/3/4 为 FIFO N×0.50 s、聚合 211 tok/s，无并行加速。
kind: 实测
status: 现行
review: 待复核
entity: PRJ-SAGE
gen_born: G1
gen_valid: [G1]
confidence: 实测
evidence: "T21 A；/v1/models n_ctx=262144；/props 262144；并发墙钟 N×0.50 s"
source: "E:/rlab/20-生产/PRJ-SAGE/详细/T21-并发1-4-20261021.md"
source_lines: 1-160
source_anchor: 并发 1/2/3/4（2026-10-21）
ttl_days: 365
verified_at: 2026-10-21
supersedes: []
aliases: [DSH Sage, Sage 256K, 并发 234, poly batch]
symptoms: [Sage 怎么接 DSH, 并发多少, 256K 怎么起, 思考无上限]
---

## 结论
- **256K 服务**：`sage-serve-exact-256k.json`，port **8193**，`--max-context 262144 --window 4 --lookup 0` + 默认 prefill（精确线）；`/v1/models` `sage-a1.5-q4_k_m`、`meta.n_ctx=262144`；`/props` 262144；启动 `10496/10496` 专家、18.7 GiB、显存 28,591 MiB。
- **DSH 桌面**：`cordis.patch.yml` 的 `llm-pi-ai` 下加 `sage-local`（`http://127.0.0.1:8193/v1`，256K，reasoning high）；备份 `cordis.patch.yml.bak-20261021-before-sage`；**DSH 需重启一次**才会显示。默认模型未改（本会话仍是 deepseek-flash）。
- **DSH headless**：`E:\视频\_agents\ownerwake\mcp\local-sage.patch.yml`，`dsh_run(patch=...)` / `dsh headless --patch`。
- **思考**：`reasoning_budget_tokens: 0` = 无上限，模板默认开；实测 1+1 **1024 token 全在 thinking、content 空、finish=length**。DSH `maxTokens=65536`，可能想很久/到顶仍无答复；要答案需加 `reasoning_budget_tokens`（256/1024）或调大 max_tokens。
- **并发**：`strata-poly` 无 `--batch`/`BGEN`/`batch_slots`（源码 0 命中），`/slots` 一个槽 ⇒ FIFO 串行。实测 N=2/3/4 总墙钟 **1.00/1.51/2.01 s ≈ N×0.50 s**，每条延迟按队列位置 0.50 s 等间距，聚合恒 **211 tok/s**（N=1 是冷 prefill，不能拿 87.7 比）。
- **口径污染**：N=1 冷、N≥2 命中会话缓存；干净判据只有“总墙钟=N×0.50 s + 延迟等间距”。

## 判据 / 负控
- 服务：`/v1/models` 的 `n_ctx` 与 `--max-context` 一致；`/props` 同。
- 并发：N=4 总墙钟 ≈0.5–0.7 s ⇒ 真并行；≈2.0 s ⇒ FIFO。本机实测 2.01 s。
- 思考：无预算时 content 空/`length` 是符合“无上限”的行为，不是故障；加预算后 content 应出现。

## 未验
- N=1 冷缓存 vs 热缓存的并发对照；N>4；`/v1/status last_timings` 未用于佐证；DSH 桌面重启后的实际显示/选择未由本席点验；DSH headless 未用 local-sage patch 实跑。
- 256K 全上下文实跑（只起服务，未发 256K prompt）；vision；8GB。

## 指针
- 接入说明：`E:\rlab\20-生产\PRJ-SAGE\交付\DSH-接入-Sage-256K.md`
- 配置：`sage-serve-exact-256k.json`；桌面 patch 备份同上
- 并发报告：`E:\rlab\20-生产\PRJ-SAGE\详细\T21-并发1-4-20261021.md`
- 数据：`E:\models\Sage-A1.5\poly\logs\t21-concurrency.json`

> **2026-10-21 诊断/修复（只加新结论）**：DSH 里 Sage Agent 的思考循环，根因 = **请求无 temperature ⇒ 服务端默认 greedy** + `reasoning_loop_recovery` 默认 **false**（`serve/server.py:7244`），不是高温。已在 `sage-serve-exact-256k.json` 开 `"reasoning_loop_recovery": "recover"` 并重启；单测 18/18，日志 `repeated reasoning detected at 2048 tokens`。证据/负控见 `E:\rlab\20-生产\PRJ-SAGE\详细\诊断-思考循环-20261021.md`。
