# 本地 MLX 模型

macOS 桌宠内置 MLX Swift 多模态推理。新安装默认使用「本地 MLX」；已有
BYOK 配置保留，可在设置 → 模型切换。iOS 暂不接入这套桌面实现。

## 使用

在设置 → 模型 → 本地 MLX 选择并下载：

- `mlx-community/Qwen3.5-4B-4bit`：默认，下载约 3.1 GB。
- `mlx-community/Qwen3.5-2B-4bit`：低内存备选，下载约 1.8 GB。

下载按钮是唯一的模型联网入口。默认先从 Hugging Face 下载；连接超时、下载中断或
校验失败时自动尝试魔搭 ModelScope，不需要用户选择。元数据请求超时 15 秒，文件
下载连续 30 秒无数据时失败（不是整个文件只能下载 30 秒）。两个源都失败才显示错误。
用户暂停不会触发换源，再次点击下载会从已完成的分块继续，并显示已下载字节数。
每次尝试使用该源解析出的文件 revision，校验文件大小及权重 SHA-256；魔搭还提供
配置文件 SHA-256，一并校验。分块缓存放在 `AppPaths.dataRoot/downloads/`，按哈希
或来源与 revision 隔离，两个源只有内容哈希一致的权重才可复用。服务器不支持 Range
时允许完整下载，再校验安装。安装成功后清理分块缓存，暂停和失败时保留以便续传。
下载完成后原子安装，未完成的安装不会被加载。完成后可断网推理，不需要 API Key，不启动 Python/Ollama/CLI，也不会自动回退云端。
App 的更新检查是独立功能，不属于模型推理。

模型存放在 `AppPaths.dataRoot/models/`：正式版默认 `~/.dozycat/models/`，
Debug 默认 `~/.dozycat-debug/models/`。可用 `DOZYCAT_HOME` 隔离测试数据。

观屏复用前台窗口捕获权限和 secure-input 门控：当前帧只进入本地 VLM，
在内存中编码，图片不落盘。现有 OCR 仍用于保留小字和事实出处。当前图片
与历史 OCR 分别标注，不能把当前画面误认为历史原料。`PiAgent.run(imageData:)`
也支持显式传入一张图片，并在后续工具回合保留它。

## 资源策略

- 单个共享模型实例，加载、切换和生成经过串行队列；取消后等待 GPU 任务结束。
- 输入最多 3072 tokens，输出最多 1024 tokens，共 4096 tokens。
- 超长历史按完整回合移除；工具调用和结果成对保留，必要时截短工具结果。
  单条输入或工具定义仍超限时返回明确错误。
- 每次一张图片，最长边缩至 768，处理器像素预算 524288。
- Prefill 分块 128 tokens，MLX 空闲缓存 128 MiB，每次完成清缓存。
- 闲置 90 秒卸载模型，切换云端也卸载。
- 生成前及生成期间检查进程 physical footprint，接近预算时停止。

**6 GB 是验收目标，不是操作系统硬配额。** Metal 视觉编码和 prefill 内部瞬时分配
可能发生在采样之间；MLX 权重文件大小也不能代表总内存。必须在目标设备使用
真实输入测试，包括连续多轮和大截图。失败时应缩小输入或主动改选 2B。

工具定义沿用 `AgentTool`；本地模型使用 Qwen3.5 专用解析器。仅允许已注册的
工具，拒绝格式错误、缺失必填参数、未知参数和类型不符的调用；最多 6 轮、每轮 4 个调用。

## 验证

`LocalModelSmoke.swift` 提供仅 Debug 编译的集成测试入口，跳过正常启动流程、
更新器与观屏，用合成红圆图片和内存中的假工具验证中文聊天、看图、调用参数、
工具结果回传、连续运行和超长输入拒绝。测试不会修改用户小传。

先构建 Debug，下载模型，再执行：

```sh
DOZYCAT_HOME="$HOME/.dozycat-debug" scripts/test-local-model.sh /path/to/dozycat-debug.app /tmp/dozycat-mlx-report.json
```

报告包含每项结果、回答、总用时、50ms 采样的进程 physical footprint 峰值。
设置 `DOZYCAT_MLX_MODEL=mlx-community/Qwen3.5-2B-4bit` 可测 2B。
这组小样本是功能检查，不代表完整中文/视觉/tool-call 质量评测。

## 本次实测（2026-09-07）

Apple M5 / 16GB，macOS 26.6，Debug 构建，Qwen3.5-4B-4bit。
使用 `sandbox-exec` 的 `(deny network*)` 禁止测试进程联网。
中文聊天、两个并发请求、连续三次图片→工具→结果回传、超长上下文拒绝均通过。
整组测试用时 22.66 秒，进程 physical footprint 采样峰值 **4.153 GB**（十进制）。
图片为合成红圆；这不等于真实复杂截图质量评测，也不保证任意输入均低于 6GB。
2B 备选尚未真机测试。完整报告位于构建产物目录 `build.noindex/MLXLocal/offline-report.json`。

下载源逻辑测试（无需模型权重）：

```sh
swiftc -parse-as-library Sources/LocalModelDownloadSource.swift scripts/tests/LocalModelDownloadTests.swift -o /tmp/dozycat-download-tests
/tmp/dozycat-download-tests --live
```

覆盖默认 Hugging Face、失败切魔搭、取消不切源、双源失败、损坏文件拒绝；
`--live` 还验证两个源的 4B/2B 公开配置下载，以及跨源权重 SHA-256 一致性。

断点续传测试：`python3 scripts/tests/test_model_transfer.py`。使用本机 HTTP 服务
主动中断传输，验证续传起点、缓存复用、服务器忽略 Range 的处理以及损坏数据拒绝。

## 0.1.6 发布验收（2026-09-08）

Release 0.1.6 / build 7 已完成 Developer ID 签名、Apple 公证、stapler 和 Gatekeeper
校验。使用 Sparkle 2.9.6 对隔离的已发布 0.1.4 副本执行真实更新，成功安装到 0.1.6，
并验证新版本符合旧 App 的 designated requirement。无需改动用户现有安装或权限。
两个源的真实权重 Range 请求均已验证，与本机已测权重的文件开头一致。
下载器单元测试、HTTP 中断续传测试、5 项 appcast 检查均通过。
