# Build Notes

The current official release is an EXE only. Complete source after 1.8 is not published, so these steps apply only to the last open-source snapshot: **1.8**.

If you just want to use the app, download the latest EXE from the official site or GitHub Releases. You do not need to compile anything.

## Scope

- Applies to: the published 1.8 source
- Does not apply to: 1.9 and later EXE-only releases

## Prepare icons

Before compiling the 1.8 source, create an `img` directory at the project root if it does not already exist, then make sure these files are present:

```text
img/img.ico
img/img.svg
```

`img.ico` is used for the EXE, taskbar, Alt+Tab, and tray icon. `img.svg` is used by the application interface. The directory and file names must match exactly.

## Build

After preparing a Windows script runtime and compiler compatible with the 1.8 source, run this command at that source root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

The completed file is written to:

```text
exe/KeyMouseTools-v1.8.exe
```

For versions after 1.8, use the published EXE. Do not assume this repository contains the latest complete source.
