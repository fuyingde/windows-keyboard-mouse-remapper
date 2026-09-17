# 编译说明

当前正式版只发布 EXE。1.8 之后的完整源码暂不公开，因此下面的步骤只适用于仓库中已经开源的 **1.8**。

如果你只是使用软件，请直接下载官网或 GitHub Releases 中的最新 EXE，不必编译。

## 适用范围

- 适用版本：已公开的 1.8 源码
- 不适用于：1.9 及之后只发布 EXE 的版本

## 准备图标

1.8 源码编译前，如果项目根目录下没有 `img` 文件夹，请自行新建，再确认存在以下文件：

```text
img/img.ico
img/img.svg
```

`img.ico` 用于 EXE、任务栏、Alt+Tab 和托盘图标；`img.svg` 用于软件界面中的图标资源。目录和文件名必须完全一致。

## 构建

准备好与 1.8 源码对应的 Windows 脚本运行环境和编译工具后，在该版本源码根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

构建完成后的文件位于：

```text
exe/KeyMouseTools-v1.8.exe
```

1.8 之后的版本请使用已发布的 EXE，不要假设当前仓库包含最新完整源码。
