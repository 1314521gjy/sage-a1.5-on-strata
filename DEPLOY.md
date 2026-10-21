# 部署：Sage-A1.5 Q4_K_M on PolyStrata（单卡 32 GB）

从零到能跑，一条闭环。所有路径都是本机的实际位置，换成你自己的即可。

## 0. 前置

- **显卡**：NVIDIA，本机 RTX 4080 SUPER **32 GB**（32,760 MiB）。20.2 GiB 权重 + 18.7 GiB 专家 + KV ≈ 28.5 GiB 常驻。
  **24 GB 卡装不下常驻服务**（可试更小上下文或 KV in RAM，本仓未验）。
- **CUDA 13.3**，`PATH` 里要有 `E:\cuda-13.3\bin\x64`（本机写法）：
  ```powershell
  $env:PATH = "E:\cuda-13.3\bin\x64;" + $env:PATH
  ```
- **Python 3.12**（serve 端），**VS 2022 Build Tools + CUDA toolkit**（编引擎），**CMake/Ninja**。

## 1. 引擎

```powershell
git clone <PolyStrata 0.1.44.1 的源>
cd PolyStrata
cmake -S . -B build-p3 -G Ninja -DCMAKE_BUILD_TYPE=Release   # 参数按上游 docs/BACKENDS.md
cmake --build build-p3 --target strata-poly
```

产物：`build-p3\strata-poly.exe`（本机 65,665,536 B）。

**可选：打本仓的思考循环补丁**（推荐，见 README §3）：

```powershell
git apply .\patches\0001-reasoning-loop-recovery-2029.patch
python -m unittest serve.test_reasoning_loop_recovery      # 期望 20/20 OK（CPU，不占显卡）
```

补丁只改 `serve/server.py`（Python），**不重编 exe**；打完重启 serve 即生效。

## 2. 权重

- 文件：`Sage-A1.5-Q4_K_M.gguf`，**21,713,463,520 B**（20.22 GiB）。
  sha256：`a64fe0bbf936db3eb54f66f142c2b2eee569ade83673649f549a21daef8ca395`（本机实测）。
- 来源：`InternScience/Sage-A1.5` 的 GGUF（Q4_K_M）。
- **先核对大小再启动**（`strata-poly` 读 GGUF 头，不校验 hash；坏文件会在加载时报几何错）。

> ⚠️ 别用 q36 变体：`strata-q36` 拒载 `blk.0.ssm_alpha.weight is Q4_K, expected F32, BF16, F16 or Q8_0`。

## 3. tokenizer

本仓 `tokenizer/` 即服务端要的那份（从 GGUF 导出）：

```
chat_template.jinja  vocab.json  merges.txt  tokenizer.json  token_type.json   （约 10 MB）
```

`serve` 配置里的 `"tokenizer"` 指向这个目录即可。

## 4. 冒烟（CLI，一次性）

```powershell
cd <repo>\PolyStrata
.\build-p3\strata-poly.exe --model <...>\Sage-A1.5-Q4_K_M.gguf `
  --tokens-file prompt.txt --max-context 16384 --max-new 256 `
  --window 4 --lookup 0
```

期望：`loaded in ~7 s; 10496 of 10496 routed experts in VRAM (18.7 GiB)`，然后按 193 tok/s 左右出 token。

`--window 4` 是 MTP 的**精确档**；`--window 8` 更快但第 70 个 token 起分岔，别用于对拍。

## 5. 常驻服务（OpenAI 兼容）

```powershell
$env:PATH = "E:\cuda-13.3\bin\x64;" + $env:PATH
python -m serve.server --engine strata `
  --config .\configs\sage-serve-exact-256k.json --port 8193
```

配置里关键四项：

```json
"args": ["--model", "<...>.gguf", "--max-context", "262144", "--window", "4", "--lookup", "0"],
"tokenizer": "<本仓>/tokenizer",
"reasoning_budget_tokens": 0,
"reasoning_loop_recovery": "recover"
```

健康检查（必须逐条对）：

```powershell
Invoke-RestMethod http://127.0.0.1:8193/health
# status=ok, max_context=262144, model=sage-a1.5-q4_k_m

python .\scripts\test_sage256k.py    # 注意：max_tokens 见脚本；思考无上限时给小了会只出思考
```

`/props` 的 `n_ctx` 必须等于 `--max-context`；不等就是读错了配置。

### 5.1 图片输入（可选）

要让模型看图，配置里加 `"vision"` 段（键名：`exe` `mmproj` `model` `threads` `max_tokens` `min_tokens` `gpu`）：

```json
"vision": {
  "exe": "...\\build-vision\\bin\\strata-vision.exe",
  "mmproj": "...\\Sage-A1.5-mmproj.gguf",
  "model": "...\\Sage-A1.5-Q4_K_M.gguf",
  "threads": 16, "max_tokens": 1024, "min_tokens": 1024
}
```

`strata-vision` 先编出来（源在 `tools/vision`）：

```powershell
cmake -S tools/vision -B build-vision -G Ninja -DCMAKE_BUILD_TYPE=Release `
      -DLLAMA_DIR=E:\llama-cpp-pin -DSTRATA_PORTABLE=OFF
cmake --build build-vision --target strata-vision
```

判据：重启后 `/health` 的 `images` = `true`，日志出现 `loading the vision encoder ...` 与 `images on`；
发一张已知内容的图，回答要对得上。CPU 编码约 9–10 s/图（1024 图像 token）；要快就 `-DSTRATA_VISION_CUDA=ON`，
代价约 1.4 GB 显存。

## 6. 踩坑清单（都真踩过）

| # | 坑 | 判据 / 修法 |
|---|---|---|
| 1 | **q36 变体拒载** | 报 `ssm_alpha.weight is Q4_K` ⇒ 换 Q4_K_M GGUF，别改类型表 |
| 2 | **MTP window8 分岔** | 第 70 token 起 different ⇒ 只认 `--window 4` |
| 3 | **`--prompt-batch` 有损** | 8K 任务 `first_diff=15/49/56` ⇒ 只走默认 prefill |
| 4 | **循环恢复静默空转** | 日志没有 `repeated reasoning` 但确实在重复 ⇒ 打本仓补丁 |
| 5 | **思考无上限 + max_tokens 小** | `content` 空、`finish=length` ⇒ max_tokens ≥ 3000，或给 `reasoning_budget_tokens` |
| 6 | **并发不是并行** | `strata-poly` 无 `--batch`/`slot`，2/3/4 并发 = FIFO（N×0.50 s） |
| 7 | **脚本中文路径乱码** | PS 5.1 读无 BOM UTF-8 会按 GBK ⇒ 脚本存 UTF-8 **带 BOM** |
| 8 | **原生 stderr 触发假失败** | `$ErrorActionPreference=Stop` + 引擎 stderr ⇒ 改 `Continue` 再判 `$LASTEXITCODE` |

## 7. 回滚

- 引擎二进制：构建目录里留 `strata-poly.exe.bak-*`。
- 服务端：打了补丁就 `git checkout serve/server.py` 后重启。
- 服务进程：`Stop-Process -Id <python 的 pid> -Force` 之后 `Get-Process strata* | Stop-Process -Force`；
  **杀父进程前先确认 `strata-poly` 是它的子进程**（本机是 python 包装器 + strata-poly 子进程两件套）。
