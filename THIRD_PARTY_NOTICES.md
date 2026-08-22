# 第三方组件声明

键鼠映射工具使用或依赖以下第三方项目。各组件继续适用其原始许可证，本项目的 GPL-2.0-only 许可不会替代这些声明。

## AutoHotkey v2

- 项目：https://github.com/AutoHotkey/AutoHotkey
- 许可证：GNU General Public License v2.0
- 用途：脚本运行时以及编译后 EXE 的自包含运行基础。

AutoHotkey 的许可证文本及其包含的 PCRE/BSD 声明可在上游仓库中查看：https://github.com/AutoHotkey/AutoHotkey/blob/alpha/license.txt

## Ahk2Exe

- 项目：https://github.com/AutoHotkey/Ahk2Exe
- 许可证：WTFPL
- 用途：将 AutoHotkey v2 源码编译为 Windows EXE。

Ahk2Exe 仅在构建过程中使用，不作为本仓库源码的一部分进行修改。

## WebViewToo

- 文件：`Lib/WebViewToo.ahk`
- 项目：https://github.com/The-CoDingman/WebViewToo
- 许可证：MIT License
- 版权：Copyright (c) 2025 Ryan Dingman（Panaku / The-CoDingman）

完整 MIT 许可证声明保留在 `Lib/WebViewToo.ahk` 文件顶部。

## Microsoft Edge WebView2

- 项目：https://developer.microsoft.com/microsoft-edge/webview2/
- 用途：承载 HTML、CSS 和 JavaScript 用户界面。

WebView2 Runtime 由 Microsoft 提供并适用 Microsoft 的相关许可条款。运行本项目通常需要系统已经安装 WebView2 Runtime。

## 项目资源

`docs/images` 中的软件界面截图及其他未单独声明来源的公开资源，随本项目按 GPL-2.0-only 发布。

本仓库不提供构建时使用的 `img/img.ico` 和 `img/img.svg`。使用者自行放入的图标文件不属于本项目分发内容，并应由使用者自行确认其授权。
