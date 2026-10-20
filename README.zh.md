# 大字幕（Loud Caption）

<p align="center">
  <img src="assets/icon/app_icon.png" width="96" alt="大字幕应用图标">
</p>

<p align="center">
  <strong>Android 上的实时、离线、大字字幕。</strong><br>
  给听得到声音、却听不清讲话的人。
</p>

<p align="center">
  <a href="https://github.com/DR1N0/loud-caption/actions/workflows/ci.yml"><img src="https://github.com/DR1N0/loud-caption/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="https://github.com/DR1N0/loud-caption/releases/latest"><img src="https://img.shields.io/github/v/release/DR1N0/loud-caption?display_name=tag&sort=semver" alt="最新版本"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT 许可证"></a>
</p>

大字幕把身边的说话声变成手机上的大字、高对比度文本。语音识别完全在设备本地
通过 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)（SenseVoice + Silero
VAD）完成，音频不会上传。可选的设备端模型
[Hy-MT2-1.8B](https://github.com/Tencent-Hunyuan/Hy-MT2) 可以在下方多显示一行
译文，同样不经过云端。

## 为什么做它

最初是为外公做的。他听力下降后，声音不是变小，而是变糊；助听器能放大音量，
却无法恢复清晰度。把对话实时变成大字，他就不用再靠猜。

这个场景决定了优先级：**低延迟、看得清、离线可用、少点几下**。其他东西都排在
后面。

## 功能

- **实时字幕**：中文、英文、日语、韩语、粤语，自动判断语种。
- **大字、高对比度**：16–80 px，自动滚动；上滑可以回看之前的字幕。
- **设备端翻译**：翻译模式使用统一目标语言；互译模式按来源语言分别设置目标。
- **横屏侧栏、昼夜主题、设置页**，切换字号/方向/设置时识别不中断。
- **模型只下载一次，之后离线可用。** 联网只用于下载经过固定校验的模型文件。

<!--
## 截图

待 docs/assets/ 加入以下文件后补上截图表格：
captions-portrait.png、translation-mode.png、translate-custom.png、
landscape-large-font.png、first-run-mobile-data.png。
-->

## 安装

大字幕通过侧载 APK 分发，不上架 Google Play。

### Obtainium（推荐）

安装 [Obtainium](https://github.com/ImranR98/Obtainium)，把本仓库地址添加为
来源，之后跟随 GitHub Release 更新：

```text
https://github.com/DR1N0/loud-caption
```

### APK

从[最新 Release](https://github.com/DR1N0/loud-caption/releases/latest) 下载
`app-release.apk` 并打开。首次安装需要允许浏览器或文件管理器“安装未知应用”。

- Android 8.0（API 26）及以上，arm64-v8a。
- APK 约 52 MB。首次启动会下载并校验约 240 MB 的识别/降噪模型；之后第一次
  进入翻译模式，会再下载约 1.08 GB 的翻译模型。
- 下载支持断点续传。未连接 Wi-Fi 时会提示将使用移动数据，确认后才继续。
- 模型安装完成后，识别和翻译都不需要网络。

## 实现概要

- **识别/降噪**：SenseVoice int8 + Silero VAD，通过 sherpa-onnx 在本地运行。
  VAD 切分麦克风音频；说话过程中做部分结果重解码，只有最终片段会成为已提交字幕。
- **翻译**：Hy-MT2-1.8B Q4_K_M 通过 llama.cpp 在 CPU 上运行。只翻译已提交的
  字幕行，避免翻译积压拖住实时字幕。
- **模型分发**：固定 URL 和 SHA-256、镜像回退、`.part` 断点续传、stall 检测、
  原子安装。精确大小与许可证见 [docs/model-sources.md](docs/model-sources.md)。

## 隐私

- 没有账号、统计、遥测，也没有云端识别/翻译。
- 音频、识别文字和译文都不会被保存或上传。
- 唯一的网络请求是模型下载；release manifest 中的 `INTERNET` 和
  `ACCESS_NETWORK_STATE` 只用于这个目的。
- 崩溃日志只保存在本机、有大小上限，可在设置中手动复制或清除，不会自动上传。

## 现状

已在两台 Android 手机（包括外公的手机）上做过正常对话测试。使用中没有观察到
明显发热或耗电问题，表现与其他持续运行的 App 相当；这不是正式 benchmark。
不同口音、设备和长时间使用下的准确率，仍需要更多真实反馈。翻译为可选功能，
目前仅支持 Android；iOS、云同步、字幕历史和账号系统不在范围内。

## 构建与测试

需要 Flutter 3.47.x、JDK 17 和 Android SDK（platform 36、build-tools
36.0.0、NDK 28.2.13676358）。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

提交 PR 前请先看 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 文档

- [架构](docs/architecture.md)
- [架构决策（ADR）](docs/adr/)
- [模型来源、大小、校验和与许可证](docs/model-sources.md)
- [测试与发布检查清单](docs/testing.md)
- [真机测试](docs/device-testing.md)
- [文档索引](docs/README.md)

带日期的实现计划不放进仓库：过期的计划比没有计划更糟。

## 许可证

本仓库代码使用 [MIT License](LICENSE)。

模型文件不在本仓库中，遵循各自许可证：SenseVoice 权重使用 FunASR Model Open
Source License Agreement v1.1，Silero VAD 为 MIT，Hy-MT2 为 Apache-2.0。详见
[docs/model-sources.md](docs/model-sources.md) 和
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

[English README](README.md)
