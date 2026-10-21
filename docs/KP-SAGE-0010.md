---
id: KP-SAGE-0010
title: 代码级四项落地：I4 位精确、Q2 回收已验证、I10 root/tail 有开关（tail 无增益）、NaN 守卫默认开（恢复缺口）
one_line: I4 route 单遍 256/256 ≡ D0；Q2 32K→4096 行回收有硬证据（默认 off）；I10 root/tail 已接线，tail 4 轮无增益；NaN 默认开、正常零影响，注入后恢复仍红（GDN 持久态，pre-existing）。
kind: 实测
status: 现行
review: 待复核
entity: PRJ-SAGE
gen_born: G1
gen_valid: [G1]
confidence: 实测
evidence: "T17/T18/T19/T20 A；BUILD_EXIT=0；exact 回归 256/256 ≡ D0"
source: "E:/rlab/20-生产/PRJ-SAGE/详细/T19-I10tail与证据-20261021.md"
source_lines: 1-180
source_anchor: 代码级四项（2026-10-21）
ttl_days: 365
verified_at: 2026-10-21
supersedes: []
aliases: [I4, Q2, I10, NaN 守卫, 代码级四项]
symptoms: [route 单遍, KV 回收, prompt-cache tail, NaN 守卫, 代码级做完没]
---

## 结论
- **I4 route 单遍**：`qwen35.cpp:336-354` 改 32 槽单遍；**2K/256 的 256 ids ≡ D0**（sha16 `247486469173b0cf`）；新 exe decode **193.10 tok/s**（单次，旧 190.36；未 ABBA，不报百分比结论）。
- **Q2 KV 行回收**：`Engine::reclaim_kv` + env `STRATA_KV_RECLAIM=1`（默认 off）。硬证据：`serve-exact.log` 有 `attention cache reclaimed to 4096 rows (STRATA_KV_RECLAIM=1)`（32K 请求后 2K 请求）；`=0` 跑 32K→2K 新增日志 0 条 reclaim ⇒ **开/关两边都有证据**。
- **I10 root/tail**：`--prompt-cache-root` 与 `--prompt-cache-tail` 已接线（默认 0 = 现行为）；root 2 轮无回归；**tail=64 在 4 轮对话中无增益**（轮4 reused 2089 vs 2111，反而少复用 22）⇒ **不进默认交付档**；4 轮 root 对照未跑。
- **NaN 守卫**：默认开（`STRATA_NAN_GUARD=0` 才关）；正常路径无 guard 行、**256 ids ≡ D0**；**注入路径仍红**：`nan guard ... dropping KV + rerun` 两次后 `ERR nan guard: non-finite logits again after the rerun`，0 token。**判读：守卫会检测；丢 KV 清不掉 GDN 的 persistent recurrence，pre-existing 缺口，不是本次引入。**
- **构建**：T17 第一次 exit 2（`reclaim_kv` 访问权限），移 public 后 **exit 0**；T19 tail 再编 **BUILD_EXIT=0**。新 exe **65,665,536 B / 2026-10-21 19:22:35**；备份 `_backups\code-round-20261021\`。
- **T18 更正**：引擎 stderr **不是没转发**，而是写到 config 的 `log` 字段（`serve-exact.log`）；T18 找错了文件。
- **新 exe exact 回归**：2K/256 **256/256 ≡ D0**；8K prefill **3478.1**/TTFT **2.359 s**；32K **3231.9**/TTFT **10.14 s**；serve 32K HTTP 200、prefill **3198.0**/TTFT **10.253 s**；与旧 exe 差 −1.96%/+0.28%/+0.98%，同噪声量级，未 ABBA。

## 判据 / 负控
- I4：256 ids 与 D0 逐位；不同即红。
- Q2：`=1` 必须有 `attention cache reclaimed` 行，`=0` 必须 0 条；slot 数并排未抓（未验）。
- I10 tail：默认 0 不改变任何 checkpoint；tail=64 的复用数不得低于 tail=0 才能算增益；实测低 22 ⇒ 判无增益。
- NaN：正常路径不得出现 guard 行；注入必须检测到；本轮注入恢复失败 ⇒ 判“守卫检测有效、恢复缺口未闭”。

## 未验
- Q2 的 `/slots` 并排 slot 数；I10 root 4 轮；tail 更长对话；NaN 恢复的根因/修法；n=1；8K/32K 的 ABBA 未跑。

## 指针
- 报告：`T17-代码级四项-20261021.md`、`T18-代码级运行时验证-20261021.md`、`T19-I10tail与证据-20261021.md`、`T20-新exe最终回归-20261021.md`
- 备份：`E:\视频\_flashnext\experiments\20261015-nemotron-on-strata\_backups\code-round-20261021\`（5 源文件 + 旧 exe）
- 交付：`E:\rlab\20-生产\PRJ-SAGE\交付\README-精确线.md`、`exact.ps1`、`sage-serve-exact-b64.json`、`sage-serve-exact-32k.json`
- 相关：`KP-SAGE-0009`（精确线收口）

> **2026-10-21 更新（只加指针）**：Sage-256K 已接入 DSH（`sage-local`，8193）；并发 2/3/4 实测 FIFO（N×0.50 s、聚合 211）。见 `KP-SAGE-0011`。
