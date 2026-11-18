# VaultNote

[English](#english) · [简体中文](#简体中文)

## English

VaultNote is a native macOS notes app. Note files are encrypted locally with AES-GCM using a key derived from the master password. Gallery items and manual exports are stored separately under their own file permissions.

When you submit a link in the download feature, the app uses a third-party service to resolve it. Note encryption runs independently of media downloads.

### Build and run

1. On macOS 14 or later, open `VaultNote.xcodeproj` in Xcode.
2. Select the **VaultNote** scheme and choose **Product → Build**.
3. Click the **Run** button in Xcode to launch the app.

The app uses the current macOS user’s local vault. If you already have VaultNote data, back it up before running a new build.

## 简体中文

VaultNote 是一款原生 macOS 笔记应用。笔记文件在本地通过 AES-GCM 加密，密钥由主密码派生。图库和手动导出的文件独立存储，适用各自的文件权限。

在下载功能中提交链接时，应用会使用第三方服务解析链接。笔记加密与媒体下载独立运行。

### 构建和运行

1. 在 macOS 14 或更新版本上，用 Xcode 打开 `VaultNote.xcodeproj`。
2. 选择 **VaultNote** 方案，再选 **Product → Build**。
3. 点 Xcode 左上角的 **运行** 按钮启动应用。

应用使用当前 macOS 用户的本地笔记库。如果已经有 VaultNote 数据，请先备份，再运行新构建。
