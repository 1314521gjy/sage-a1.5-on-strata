---
id: KP-SAGE-0012
title: 思考循环恢复对“无 effort 句”客户端静默空转——根因与修复（#2029）
one_line: DSH 的 system prompt 里没有 xhigh effort 句，focused_recovery_prompt 返回 None 且不打日志 ⇒ 恢复从不执行；已加兜底 + 两次恢复 + 收尾 wrap，实测循环在第 2560 token 被接住并出答案。
kind: 实测
status: 现行
review: 待复核
entity: PRJ-SAGE
gen_born: G1
gen_valid: [G1]
confidence: 实测
evidence: "会话 24×40词重复；离线重放 coverage 0.731@2560；修复后日志 repeated reasoning detected at 2560 (coverage=0.593) + content 出现；单测 20/20"
source: "E:/视频/_flashnext/experiments/20261015-nemotron-on-strata/PolyStrata/serve/server.py"
source_lines: 174-218, 4560-4660
source_anchor: reasoning_loop_recovery 空转（2026-10-21）
ttl_days: 365
verified_at: 2026-10-21
supersedes: []
aliases: [Sage 死循环, 思考循环, reasoning_loop_recovery, 恢复空转, focused_recovery_prompt]
symptoms: [Sage 长任务死循环, 只思考不回答, 恢复没生效, DSH 里转圈]
---

## 结论

- **原实现有一个静默分支**：`focused_recovery_prompt()` 必须在第一条 system 消息里找到
  `Reasoning effort is set to xhigh. …` 才返回新 prompt；找不到就 `return None`，而调用处的日志、抬温度、
  续跑全在 `if recover_prompt is not None:` 里面 ⇒ **对 DSH 这类自带 system prompt 的客户端，恢复一次都没跑过**，
  日志也不会留痕（本机 `serve-256k.log` 里 `repeated reasoning` 计数为 0）。
- **不是引擎问题**：token 正常、prefill/decode 正常；是接线（服务端恢复路径）断在锚句上。
- **已修**（`serve/server.py`）：
  1. `focused_recovery_prompt()` 兜底：锚句不存在时，把 LOW_EFFORT 句当作回复自己的后续文字接在已生成 token 后面，
     不再返回 `None`（`server.py:211` 起）。
  2. 恢复次数 `not recovery_count` → `recovery_count < MAX_LOOP_RECOVERIES(=2)`（`server.py:174, 4566`）。
  3. 第二次恢复后再给 `RECOVERY_WRAP_TOKENS(=256)` 个思考 token，随后走**已有并已验证**的 wrap-up 路径
     关闭思考、强制出答案（`server.py:4651-4656`），避免再次跑到 max_tokens。
- **根因之外的一个诱因**：256K 配置 `reasoning_budget_tokens: 0`（用户要求“思考无上限”）。模型在 greedy 下
  即使回答 `1+1` 也会自言自语到 2000+ token 才收敛；有预算的 4K/32K 配置（64 / 16）从不会出现这个现象。
  两者是取舍关系，不是故障。

## 判据 / 负控

- 正向：日志出现 `repeated reasoning detected at N tokens (coverage=…)` ⇒ 恢复真的执行。
- 负控：`reasoning_loop_recovery` 关闭时同一请求不得出现该行（单测 `test_disabled_is_one_pass` 覆盖）。
- 负控：prompt 不以 `<|im_start|>system\n` 开头（如只有 user 轮）仍应返回 `None` 跳过
  （`test_missing_native_high_hint_skips_recovery` 覆盖）。
- 答案：修复后 1+1 请求 `finish=stop`、content 非空；修复前 `finish=length`、content 空。

## 实测数字（A 级，2026-10-21 20:0x，8193 服务）

| 场景 | 修复前 | 修复后 |
|---|---|---|
| DSH 桌面任务（19:35 / 19:41 两轮） | 23,131 / 21,188 字思考，0 字正文，用户手动停 | — |
| 同一段思考离线重放 | coverage 0.731@2560 → 1.000 | 判定本应触发 |
| 1+1（无 system，max_tokens 4096） | 4096 token 全思考、content 空、`length` | 2560 token 触发恢复，2635 token `stop`，content `1 + 1 equals 2.` |
| 强制重复测试（max_tokens 8192） | — | 3584 / 6144 两次恢复，最终出 9.4 KB 正文（`length`） |
| 单测 | 18 | **20/20 OK**（新增 3 条：兜底、无锚句端到端、两次后 wrap） |

## 边界（不要写成已修）

- **内容级循环不检测**：模型若把重复搬进正文（强制测试里出现过），服务端没有对应检测，只能靠 `repeat_stop_tokens`（单 token ×256）。
- **跨请求的工具循环不检测**：headless 实跑里父代理反复 `list_agents → job_output(报 unknown job)`，跨请求发生，
  每请求内部推理覆盖率仅 **0.224**（阈值 0.25 之下），这类循环必须从 DSH 侧（提示词/工具语义）治。
- **自然长任务循环未复现**：把 DSH 记录的 prompt 原样回放（greedy / 0.6）都不循环，说明触发依赖当时上下文，未定位到唯一条件。

## 回滚

- 备份：`E:\视频\_flashnext\experiments\20261015-nemotron-on-strata\_backups\code-round-20261021b\`
  （`server.py.bak`、`test_reasoning_loop_recovery.py.bak`、`sage-serve-exact-256k.json.bak`）。
- 纯 Python 改动，不涉及 exe；回滚后重启 8193 即恢复原行为。
