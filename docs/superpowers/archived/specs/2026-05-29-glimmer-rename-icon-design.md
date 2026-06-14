# Glimmer App 改名与图标设计

## 概述

将 app 显示名从 "voice_diary" 改为 "Glimmer"，并生成配套的启动图标。

## 图标设计规格

- **背景**: 蓝紫渐变，左上 #667eea → 右下 #764ba2，135° 方向
- **形状**: 圆角方形，适配 Android Adaptive Icon
- **核心元素**: 白色声波纹（正弦波形，圆头描边），居中放置
- **风格关键词**: 简洁、柔和、现代
- **适用平台**: 仅 Android

## App 改名范围

### 需要修改

| 文件 | 修改内容 |
|------|----------|
| `android/app/src/main/AndroidManifest.xml` | `android:label` 从 `"voice_diary"` 改为 `"Glimmer"` |
| `android/app/src/main/res/mipmap-*/ic_launcher.png` | 各分辨率替换为新图标 |

### 不修改

| 文件/字段 | 原因 |
|-----------|------|
| `applicationId` (com.personal.voice_diary) | 保持包名不变，避免影响已安装用户和签名 |
| `pubspec.yaml` name 字段 | Dart 包标识符，非用户可见的显示名 |

## 实现方式

使用 `flutter_launcher_icons` 插件从一张 SVG/PNG 源图自动生成各分辨率的 Android 图标。源图使用 Python 脚本生成，确保精确的颜色和渐变参数。

## 验证

- `flutter build apk --release` 构建成功
- 安装后 app 名称显示为 "Glimmer"
- 图标在各分辨率下清晰可辨
