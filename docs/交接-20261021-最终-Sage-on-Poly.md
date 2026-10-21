# 交接：Sage-A1.5 on PolyStrata（最终，2026-10-21）

> **这是当前唯一入口。** 旧 v0139 交接保留为历史，不要按它施工。
> 状态：精确线已收口；256K 服务已常驻；DSH 已接；代码级四项已编译；思考循环已修。**当前无待跑的 GPU 作业。**

---

## 0. 一句话

**Sage-A1.5 Q4_K_M 跑在 `PolyStrata 0.1.44.1` 的 `strata-poly.exe` 上；精确线 = 默认 prefill + `--window 4 --lookup 0`（MTP）；256K 常驻在 `127.0.0.1:8193`；DSH 里选 `sage-local` 即可体验。**

---

## 1. 先读顺序（必须读的指针）

1. 项目章程：`E:\rlab\20-生产\PRJ-SAGE\CHARTER.md`
2. 项目共识：`E:\rlab\20-生产\PRJ-SAGE\AGENTS.md`
3. **本交接**：`E:\rlab\20-生产\PRJ-SAGE\详细\交接-20261021-最终-Sage-on-Poly.md`
4. 精确线卡：`E:\rlab\20-生产\PRJ-SAGE\索引\KP-SAGE-0009.md`
5. 代码级卡：`E:\rlab\20-生产\PRJ-SAGE\索引\KP-SAGE-0010.md`
6. DSH/并发卡：`E:\rlab\20-生产\PRJ-SAGE\索引\KP-SAGE-0011.md`
7. **循环修复卡（必读）**：`E:\rlab\20-生产\PRJ-SAGE\索引\KP-SAGE-0012.md`（#2029：恢复为什么空转、怎么修的、边界在哪）
8. 最终回归：`E:\rlab\20-生产\PRJ-SAGE\详细\T20-新exe最终回归-20261021.md`
9. 并发报告：`E:\rlab\20-生产\PRJ-SAGE\详细\T21-并发1-4-20261021.md`
10. 思考循环诊断：`E:\rlab\20-生产\PRJ-SAGE\详细\诊断-思考循环-20261021.md`
11. 精确线说明：`E:\rlab\20-生产\PRJ-SAGE\交付\README-精确线.md`
12. DSH 接入：`E:\rlab\20-生产\PRJ-SAGE\交付\DSH-接入-Sage-256K.md`
13. 历史/已推翻项：`KP-SAGE-0004`（MTP 根因）、`0005`（prefill 有损）、`0006`（q36 拒载）、`0007`（零改码收口）、`0008`（有损双线，已退役）

---

## 2. 当前运行状态（2026-10-21 19:40 左右）

| 项 | 值 |
|---|---|
| 服务 | `http://127.0.0.1:8193/v1`（OpenAI 兼容） |
| 模型 id | `sage-a1.5-q4_k_m` |
| 上下文 | `/v1/models`、`/props`、`/health` 均 **262144** |
| 参数 | `--max-context 262144 --window 4 --lookup 0`；默认 prefill（batch 1024 / every 2048） |
| 思考 | 模板默认开；`reasoning_budget_tokens: 0`（无上限）；**`reasoning_loop_recovery: "recover"`** |
| 进程 | `python` PID **21464**；`strata-poly` PID **20896**（以实际 `Get-Process` 为准） |
| 显存 | **~28,557 / 32,760 MiB**；只许这一个引擎 |
| 端口 | 8193 LISTEN；8191/8192 空闲 |
| DSH | 桌面 `cordis.patch.yml` 已加 `sage-local`；**需重启 DSH 才读** |

**停止**：
```powershell
Stop-Process -Id 21464 -Force
Get-Process strata* -ErrorAction SilentlyContinue | Stop-Process -Force
```

**重启**：
```powershell
$env:PATH = "E:\cuda-13.3\bin\x64;" + $env:PATH
cd "E:\视频\_flashnext\experiments\20261015-nemotron-on-strata\PolyStrata"
python -m serve.server --engine strata `
  --config "E:\rlab\20-生产\PRJ-SAGE\交付\sage-serve-exact-256k.json" --port 8193
