# 键鼠映射工具 v1.8（开源版）

轻量的 Windows 键盘与鼠标按键映射工具。映射实时生效，无需修改系统按键注册表或重启电脑。下载下方 EXE 即可直接使用，无需配置开发环境

## v1.8 更新内容

- 修复映射按下只触发一次、不会连续输入的问题
- 新增虚拟键盘，损坏或无法按下的按键可通过屏幕键盘录入映射

## 使用方法

1. 下载并运行 `KeyMouseMapper-OpenSource-v1.8.exe`
2. 首次启动时选择界面语言
3. 点击“添加映射”，依次录制原始按键和目标按键
4. 保存并勾选该条映射即可生效

取消勾选会立即恢复原始按键输入。关闭窗口后软件会在托盘继续运行，使用托盘右键菜单中的“退出”才会完全结束

## 运行要求

- 64 位 Windows 10 或 Windows 11
- Microsoft Edge WebView2 Runtime，多数系统已经自带

如果需要映射以管理员身份运行的软件，请同时以管理员身份运行本工具

## 安全说明

本软件不收集或上传用户配置。由于软件使用全局输入钩子和模拟输入，少数安全软件可能产生误报，请以本仓库源码和下方 SHA-256 为准

**SHA-256**

`2018B2738CE370F3D44190063D309D013D86E05072D4D92BDF90F650DBAE3818`

完整功能、源码编译和使用限制请查看仓库首页

---

## English

Keyboard & Mouse Remapper for Windows v1.8 is a lightweight keyboard and mouse remapping tool. Mappings take effect immediately without permanently changing system keys or restarting Windows. Download the EXE below and run it directly without setting up a development environment

### What's new in v1.8

- Fixed mapped keys firing only once instead of repeating
- Added a virtual keyboard so damaged or unpressable keys can be recorded on screen

### Quick start

1. Download and run `KeyMouseMapper-OpenSource-v1.8.exe`
2. Choose an interface language on first launch
3. Select “Add Mapping” and record the source and target
4. Save the mapping and select its checkbox to enable it

Clear a mapping's checkbox to restore the original input immediately. Closing the window keeps enabled mappings running in the tray; use “Exit” from the tray menu to stop the app completely

### Requirements

- 64-bit Windows 10 or Windows 11
- Microsoft Edge WebView2 Runtime, already present on most systems

Run this tool as administrator when mapping input inside an application that also runs as administrator

### Safety

The app does not collect or upload user configuration. Because it uses global input hooks and simulated input, a small number of security products may report a false positive. Verify the source code and SHA-256 below if needed

**SHA-256**

`2018B2738CE370F3D44190063D309D013D86E05072D4D92BDF90F650DBAE3818`
