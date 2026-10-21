# Sage-A1.5 × PolyStrata 精确线（2026-10-21）

只保留精确线；有损极速线已退役到 `E:\rlab\20-生产\PRJ-SAGE\交付\_retired\`。
引擎已更新到代码级四项后的 `build-p3\strata-poly.exe`（**65,665,536 B / 2026-10-21 19:22:35**；旧 exe 备份在 `_backups\code-round-20261021\`）。

## CLI

```powershell
pwsh -ExecutionPolicy Bypass -File "E:\rlab\20-生产\PRJ-SAGE\交付\exact.ps1" `
  -Prompt "E:\models\Sage-A1.5\poly\tok\prompt_ids_8k_task.txt" `
  -MaxContext 16384 -MaxNew 256
```

- 2K/256：**193.10 tok/s**（单次），**256/256 ≡ D0**（位同）。
- 8K 任务：prefill **3478.1 tok/s**、TTFT **2.359 s**。
- 32K（`-MaxContext 36864`）：prefill **3231.9 tok/s**、TTFT **10.14 s**，无 arch/几何/`idx_top_k` 报错。
- EOS：给 1024 预算时 **274 token 自然停**，末位 **248046 `<|im_end|>`**，答复 `1+1等于2。`。

## serve

配置（无 BOM；args 不含 `--serve`）：
- 4K：`E:\rlab\20-生产\PRJ-SAGE\交付\sage-serve-exact-b64.json`（port 8191，budget 64）
- 32K：`E:\rlab\20-生产\PRJ-SAGE\交付\sage-serve-exact-32k.json`（port 8192，budget 16，`--max-context 36864`）

启动（从 `...\PolyStrata` 目录）：

```powershell
python -m serve.server --engine strata `
  --config "E:\rlab\20-生产\PRJ-SAGE\交付\sage-serve-exact-b64.json" --port 8191
```

- 4K：`/health` 6 s；两条请求 HTTP 200/200、`finish_reason=stop`、content `1+1等于2。` / `1+1 equals 2.`；正文无 `<|im_end|>`；双轮英文正确。
- 32K：HTTP 200、`stop`；新 exe prefill **3198.0 tok/s**、TTFT **10.253 s**、decode 136.0；`prompt_tokens=32789`。content 在 `max_tokens=16/budget=8` 下为空是预算不足，不是回归（T16 用 64 出过 50 字正确答复）。
- server 启动自证 `end-of-reply ids: 248044,248046`。
- 引擎日志写到 config 的 `log` 字段（`serve-exact.log`），不是 server stdout。

## 代码级四项（已编译进新 exe）

- **I4 route 单遍**：位精确，2K/256 256/256 ≡ D0；decode 193.10（单次；未 ABBA）。
- **Q2 KV 行回收**：默认 **off**；`STRATA_KV_RECLAIM=1` 才开。已验证 `attention cache reclaimed to 4096 rows (STRATA_KV_RECLAIM=1)`（32K→2K）；`=0` 无此行。
- **I10 prompt-cache root/tail**：`--prompt-cache-root`、`--prompt-cache-tail` 已接线，默认 0 = 现行为；**tail=64 在 4 轮里无增益（reused 2089 vs 2111，反而少 22）**，不进默认交付；root 2 轮无回归。
- **NaN 守卫**：默认开（`STRATA_NAN_GUARD=0` 才关）；正常路径零影响、256 ids ≡ D0；注入路径仍红（丢 KV 清不掉 GDN persistent recurrence，pre-existing），只保证“检测”，恢复缺口未闭。

## 结论

- 精确线：CLI 2K/8K/32K、EOS、serve 4K/32K、system/模板、双轮，均已跑通。
- 位同口径：2K/256 的 256 ids 与 D0 逐位一致；serve 正文无 eos 字面（正文非空，非真空）。
- 有损极速线不再交付；历史读数见 `_retired\README-双线-历史.md` 与 `KP-SAGE-0008`。

## 未验

- 262K 全上下文；vision；8GB 档；serve 进程内“专家全驻”无直接日志行（只有 `expert cache 100.0% hit` + nvidia-smi）。
- `<|im_end|>` 是“被裁”还是“没生成”无裁剪计数器；n=1；流式未测。
- Q2 的 `/slots` 并排 slot 数；I10 root 4 轮；tail 更长对话；NaN 恢复根因/修法；8K/32K ABBA。
