# 键鼠映射

Windows 上的轻量键鼠重映射工具。用 AutoHotkey v2 拦截按键，用 WebView2 显示界面，编译后只需一个 EXE。

## 功能

- 把一个按键或最多三个按键的组合映射成另一个按键或组合（也可以映射为“无”以屏蔽）
- 点击录制框即可捕获按键，不必手写按键名
- 鼠标左/右键不能作为原始按键单独映射，但可以作为映射目标
- 映射前检查前缀冲突，冲突和限制提示显示在左侧
- 配置保存在当前用户 AppData，不写进 EXE
- 开机自启（当前用户注册表，不需要管理员）
- 关闭窗口后继续在后台生效，托盘「退出」才结束进程
- 单实例：再打开一份 EXE 只会唤起已有窗口

## 系统要求

- Windows 10 或更高版本
- [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)（多数系统已自带）
- 从源码运行或编译时还需要 [AutoHotkey v2](https://www.autohotkey.com/)（64 位）和 Ahk2Exe

## 配置位置

```
%AppData%\键鼠映射\键鼠映射.ini
```

WebView2 的用户数据在：

```
%LocalAppData%\键鼠映射\WebView2
```

开机自启写入：

```
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run
值名称：键鼠映射
```

同一 Windows 用户下的多个 EXE 副本共用这份配置。把 EXE 拷到另一台电脑时，那边没有对应 AppData，会从空映射开始。

## 从源码编译

1. 安装 AutoHotkey v2（64 位）和 Ahk2Exe。
2. 在源码目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

成功后输出在 `exe\`，文件名类似 `键鼠映射v1.6.exe`。脚本会打印文件大小和 SHA-256。EXE 和托盘图标由脚本按界面里的键盘 logo 生成，不需要单独准备 `img` 或 `.ico` 文件。

## 杀毒软件误报

编译后的 AutoHotkey 程序会安装全局热键，还可以写入开机自启、隐藏托盘图标，部分杀毒软件会把它判为可疑程序。这是 AHK 编译产物的常见情况。

本程序：

- 只在本机拦截你配置的按键
- 不需要管理员权限
- 不访问网络
- 配置只写在当前用户的 AppData

请以本仓库源码和 Release 中的 SHA-256 为准。

## 许可证

本项目以 [MIT](LICENSE) 许可。第三方声明见 [NOTICE](NOTICE)。界面依赖 [WebViewToo](https://github.com/The-CoDingman/WebViewToo)（MIT）。