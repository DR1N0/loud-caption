# 大字幕(Loud Caption)

[English](README.md)

大字幕(英文名 Loud Caption)是一款 Android 应用,为身边的对话实时显示大字、高对比度字幕,使用设备本地的 sherpa-onnx(SenseVoice)语音识别——音频不会上传,识别过程完全离线完成。它是为听力不便、希望跟着看字幕的人设计的。首次启动需要联网下载一次约 240MB 的识别模型(见下方"安装到设备"一节),之后使用无需联网。目前支持中文和英文识别,**仅支持 Android**。系统语言为中文时,桌面图标和应用名会显示为"大字幕"。

这是一个个人项目,通过 [GitHub Releases](https://github.com/DR1N0/loud-caption/releases) 侧载分发,不在 Google Play 上架。

## 功能

- 全屏、高对比度实时字幕,可调整字号(16–80px),新字幕会自动滚动到可见范围内,上滑回看历史字幕时会暂停自动滚动
- 离线中文/英文/日语/韩语/粤语语音识别,自动判断语种,无需手动切换
- 设备本地翻译(通过 llama.cpp 运行 Hy-MT2-1.8B,绝不经过云端),可配置单一目标语言,也可按源语言分别路由——粤语在翻译时会和普通话归为同一语言,因为两者转写出来的文字相同
- 横竖屏锁定;控制栏会自适应排布——竖屏一排、横屏变成侧边栏,尽量把屏幕让给字幕
- 不保存音频或字幕历史,仅保留你的显示和翻译相关偏好设置(字号、横竖屏、昼夜主题、翻译模式/目标语言)
- 旋屏、调整字号、使用应用内设置页时识别不会中断;只有真正退到后台、锁屏,或进入系统设置时才会停止

打包了哪些内容及各自的许可证,见 [`docs/model-sources.md`](docs/model-sources.md) 和 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md);完整的设计过程见 [`docs/superpowers/specs/`](docs/superpowers/specs/)。

## 开发者指南

### 环境要求

- Flutter SDK(已用 3.41.7 验证)
- 带 Android SDK 的 Android Studio(需要 `adb`、`aapt`、`apksigner`,以及一个模拟器或真机),外加 NDK 和 CMake 组件——翻译插件在构建时会从源码编译 llama.cpp
- Python 3
- 一个你所在网络 TLS 信任的 JDK 17(`Makefile` 默认指向本机的 Zulu 17;如果路径不同,用 `JAVA17_HOME` 覆盖)
- `make`
- 运行 Android 8.0(API 26)及以上版本的设备或模拟器——因翻译插件的最低要求从 API 24 提高到了 API 26

### 常用命令

```bash
make test          # flutter test(单元 + widget 测试）
make analyze       # flutter analyze
make apk-debug     # 构建 build/app/outputs/apk/debug/app-debug.apk
make apk-release   # 构建 build/app/outputs/apk/release/app-release.apk
make apk           # apk-release 的别名
make check         # pub-get + analyze + test（完整检查）
make clean         # flutter clean
```

提交 PR 或准备发布前先跑一遍 `make check`。

### 安装到设备

```bash
make install-debug     # 构建 + adb install -r 安装 debug 包
make install-release   # 构建 + adb install -r 安装 release 包
```

首次启动时,应用会先下载并校验约 240 MB 的语音识别模型(SenseVoice + Silero VAD),下载完成前无法使用——请确保有足够的时间、存储空间和网络连接。下载完成后,点击 **开始** 并同意 Android 弹出的麦克风权限请求;此后使用应用不再需要联网。之后如果切换到翻译模式,会触发另一次独立的按需下载(约 1.08 GB,Hy-MT2——见 [`docs/model-sources.md`](docs/model-sources.md));不需要翻译功能可以跳过。

### 签名说明

debug 包和 release 包都用 `android/app/release-keystore.jks` 签名——这是为本项目专门生成、**刻意提交进仓库**的密钥,不是秘密,也不是 Gradle 默认的、每台机器各自生成的 Debug 签名。debug 包刻意使用这个相同的身份(而不是默认的 debug key),这样 debug 包和 release 包之间互相安装升级时不需要先卸载。本项目只通过 GitHub Release 分发,从不上架 Play(Play 本身也会拒绝 Debug 签名的上传),所以"每台构建机器、每种构建类型签名都一致"比"一把可能丢失的私钥"更重要。

这样做的代价是:因为密钥是公开的,任何拿到这个仓库的人都能做出一个 Android 会认可为"合法更新"的 APK。对一个非商业化的个人项目,这是可以接受的风险——但如果你的项目有真实的对手方、或考虑上架 Play,**不要**照搬这个做法,应该自己生成密钥、不纳入版本控制,并私下妥善备份。

### 隐私

- release 包的 manifest 申请了 `RECORD_AUDIO` 和 `INTERNET`,没有存储、悬浮窗或前台服务权限。`INTERNET` 权限仅用于首次启动时下载经过校验的指定模型文件(见 [`docs/model-sources.md`](docs/model-sources.md)),应用不会发起其他任何网络请求。
- 没有发现任何由本应用代码发起的语音上传路径;识别完全基于下载到本地的 sherpa-onnx(SenseVoice)和 Silero VAD 模型在设备本地完成,音频和识别出的文字都不会被发送到任何地方。这一点未经网络抓包独立验证。

### 现状

本项目已将语音识别引擎从 Vosk 迁移到 sherpa-onnx(SenseVoice 语音识别 + Silero VAD)。SenseVoice 的自动语种识别("auto"模式)实测已经足够准确——没有出现中文被误判为英文的情况——因此手动切换语言的界面被移除。ASR 模型改为首次启动时下载,不再打包进 APK;ASR 和翻译模型的下载如果中途中断,都支持断点续传,并且在主源之外还提供了对中国大陆网络更友好的镜像(GitHub 代理、ModelScope、hf-mirror.com)作为备用。

设备本地翻译(通过 llama.cpp 运行 Hy-MT2-1.8B,绝不经过云端)已接入实时字幕流程,并已在真机上完整验证——翻译模式和自定义翻译模式下都实测翻译了几十句。目前只有已提交(最终)的字幕行才会触发翻译;此前曾对尚未提交的部分识别结果做投机性翻译以追求伪流式效果,但真机测试发现设备端推理的延迟跟不上正常语速,因此这个机制已被移除。

真机测试还发现了本项目用于翻译推理的第三方库 `llama_flutter_android` 的两个 bug:一个是 llama.cpp 自身 RMSNorm 计算核里的原生崩溃(移除上述投机翻译机制后,顺带消除了触发它的"取消后立即重新生成"竞态,目前未再复现);另一个是流式输出时错误处理跨 token 边界的多字节 UTF-8 字符,导致中日韩文字出现乱码。两个问题均已修复并验证,第二个已提交 PR 到上游仓库([dragneel2074/Llama-Flutter#2](https://github.com/dragneel2074/Llama-Flutter/pull/2)),在其合并之前本项目依赖一个带有该修复的 fork(见 `pubspec.yaml`)。

前台恢复行为、同时运行语音识别和翻译对电量/发热的影响,以及不同设备、不同口音下的识别/翻译准确率,除了本项目实测过的这一台设备外均未独立验证。可下载语言包、云同步、字幕历史和 iOS 支持仍不在当前范围内。
