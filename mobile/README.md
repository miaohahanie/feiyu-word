# 手机端（Android · M2）

本目录是「单词桌宠」手机端（Android）的 Flutter 源码与工程。

当前状态：**M2 已实现并在本机构建通过（debug APK）**。

## 目录内容

- [需求文档.md](需求文档.md)（v0.2）
- [技术设计文档.md](技术设计文档.md)（v0.1）
- `android/` — Flutter 生成的 Android 工程（已在仓库内，无需再 `flutter create`）
- `lib/` — Dart 源码（模型 / SQLite / 同步 / 复习 / 页面）
- `pubspec.yaml` / `pubspec.lock`
- `test/` — 测试
- `.gitignore`

## 本机环境（已配置）

- Flutter SDK：`C:\Users\miaoha\flutter`（3.47.2+，含 Dart 3.13）
- Android SDK：`C:\Users\miaoha\Android\Sdk`（platform 36 / build-tools 36 / platform-tools）
- 本项目路径：`C:\Users\miaoha\Desktop\_Projects\单词桌宠`

本机常用命令（需要先打开 Git Bash 并 source 环境脚本，或直接使用完整 `flutter` 路径）：

```bash
source scripts/flutter-env.sh   # 若脚本不在仓库中，请按下面路径补全
cd mobile
flutter pub get
flutter build apk --debug
```

## 由于路径含中文做的适配

1. 本项目路径含「单词桌宠」，Windows 下 Android Gradle 默认拒绝构建。
   已在 `android/gradle.properties` 加入：

   ```properties
   android.overridePathCheck=true
   ```

2. `flutter analyze` 在本机中文路径下触发 Dart 分析器 LSP 崩溃，
   可改用：

   ```bash
   dart analyze
   ```

   实测 `dart analyze` 在中文路径下可以正常通过（当前 0 issues）。

3. Gradle 发行包下载（`services.gradle.org`）在本机超时，
   已把 `android/gradle/wrapper/gradle-wrapper.properties` 指向腾讯镜像：

   ```properties
   distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip
   ```

## 构建产物

调试 APK（本机构建通过）：

```text
mobile/build/app/outputs/flutter-apk/app-debug.apk   （约 162MB）
```

正式/安装版后续再出；release APK 需要配置签名（默认会用 debug 签名，仅用于测试）。

## Android 权限

`mobile/android/app/src/main/AndroidManifest.xml` 已包含：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CAMERA" />
```

后续 M5 提醒会追加：`POST_NOTIFICATIONS`、`SCHEDULE_EXACT_ALARM`、`USE_EXACT_ALARM`、`WAKE_LOCK`。

## 首次使用（M2 功能）

1. 电脑端打开「设置 → 手机同步」，勾选「开启局域网同步服务」；
2. 手机安装 `app-debug.apk`，打开 App →「设置 → 扫码配对」扫电脑二维码（或手动输入 IP + 端口 + 配对码）；
3. 回到首页选择词本，点「同步」拉取词库到本地 SQLite；
4. 同步后断网也能浏览词库；复习页已可用（评分事件暂存，M4 做完整回传）。
