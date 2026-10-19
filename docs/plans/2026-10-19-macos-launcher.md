# PersonalAI Implementation Plan

**Goal:** 实现参考 Alfred 的原生 macOS 剪贴板、AI 启动器与脚本流程工具。

**Architecture:** SwiftUI 展示，AppKit 管理菜单栏与浮动面板，Carbon 注册全局快捷键。剪贴板和设置存储在本地 Application Support；API 密钥进入 Keychain。异步任务统一管理取消、超时与输出上限。

**Tech Stack:** Swift 5.9+、macOS 14+、Swift Package Manager；无第三方依赖。

## 设计选择

- 采用原生 SwiftUI + AppKit，便于系统集成；Electron/Tauri 需要额外运行时或工具链，暂不采用。
- 全局入口分为动作、剪贴板、流程；上下键选择，回车执行，Esc 关闭，⌘1/2/3 切换。
- 记录文本、图片和文件引用，支持去重、置顶、删除、搜索、暂停、应用排除、保留期限与数量上限；跳过标记为密码/临时的剪贴板。
- AI 动作包括本机 Codex CLI 与豆包应用/网页转交；可选火山方舟 API。搜索 URL 使用编码后的 `{query}`。
- 自定义流程由多个顺序脚本步骤组成，上一步 stdout 作为下一步 stdin；输入同时通过 `PERSONALAI_INPUT` 传递，绝不把输入拼入脚本源码。支持独立快捷键、工作目录、超时、输出复制。
- 快捷键提供录制与冲突提示；登录启动、剪贴板设置、搜索、AI 和流程均可从设置编辑。

## 实施步骤

1. 创建 SwiftPM 工程、菜单栏应用和本地 `.app` 构建脚本。
2. 实现 Codable 模型、本地原子存储、Keychain、剪贴板采集与恢复。
3. 实现全局快捷键录制与注册、浮动面板、焦点恢复和键盘操作。
4. 实现异步脚本执行、超时/取消、搜索、豆包转交/API 和 Codex CLI。
5. 实现设置表单、流程增删编辑及多步骤编排，保存时校验。
6. 编译并进行实际应用冒烟验证；不编写单测，不进行 Java 编译。
7. 完成 README 与验证记录，提交中文 message，推送功能分支；不发布。

## 仓库初始化

远程仓库当前无任何分支，故先创建空 master 基线，再创建 `feature/261019-fj-macos-launcher`。