```

---

## 3. 靶子与最终决策

- **主靶**：`E:\视频\_flashnext\experiments\20261015-nemotron-on-strata\PolyStrata\build-p3\strata-poly.exe`（PolyStrata 0.1.44.1；sha256 `03885b24…26b`；当前 exe **65,665,536 B / 2026-10-21 19:22:35**，含代码级四项）。
- **权重**：`E:\models\Sage-A1.5\gguf-q4\Sage-A1.5-Q4_K_M.gguf`（21,713,463,520 B；sha256 `a64fe0bb…8ca395`）；mmproj 未验。
- **精确线**：默认 prefill + `--window 4 --lookup 0`；**不带** `--prompt-batch` / `--prompt-cache-every 0`（有损）。
- **256K**：`--max-context 262144`；MTP window4；思考无上限 + 循环恢复。
- **出局**：`E:\strata-v01431` / 生产 `E:\strata`（0.1.43.1 只认 qwen4exp）；q36 路径（拒载 `ssm_alpha` Q4_K）；GDN 移植（2.86× 核已在 poly）。
- **未启动**：ninfer v2（B-A/B-B）；8GB 档（用户说先不管）；vision。

---

## 4. 成果/读数（A 级为主）

### 4.1 精确线

| 场景 | 读数 |
|---|---|
| CLI 2K/256 | **193.10 tok/s**；**256/256 ≡ D0**（sha16 `247486469173b0cf`） |
| CLI 8K 任务 | prefill **3478.1 tok/s**、TTFT **2.359 s**、256 token `(length)` |
| CLI 32K | prefill **3231.9 tok/s**、TTFT **10.14 s**、无 arch/几何/`idx_top_k` 错 |
| serve 32K | HTTP 200、prefill **3198.0**、TTFT **10.253 s**、decode 136.0 |
| EOS（CLI 1024 预算） | **274 token 自然停**、末位 **248046 `<|im_end|>`**、答复 `1+1等于2。` |
| serve 4K | 200/`stop`；`1+1等于2。` / `1+1 equals 2.`；正文无 `<|im_end|>` |
| serve EOS 集合 | 启动自证 `end-of-reply ids: 248044,248046` |

### 4.2 代码级四项（已编译进当前 exe）

| 项 | 结果 |
|---|---|
| I4 route 单遍 | 2K/256 的 256 ids ≡ D0；decode 193.10（单次，未 ABBA） |
| Q2 KV 行回收 | `STRATA_KV_RECLAIM=1`：`attention cache reclaimed to 4096 rows`；`=0`：0 条；默认 off |
| I10 root/tail | 开关已接线；root 2 轮无回归；**tail=64 在 4 轮里无增益**（reused 2089 vs 2111），不进默认 |
| NaN 守卫 | 默认开；正常路径零影响、256 ids ≡ D0；**注入恢复仍红**（丢 KV 清不掉 GDN persistent state，pre-existing） |

### 4.3 DSH / 并发 / 循环

- DSH：`sage-local` 已加 provider + allowedModels；模型 `sage-a1.5-q4_k_m`；重启 DSH 后可选。
- 并发：`strata-poly` **无 `--batch`/`BGEN`**；`/slots` 一个槽；2/3/4 并发 = FIFO，总墙钟 ≈ **N×0.50 s**，聚合恒 ~**211 tok/s**，无并行加速。
- 循环：根因 = **请求无 temperature ⇒ 服务端默认 greedy**（`serve/server.py:785-786`；`src/poly/main.cpp:83/101`）+ `reasoning_loop_recovery` 默认 false（`server.py:7244`）。已开 `"recover"`；检测重复后抬 temp≥1.0/presence≥1.5、低 effort 续跑；单测 **18/18 OK**；日志 `repeated reasoning detected at 2048 tokens`。
  - **⚠️ 上一条“已修”已被证伪（2026-10-21 20:0x）**：恢复必须在 system 消息里找到 `Reasoning effort is set to xhigh. …`，DSH 的 prompt 里没有 ⇒ `focused_recovery_prompt()` 返回 `None`，日志/抬温度全在 `if recover_prompt is not None` 里 ⇒ **从未执行**。已重修为兜底 + 两次恢复 + 收尾 wrap，单测 **20/20**。证据与边界见 `E:\rlab\20-生产\PRJ-SAGE\索引\KP-SAGE-0012.md`。

---

## 5. 已推翻/不要再写

1. **“v1 只能是 v0139”**：错。PolyStrata 1.44.1 直读 Q4_K_M，已跑通。
2. **“Q4 格式不支持”**：错。poly 有 rank-3 GgufBlocks/MMQ；缺的是 qwen3_5 没接，不是格式。
3. **“150.05 tok/s”**：不能引；归因也不是 PLE-off（Cyber 无 PLE 表）；真因是 z 闸门修复前的乱码，同 regime 有效值 152.11。见 `KP-SAGE-0003`。
4. **“Poly 的 D_FMTS 缺 Q4_K 所以不能用”**：范围错。缺的是 native IQ 分组核；`strata-poly` 的 GGUF/MMQ 路径 Q4_K 在册。
5. **“prefill batch2048/4800 无损”**：错。8K 任务 first_diff=15/49/56；+40% 是有损快档，已退役。
6. **“MTP window8 可用”**：错。window8 自第 70 token 分岔；window4 才 128/128、256/256 位同。
7. **“q36 路径可零改码”**：错。拒载 `blk.0.ssm_alpha.weight is Q4_K`；要新 GGUF 或改类型表。
8. **“NaN 守卫能恢复”**：检测有效，GDN 持久态恢复仍红；不要写成已修。

---

## 6. 配置/文件

- 精确线 CLI：`E:\rlab\20-生产\PRJ-SAGE\交付\exact.ps1`
- 256K serve：`E:\rlab\20-生产\PRJ-SAGE\交付\sage-serve-exact-256k.json`（已有 `reasoning_loop_recovery: "recover"`；另有 `-nocap` 历史副本）
- 4K/32K serve：`sage-serve-exact-b64.json`、`sage-serve-exact-32k.json`
- DSH 桌面：`C:\Users\Administrator\.dsh\profiles\desktop\cordis.patch.yml`（`sage-local`）；备份 `...bak-20261021-before-sage`
- DSH headless：`E:\视频\_agents\ownerwake\mcp\local-sage.patch.yml`
- 测试脚本：`E:\rlab\20-生产\PRJ-SAGE\交付\test_sage256k.py`
- 旧有损线：`交付\_retired\`（已退役，不交付）

**关键源码落点**（改前先读）：
- greedy 默认：`serve/server.py:785-786`；采样默认：`src/poly/main.cpp:83/101`
- 循环恢复：`serve/server.py:4546-4651, 7244-7250`；回归 `serve/test_reasoning_loop_recovery.py`
- I4：`src/poly/qwen35.cpp:336-354`
- Q2：`src/poly/engine.cpp:961`；调用 `src/poly/main.cpp:857`
- I10：`src/poly/conversations.hpp`
- NaN：`src/poly/main.cpp:521-524, 689-711`

---

## 7. 未验/下一步

- **256K 全上下文实跑**：只起了服务，没有发 256K prompt；32K 已实测。
- **vision**：mmproj 未加载；`strata-vision` 版本不同步。
- **8GB/KV in RAM**：未做（用户说先不管）。
- **ninfer v2**：B-A/B-B 未启动。
- **NaN 恢复**：注入路径仍红；要修需清 GDN persistent state。
- **Q2**：`/slots` 并排 slot 数未抓；默认 off。
- **I10**：root 4 轮未跑；tail 无增益。
- **并发**：N>4、冷缓存对照未做；poly 无 batch 是结构限制。
- **循环恢复**：已修好“无 effort 句客户端”的静默空转（`KP-SAGE-0012`），单测 20/20；**但**内容级循环、跨请求的工具循环（headless 里 `list_agents→job_output` 报 unknown job、覆盖 0.224）都不在服务端检测范围；自然长任务循环未稳定复现（原样回放不循环）。

---

## 8. 回滚/备份

- 代码级备份：`E:\视频\_flashnext\experiments\20261015-nemotron-on-strata\_backups\code-round-20261021\`（5 源文件 + 旧 exe）
- 旧 exe：`build-p3\strata-poly.exe.bak-pre-code`（产出全部旧 T 线读数的版本）
- DSH 配置备份：`C:\Users\Administrator\.dsh\profiles\desktop\cordis.patch.yml.bak-20261021-before-sage`
- 有损线历史：`E:\rlab\20-生产\PRJ-SAGE\交付\_retired\`

---

## 9. 变更记录

- 2026-10-21：v0139 调研/交接；转 PolyStrata；精确线收口；MTP window4；EOS/32K/serve；代码级 I4/Q2/I10/NaN；DSH 接入；并发 FIFO；思考循环修复（greedy + recovery）。
