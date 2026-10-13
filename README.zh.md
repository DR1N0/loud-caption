# Loud Caption

[English](README.md)

Loud Caption 是一款 Android 应用,为身边的对话实时显示大字、高对比度字幕——完全离线,使用设备本地的 Vosk 语音识别。它是为听力不便、希望跟着看字幕的人设计的,音频不会离开设备。目前内置中文和英文模型,**仅支持 Android**。

这是一个个人项目,通过 [GitHub Releases](https://github.com/DR1N0/loud-caption/releases) 侧载分发,不在 Google Play 上架。

## 功能

- 全屏、高对比度实时字幕,可调整字号
- 离线中英文语音识别,一键切换
- 横竖屏锁定,设置页可启用/禁用已安装的语言
- 不保存音频或字幕历史,仅保留你的偏好设置(语言、字号、横竖屏)
- 旋屏、调整字号、使用应用内设置页时识别不会中断;只有真正退到后台、锁屏,或进入系统设置时才会停止

打包了哪些内容及各自的许可证,见 [`docs/model-sources.md`](docs/model-sources.md) 和 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md);完整的设计过程见 [`docs/superpowers/specs/`](docs/superpowers/specs/)。

## 开发者指南

### 环境要求

- Flutter SDK(已用 3.41.7 验证)
- 带 Android SDK 的 Android Studio(需要 `adb`、`aapt`、`apksigner`,以及一个模拟器或真机)
- Python 3
- 一个你所在网络 TLS 信任的 JDK 17(`Makefile` 默认指向本机的 Zulu 17;如果路径不同,用 `JAVA17_HOME` 覆盖)
- `make`

### 常用命令

```bash
make models       # 下载并校验两个内置 Vosk 模型
make test          # flutter test(单元 + widget 测试）
make analyze       # flutter analyze
make jvm-test      # Android/Kotlin JUnit 测试
make apk-debug     # 构建 build/app/outputs/apk/debug/app-debug.apk
make apk-release   # 构建 build/app/outputs/apk/release/app-release.apk
make apk           # apk-release 的别名
make check         # models + pub-get + analyze + test + jvm-test（完整检查）
make clean         # flutter clean
```

`make models` 一般只需执行一次(或模型升级版本时再跑一次)——ZIP 文件会做校验且已被 Git 忽略。提交 PR 或准备发布前先跑一遍 `make check`。

### 安装到设备

```bash
make install-debug     # 构建 + adb install -r 安装 debug 包
make install-release   # 构建 + adb install -r 安装 release 包
```

首次启动时,点击 **开始** 并同意 Android 弹出的麦克风权限请求。首次使用会把约 82 MB 的内置模型解压到约 133 MB 的应用私有存储,请在授予麦克风权限前确保时间和存储空间足够。

### 签名说明

release 包用 `android/app/release-keystore.jks` 签名——这是为本项目专门生成、**刻意提交进仓库**的密钥,不是秘密,也不是 Android 的 Debug 签名。本项目只通过 GitHub Release 分发,从不上架 Play(Play 本身也会拒绝 Debug 签名的上传),所以"每台构建机器签名一致"比"一把可能丢失的私钥"更重要。

这样做的代价是:因为密钥是公开的,任何拿到这个仓库的人都能做出一个 Android 会认可为"合法更新"的 APK。对一个非商业化的个人项目,这是可以接受的风险——但如果你的项目有真实的对手方、或考虑上架 Play,**不要**照搬这个做法,应该自己生成密钥、不纳入版本控制,并私下妥善备份。

### 隐私

- release 包的 manifest 只申请 `RECORD_AUDIO`,没有 `INTERNET`、存储、悬浮窗或前台服务权限。debug 包额外带有 Flutter 开发工具自身需要的 `INTERNET` 权限。
- 没有发现任何由本应用代码发起的语音上传路径;识别完全基于内置的 Vosk 模型在设备本地完成。这一点未经网络抓包独立验证。

### 现状

有一台手机运行过本项目的 release 包,实测中英文实时字幕稳定、旋屏和应用内设置期间不中断识别、切换语言时模型替换顺利、退到后台时能干净停止——这些由开发者确认,部分有设备日志佐证。前台恢复行为、字幕准确率,以及不同设备的电量/发热/无障碍表现尚未独立验证。在线翻译、可下载语言包、云同步、字幕历史和 iOS 支持均不在当前范围内。
