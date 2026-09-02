# 手机端（Android · M2 开发中）

本目录用于存放手机端（Android / 后续可能 iOS）相关的需求、设计与代码。

当前状态：**M1 已完成；M2（Flutter 骨架 + 配对 + 首次全量同步 + SQLite）代码已就绪**。

## 目录内容

- [需求文档.md](需求文档.md)（v0.2）
- [技术设计文档.md](技术设计文档.md)（v0.1）
- `pubspec.yaml` — Flutter 依赖
- `lib/` — Dart 源码（模型 / SQLite / 同步 / 复习 / 页面）
- `.gitignore` — Flutter 构建产物忽略规则

## 本机如何生成 Android 工程并运行

需要先安装：

1. [Flutter SDK](https://flutter.dev/)（建议 3.x）
2. Android Studio / Android SDK（API 26+）

然后在本目录执行：

```bash
flutter create --platforms=android --org com.wordpet --project-name word_pet_mobile .
flutter pub get
```

如果 `flutter create` 提示文件已存在，可选择在一个空目录生成后再把 `lib/` 与 `pubspec.yaml` 覆盖过去，保留本目录内容。

接着：

```bash
flutter run          # 连接 Android 手机/模拟器运行
flutter build apk --release   # 生成 release APK
```

首次运行后（M2 功能）：
1. 电脑端打开「设置 → 手机同步」，勾选「开启局域网同步服务」；
2. 手机端 App「设置 → 扫码配对」扫电脑二维码（或手动输入 IP + 端口 + 配对码）；
3. 回到首页选择词本，点「同步」拉取词库；
4. 同步后断网也可浏览词库（离线复习、提醒在 M3/M5 继续完善）。

## Android 权限（生成工程后需确认）

`AndroidManifest.xml` 需要以下权限（M2 至少需要 INTERNET / CAMERA）：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CAMERA" />
```

后续 M5 提醒会追加：`POST_NOTIFICATIONS`、`SCHEDULE_EXACT_ALARM`、`USE_EXACT_ALARM`、`WAKE_LOCK`。
