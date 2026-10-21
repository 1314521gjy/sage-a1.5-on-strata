# Sage-A1.5 on Strata

把 **Sage-A1.5**（35B-A3B MoE，Qwen3.5-MoE 架构，上海 AI Lab / InternScience）的 **Q4_K_M GGUF** 跑在
**PolyStrata 0.1.44.1** 的 `strata-poly` 引擎上，单张 **RTX 4080 SUPER 32 GB**
（i7-13790F / 95.8 GiB RAM / PCIe 4.0×16）。

引擎直接读 GGUF，不经过转换；权重 **20.22 GiB**（21,713,463,520 B，
sha256 `a64fe0bbf936db3eb54f66f142c2b2eee569ade83673649f549a21daef8ca395`），
**10,496 个专家全部驻留 VRAM**（18.7 GiB），加载 7.2 s；常驻服务占显存约 **28.5 / 32.7 GiB**。

| 指标 | 读数（本机 A 级） |
|---|---|
| **prefill 8K** | **3478.1 tok/s**，TTFT **2.359 s** |
| **prefill 32K** | **3231.9 tok/s**，TTFT **10.14 s** |
| **decode（2K 上下文，256 token）** | **193.10 tok/s** |
| **serve 32K** | prefill 3198.0，TTFT **10.253 s**，decode **136.0 tok/s** |
| **上下文** | **262,144**（256K），`--max-context 262144` |
| **EOS** | CLI 1024 预算下 **274 token 自然停**，末位 `<|im_end|>` = 248046 |
| **并发** | `strata-poly` 单槽，2/3/4 并发 = **FIFO**，总墙钟 ≈ N×0.50 s，聚合恒 **~211 tok/s**（无并行加速） |

## 1. 什么是「精确线」

本仓所有读数只在一种配置下成立，称为**精确线**：

```
默认 prefill（batch 1024 / every 2048）  +  --window 4 --lookup 0（MTP 开）
```

三条边界（都是踩出来的，别再试）：

- **不加 `--prompt-batch` / `--prompt-cache-every 0`**：8K 任务 `first_diff=15/49/56`，+40% 速度是**有损**换来的，已退役。
- **MTP 用 `--window 4` 不用 8**：window8 自第 70 个 token 起分岔；window4 下 128/128、256/256 位同（`sha16 247486469173b0cf`）。
- **采样**：请求不带 `temperature` ⇒ 服务端默认 **greedy**（`serve/server.py:785`；引擎 `src/poly/main.cpp:101` 走 `most_likely`）。位同读数都基于这个前提。

## 2. 256K 常驻服务（`configs/sage-serve-exact-256k.json`）

```powershell
$env:PATH = "E:\cuda-13.3\bin\x64;" + $env:PATH
cd <repo>\PolyStrata
python -m serve.server --engine strata `
  --config .\configs\sage-serve-exact-256k.json --port 8193
```

健康检查期望：

```
GET /health → {"status":"ok","max_context":262144,"model":"sage-a1.5-q4_k_m"}
GET /props  → n_ctx = 262144
启动日志    → loaded in ~7.2 s; 10496 of 10496 routed experts in VRAM (18.7 GiB)
```

OpenAI 兼容：`POST http://127.0.0.1:8193/v1/chat/completions`，模型 id `sage-a1.5-q4_k_m`。
自带 `tokenizer/`（从 GGUF 导出，`chat_template.jinja` 在里面）。

## 3. 视觉（图片输入）

`/health` 里 `images` 应为 `true`。做法是配置加一个 `"vision"` 段，指向 **`strata-vision`**（llama.cpp `mtmd` 的封装）
与模型自带的 `mmproj`：

```json
"vision": {
  "exe":   "...\\build-vision\\bin\\strata-vision.exe",
  "mmproj": "...\\Sage-A1.5-mmproj.gguf",
  "model": "...\\Sage-A1.5-Q4_K_M.gguf",
  "threads": 16, "max_tokens": 1024, "min_tokens": 1024
}
```

`strata-vision` 需要自己编（本仓不带二进制）：

```powershell
cmake -S tools/vision -B build-vision -G Ninja -DCMAKE_BUILD_TYPE=Release `
      -DLLAMA_DIR=<llama.cpp checkout，与本机 ggml 0.24.0/3cf0325 同源> -DSTRATA_PORTABLE=OFF
