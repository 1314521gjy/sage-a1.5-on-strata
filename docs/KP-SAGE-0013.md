---
id: KP-SAGE-0013
title: Sage-A1.5 视觉打通（strata-vision 现编 · CPU 编码 · DSH 收图）
one_line: tools/vision 对 llama-cpp-pin 现编 strata-vision.exe（4.66 MB），配置加 "vision" 段后 /health images:true，768×768 图识别正确；CPU 单图编码约 9–10 s。
kind: 实测
status: 现行
review: 待复核
entity: PRJ-SAGE
gen_born: G1
gen_valid: [G1]
confidence: 实测
evidence: "/health images:true；1050 prompt tokens（1024 图像）；12.1 s 墙钟；答'红色圆形+白色长方形'；strata-vision READY 2048"
source: "E:/视频/_flashnext/experiments/20261015-nemotron-on-strata/PolyStrata/tools/vision/CMakeLists.txt"
source_lines: 1-61
source_anchor: strata-vision 构建与接入（2026-10-21）
ttl_days: 365
verified_at: 2026-10-21
supersedes: []
aliases: [Sage 视觉, strata-vision, mmproj, 图片输入, DSH 图片]
symptoms: [Sage 看不见图, DSH 发图没反应, images false, 视觉怎么接]
---

## 结论

- **编码器是现编的**，之前本机根本没有 `strata-vision.exe`（全盘搜索 0 命中，交接里"版本不同步"实为"从未构建"）。
  源码在 `tools/vision/strata_vision.cpp`，用 `tools/vision/CMakeLists.txt` 对 **`E:\llama-cpp-pin`**（ggml 0.24.0 / commit `3cf0325`）编译：
  ```
  cmake -S tools/vision -B build-vision -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLAMA_DIR=E:\llama-cpp-pin -DSTRATA_PORTABLE=OFF
  cmake --build build-vision --target strata-vision
  ```
  产物：`build-vision\bin\strata-vision.exe`，**4,664,320 B**，131 个目标、CPU 构建。
- **mmproj 本来就在**：`E:\models\Sage-A1.5\gguf-q4\Sage-A1.5-mmproj.gguf`（899,282,880 B，`clip.*` 视觉塔）。
- **接入方式 = serve 配置加 `"vision"` 段**（poly 不需要 `--vision` 参数，它按请求里的图片读）：
  ```json
  "vision": {"exe": "...\\build-vision\\bin\\strata-vision.exe",
             "mmproj": "...\\Sage-A1.5-mmproj.gguf", "model": "...\\Sage-A1.5-Q4_K_M.gguf",
             "threads": 16, "max_tokens": 1024, "min_tokens": 1024}
  ```
  重启后 `/health` 从 `images:false` 变 **`images:true`**，
  日志出现 `loading the vision encoder ...` 与 `ready: ... images on`。
- **DSH 侧**：`cordis.patch.yml` 与 `local-sage.patch.yml` 的 sage-local 模型 `input` 从 `[text]` 改成 **`[text, image]`**，
  DSH 重启后才会把图片当输入发过来。

## 判据 / 负控

- 正向：`/health` 的 `images` 为 `true`；发一张已知内容的图，回答与图一致（本次：768×768 红圆 + 白色长方形，答对）。
- 负控：注释掉 `"vision"` 段重启 ⇒ `images:false`，同一条请求返回 400/“this engine was started without --vision”。
- 负控：纯文本请求不受影响（同一服务 `1+1` 正常）。
- 计数：`prompt_tokens = 1050`，其中图像 **1024**（`max_tokens`/`min_tokens` 都设 1024 的结果）。

## 读数（A 级，2026-10-21 21:2x，8193）

| 项 | 值 |
|---|---|
| 编码器加载 | **0.9 s**（`strata-vision: model files loaded in 0.9 s`），READY 2048 |
| 编码器位置 | CPU，16 线程 |
| 单图墙钟 | **12.1 s**（其中编码 ≈9–10 s，思考 2 s / 435 token） |
| 图像 token | 1024（768×768 图） |
| 回答 | `这是一个红色的圆形，中间有一个白色的长方形。`（正确） |

## 边界（未做）

- **CUDA 编码器没编**：`-DSTRATA_VISION_CUDA=ON` 可把编码压到 0.1–0.5 s，但要 ~1.4 GB 显存；
  服务当前占 28.8 / 32.7 GiB，只剩 ~3.9 GiB，没上。
- 多图、超大图、`min_tokens` 调参未测。
- DSH 端实际看图未验（需用户重启 DSH 后自己发一张）。
