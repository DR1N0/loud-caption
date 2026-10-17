# 大字幕(Loud Caption)

[English](README.md)

大字幕(英文名 Loud Caption)是一款 Android 应用,为身边的对话实时显示大字、高对比度字幕,使用设备本地的 sherpa-onnx(SenseVoice)语音识别——音频不会上传,识别过程完全离线完成。它是为听力不便、希望跟着看字幕的人设计的。首次启动需要联网下载一次约 240MB 的识别模型(见下方"安装到设备"一节),之后使用无需联网。目前支持中文和英文识别,**仅支持 Android**。系统语言为中文时,桌面图标和应用名会显示为"大字幕"。

这是一个个人项目,通过 [GitHub Releases](https://github.com/DR1N0/loud-caption/releases) 侧载分发,不在 Google Play 上架。

## 功能

- 全屏、高对比度实时字幕,可调整字号
- 离线中英文语音识别,自动判断语种,无需手动切换
- 横竖屏锁定;控制栏会自适应排布——竖屏一排、横屏变成侧边栏,尽量把屏幕让给字幕
- 不保存音频或字幕历史,仅保留你的字号和横竖屏偏好设置
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

本项目已将语音识别引擎从 Vosk 迁移到 sherpa-onnx(SenseVoice 语音识别 + Silero VAD)。后续测试发现 SenseVoice 的自动语种识别("auto"模式)本身已经足够准确——没有出现中文被误判为英文的情况——因此手动切换语言的界面(设置页的语言列表、字幕页的语言切换按钮)被移除。ASR 模型现在改为首次启动时下载,不再打包进 APK;设置页后来也因配置翻译功能而重新加入。有一台手机运行过 sherpa-onnx 引擎的 auto 模式,实测中英文实时字幕稳定、准确,但针对当前版本的真机冒烟测试仍待执行。前台恢复行为、不同设备下的字幕准确率,以及设备相关的电量/发热/无障碍表现尚未独立验证。

设备本地翻译(通过 llama.cpp 运行 Hy-MT2-1.8B,绝不经过云端)正在积极开发中:模式切换按钮、设置页和翻译引擎本身都已经完成且能正常构建,但翻译引擎尚未接入实时字幕流程——切换到翻译模式目前还不会真正翻译任何内容。可下载语言包、云同步、字幕历史和 iOS 支持仍不在当前范围内。