cmake --build build-vision --target strata-vision
```

实测（CPU 编码，16 线程）：768×768 图变成 **1024 个图像 token**，编码约 **9–10 s**，整条请求 12.1 s，
回答内容与图一致。要更快就 `-DSTRATA_VISION_CUDA=ON` 编 GPU 版（0.1–0.5 s/图，约 1.4 GB 显存）。

客户端侧（OpenAI 协议）就是标准的 `image_url`（base64 data URL 或 http URL）：
本机 DSH 还要把模型的 `input` 声明成 `[text, image]`，否则界面不会让你发图。

## 4. 思考循环：本仓带的补丁（`patches/0001-reasoning-loop-recovery-2029.patch`）

Sage 在 greedy 下会陷入重复思考（同一段话原样重复 20+ 次），服务端 `reasoning_loop_recovery` 本该接住它，
但上游实现有一个**静默空转**：

- 恢复要求 system 消息里有 `Reasoning effort is set to xhigh. …`；客户端（DSH 等）自带 system prompt 时没有这句
  ⇒ `focused_recovery_prompt()` 返回 `None` ⇒ 日志、抬温度、续跑全在 `if recover_prompt is not None:` 里 ⇒ **一次都没执行**。
- 后果：思考一路跑到 `max_tokens`，`content` 为空，用户只能手动停。

补丁（3 处，纯 Python）：

1. **兜底**：没有 effort 句时，把 LOW_EFFORT 那句当作回复自己的后续文字接在已生成 token 后面；
2. **两次**：`recovery_count < 2`；
3. **收尾**：第二次恢复后只给 256 个思考 token，随后走既有 wrap-up 路径关掉思考、强制出答案。

实测（8193，A 级）：

| 场景 | 修前 | 修后 |
|---|---|---|
| 1+1，`max_tokens=4096` | 4096 token 全思考、`content` 空、`finish=length` | 2560 token 触发恢复，2635 token `finish=stop`，`content=1 + 1 equals 2.` |
| DSH 桌面长任务 | 23,131 字思考、0 字正文、手动停 | 恢复日志 `repeated reasoning detected at 2560 tokens (coverage=0.593)` |
| 回归单测 | 18 条 | **20/20 OK**（`serve/test_reasoning_loop_recovery.py`） |

**边界（别当已修）**：只检测**单次回复内的思考重复**。内容级循环、跨请求的工具循环（如反复
`list_agents → job_output` 报错，单请求覆盖率仅 0.224 < 阈值 0.25）都不在服务端检测范围。

## 5. 一个取舍：`reasoning_budget_tokens: 0`

256K 配置用**思考无上限**（`reasoning_budget_tokens: 0`）。代价：greedy 下连 `1+1` 都可能自言自语
2000+ token 才收敛，`max_tokens` 给小了（<3000）会全花在思考上、正文为空。
旧的 4K/32K 配置用的是 **64 / 16**，所以秒答——那是预算截断，不是模型更快。

## 6. 仓库结构

```
configs/   sage-serve-exact-{256k,32k,b64}.json     三档 serve 配置（256K / 32K / 4K）
scripts/   exact.ps1                               精确线 CLI 启动器
           test_sage256k.py                       256K 冒烟测试
patches/   0001-reasoning-loop-recovery-2029.patch  思考循环修复（对 PolyStrata 0.1.44.1）
serve/     test_reasoning_loop_recovery.py          循环恢复回归（20 条，CPU-only）
tokenizer/ chat_template.jinja / vocab / merges     从 GGUF 导出
docs/      交接、循环诊断、精确线说明、DSH 接入、知识卡 0009-0012
```

## 7. 未验

- **256K 全上下文实跑**：只起了服务（`/props` 262144），没有真发 256K prompt；32K 已实测。
- **视觉的画质/多图**：只测过一张 768×768；多图、超大图、`min_tokens` 调参未测。CUDA 编码器没编（CPU 9–10 s/图）。
- **8 GB 显存档、KV in RAM**：未做。
- **自然长任务循环**：把 DSH 记录的 prompt 原样回放（greedy / 0.6）都不循环，**触发条件未定位**。

## 8. 出处

- 引擎：[PolyStrata](https://github.com/Niko1221/Strata)（Strata 的 `poly` 分支 fork）0.1.44.1，本仓只带补丁，不带整棵树。
- 模型：[InternScience/Sage-A1.5](https://huggingface.co/InternScience/Sage-A1.5)，本仓不带权重。
- 读数：本机实测，记录见 `docs/`；每条都标了证据等级与「怎么变红」。
