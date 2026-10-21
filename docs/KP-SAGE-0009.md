---
id: KP-SAGE-0009
title: 精确线收口：CLI 2K/8K/32K + EOS 274 stop + serve 4K/32K 模板双轮；极速线退役
one_line: 2K 190.36/256-of-256；8K prefill 3547.8；32K 3223/TTFT 10.17；serve 32K 3166.9/decode 150.6、一句话正确；EOS 274 token/248046；server EOS 248044+248046；有损极速线退役。
kind: 实测
status: 现行
review: 待复核
entity: PRJ-SAGE
gen_born: G1
gen_valid: [G1]
confidence: 实测
evidence: "T13/T14/T15/T16 A；CLI+serve 均 exit 0/200；0 残留"
source: "E:/rlab/20-生产/PRJ-SAGE/详细/T16-serve-32K-20261021.md"
source_lines: 1-160
source_anchor: 精确线收口（2026-10-21）
ttl_days: 365
verified_at: 2026-10-21
supersedes: []
aliases: [精确线, exact line, Sage serve, 32K serve, EOS 248046]
symptoms: [精确线怎么跑, serve 怎么起, 32K 能不能跑, EOS 会不会停]
---

## 结论
- **精确线 = 默认 prefill（batch1024/every2048）+ `--window 4 --lookup 0`**；不带有损 batch/every0。
- CLI：2K/256 = **190.36 tok/s、256/256 ≡ D0**；8K 任务 prefill **3547.8**、TTFT **2.313 s**；32K prefill **3223.0**、TTFT **10.166 s**，无 arch/几何/`idx_top_k` 报错。
- EOS：给 1024 预算时 **274 token 自然停**，末位 **248046 `<|im_end|>`**，答复 `1+1等于2。` ⇒ 引擎会停；T13 的 256 未命中是预算不足。
- serve（4K，budget 64）：`/health` 6 s；两条请求 HTTP 200/200、`finish_reason=stop`、content `1+1等于2。` / `1+1 equals 2.`；正文无 `<|im_end|>`；双轮英文正确。
- serve（32K，budget 16）：HTTP 200、`stop`、一句话正确；**prefill 3166.9 tok/s、decode 150.6 tok/s**（`prompt_tokens=32789`，10.70 s），比 CLI 32K 只低 1.7%。
- server 启动自证 `end-of-reply ids: 248044,248046`（tokenizer 推导 + 补 248044）。
- **有损极速线退役**：`speed.ps1`/双线 README 移到 `交付\_retired\`；不再交付。

## 判据 / 负控
- 精确线：2K/256 的 256 ids 必须 ≡ D0；8K/32K 默认 prefill 下与 exact 基线逐位比。
- EOS：`finish=(stop)` + 末位 248046；serve 正文非空且无 eos 字面（本轮真测，不是真空）。
- serve：HTTP 200 + `finish_reason=stop` + content 非空 + 双轮语义正确。
- 负控：256 预算时 EOS 未命中（T13），说明“停”不是默认发生；有损档 first_diff 56（T11/T12），说明 batch 变会整段分岔。

## 未验
- 262K 全上下文、vision、8GB 档；serve 进程内“专家全驻”无直接日志行（只有 `expert cache 100.0% hit` + nvidia-smi）。
- `<|im_end|>` 是“被裁”还是“没生成”无裁剪计数器；n=1；流式未测。
- 代码级 Q2/I4/I10/NaN 未动引擎树，属于性能/稳定性后续，不是精确线的前置。

## 指针
- 报告：`E:\rlab\20-生产\PRJ-SAGE\详细\T13-EOS与32K-20261021.md`、`T14-EOS与serve-20261021.md`、`T15-serve-答复与EOS-20261021.md`、`T16-serve-32K-20261021.md`
- 交付：`E:\rlab\20-生产\PRJ-SAGE\交付\README-精确线.md`、`exact.ps1`、`sage-serve-exact-b64.json`、`sage-serve-exact-32k.json`
- 历史：`KP-SAGE-0008`（有损双线）、`_retired\README-极速线-已退役.md`

> **2026-10-21 更新（只加指针，不改上文结论）**：代码级四项（I4/Q2/I10/NaN）已编入新 exe `65,665,536 B / 19:22:35`，回归：2K 193.10、8K 3478.1、32K 3231.9、serve 32K 3198.0；I4 位精确、Q2 回收有硬证据、I10-tail 无增益、NaN 注入恢复仍红。见 `KP-SAGE-0010`。
