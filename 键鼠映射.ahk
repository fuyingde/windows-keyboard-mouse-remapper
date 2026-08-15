#Requires AutoHotkey v2.0
#SingleInstance Off
;@Ahk2Exe-SetVersion 1.6.0.0
;@Ahk2Exe-SetName 键鼠映射
;@Ahk2Exe-SetDescription 键鼠映射 v1.6
#Include Lib\WebViewToo.ahk

APP_VERSION := "1.6"

SetWorkingDir A_ScriptDir
SendMode "Input"
SetKeyDelay -1, -1
SetMouseDelay -1

global App := {
    gui: 0,
    ipcGui: 0,
    instanceMutex: 0,
    ipcTitle: "KeyMouseMapper-IPC-{9A01C16D-7C45-4F94-9C84-719A01E32A90}",
    showMessage: 0x8001,
    pendingShow: false,
    configDir: A_AppData "\键鼠映射",
    iniFile: A_AppData "\键鼠映射\键鼠映射.ini",
    webviewDir: EnvGet("LOCALAPPDATA") "\键鼠映射\WebView2",
    startupKey: "HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
    startupValue: "键鼠映射",
    settings: {autoStart: false, trayIcon: true}
}

global Mapping := {
    rows: [], nextId: 1, enabled: false, suspended: false,
    activeCapture: 0, captureKeys: [], captureDown: Map(), ignoreUntilUp: Map(), captureHook: 0,
    installedSourceHotkeys: Map(), pressedKeys: Map(), pressOrder: [], activeMappings: Map(),
    suppressedKeys: Map()
}

InitializeSingleInstance()
DirCreate(App.configDir)
DirCreate(App.webviewDir)
LoadSettings()
ConfigureTray()
MappingInitialize()
BuildGui()
InstallUiMouseGuardHotkeys()
MappingEnable()
return

BuildGui() {
    global App

    try {
        LoadEmbeddedUi(&html, &bridge)
        App.gui := WebViewGui("-Caption -Resize +MinSize960x550 +MaxSize960x550", "键鼠映射",, {
            DefaultWidth: 960,
            DefaultHeight: 550,
            DataDir: App.webviewDir
        })
        App.gui.AreDefaultContextMenusEnabled := false
        App.gui.AreDevToolsEnabled := false
        html := StrReplace(html, "</body>", "<script>`n" bridge "`n</script>`n</body>")
        App.gui.AddTextRoute("index.html", html)
        App.gui.Navigate("index.html")
        App.gui.OnEvent("Close", HideApp)
        App.gui.Show("w960 h550 Center")
    } catch as err {
        MsgBox "无法启动 WebView2 界面。`n`n" err.Message "`n`n请确认系统已经安装 Microsoft Edge WebView2 Runtime。", "键鼠映射", "Iconx"
        ExitApp()
    }
}

InitializeSingleInstance() {
    global App

    App.instanceMutex := DllCall("CreateMutexW", "Ptr", 0, "Int", true,
        "Str", "Local\KeyMouseMapper-{9A01C16D-7C45-4F94-9C84-719A01E32A90}", "Ptr")
    if !App.instanceMutex
        throw OSError()

    if A_LastError = 183 {
        DetectHiddenWindows true
        Loop 30 {
            targetHwnd := WinExist(App.ipcTitle " ahk_class AutoHotkeyGUI")
            if targetHwnd {
                DllCall("PostMessage", "Ptr", targetHwnd, "UInt", App.showMessage,
                    "Ptr", 0, "Ptr", 0)
                break
            }
            Sleep 100
        }
        ExitApp()
    }

    App.ipcGui := Gui("+ToolWindow -Caption", App.ipcTitle)
    OnMessage(App.showMessage, RestoreInstanceRequest)
    OnExit(CleanupInstance)
}

RestoreInstanceRequest(*) {
    ShowApp()
}

CleanupInstance(*) {
    global App
    try MappingDisable()
    if App.instanceMutex {
        DllCall("CloseHandle", "Ptr", App.instanceMutex)
        App.instanceMutex := 0
    }
}

LoadEmbeddedUi(&html, &bridge) {
    processId := DllCall("GetCurrentProcessId", "UInt")
    tempDir := A_Temp "\KeyMouseMapper-" processId
    tempHtml := tempDir "\index.html"
    tempBridge := tempDir "\bridge.js"

    DirCreate(tempDir)
    try {
        FileInstall "index.html", tempHtml, true
        FileInstall "bridge.js", tempBridge, true
        html := FileRead(tempHtml, "UTF-8")
        bridge := FileRead(tempBridge, "UTF-8")
    } finally {
        try FileDelete(tempHtml)
        try FileDelete(tempBridge)
        try DirDelete(tempDir)
    }
}

ConfigureTray() {
    global App
    A_IconTip := "键鼠映射"
    A_TrayMenu.Delete()
    A_TrayMenu.Add("退出", ExitFromTray)
    A_TrayMenu.Default := ""
    ApplyAppIcon()
    A_IconHidden := !App.settings.trayIcon
    OnMessage(0x404, TrayIconMessage)
}

ApplyAppIcon() {
    if A_IsCompiled {
        try TraySetIcon(A_ScriptFullPath, 1, true)
        return
    }
    iconPath := A_Temp "\KeyMouseMapper-app-" APP_VERSION ".ico"
    buildScript := A_ScriptDir "\build.ps1"
    if !FileExist(iconPath) && FileExist(buildScript) {
        RunWait 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' buildScript '" -IconOnly "' iconPath '"',, "Hide"
    }
    if FileExist(iconPath)
        try TraySetIcon(iconPath, 1, true)
}

TrayIconMessage(wParam, lParam, *) {
    eventCode := lParam & 0xFFFF
    if eventCode = 0x202 || eventCode = 0x203
        ShowApp()
}

LoadSettings() {
    global App
    App.settings.trayIcon := ReadIniBool("Settings", "TrayIcon", true)
    App.settings.autoStart := IsAutoStartEnabled()
    SaveSettings()
}

ReadIniBool(section, key, defaultValue) {
    global App
    try value := Trim(String(IniRead(App.iniFile, section, key, defaultValue ? "1" : "0")))
    catch
        return defaultValue
    value := StrLower(value)
    return value = "1" || value = "true" || value = "yes" || value = "on"
}

ToBool(value) {
    value := StrLower(Trim(String(value)))
    return value = "1" || value = "true" || value = "yes" || value = "on"
}

StartupCommand() {
    return A_IsCompiled
        ? '"' A_ScriptFullPath '"'
        : '"' A_AhkPath '" "' A_ScriptFullPath '"'
}

IsAutoStartEnabled() {
    global App
    command := ""
    try command := RegRead(App.startupKey, App.startupValue)
    return command != "" && StrLower(Trim(command)) = StrLower(StartupCommand())
}

SetAutoStart(enabled) {
    global App
    enabled := ToBool(enabled)

    try {
        if enabled {
            RegWrite StartupCommand(), "REG_SZ", App.startupKey, App.startupValue
        } else {
            try RegDelete App.startupKey, App.startupValue
        }

        App.settings.autoStart := IsAutoStartEnabled()
        SaveSettings()
        if App.settings.autoStart != enabled
            return SettingResultJson(false, App.settings.autoStart, "系统没有接受开机自启设置。")
        return SettingResultJson(true, App.settings.autoStart, "")
    } catch as err {
        App.settings.autoStart := IsAutoStartEnabled()
        return SettingResultJson(false, App.settings.autoStart, "无法修改开机自启：" err.Message)
    }
}

SetTrayIcon(enabled) {
    global App
    enabled := ToBool(enabled)

    try {
        App.settings.trayIcon := enabled
        SaveSettings()
        A_IconHidden := !enabled
        return SettingResultJson(true, enabled, "")
    } catch as err {
        return SettingResultJson(false, App.settings.trayIcon, "无法保存托盘图标设置：" err.Message)
    }
}

SaveSettings() {
    global App
    DirCreate(App.configDir)
    IniWrite(App.settings.autoStart ? 1 : 0, App.iniFile, "Settings", "AutoStart")
    IniWrite(App.settings.trayIcon ? 1 : 0, App.iniFile, "Settings", "TrayIcon")
}

SettingResultJson(ok, value, message) {
    return '{"ok":' (ok ? "true" : "false")
        . ',"value":' (value ? "true" : "false")
        . ',"message":' JsonQuote(message) "}"
}

GetInitialState() {
    global App, Mapping, APP_VERSION

    json := '{"mappings":['
    for index, row in Mapping.rows {
        if index > 1
            json .= ","
        json .= "{"
            . '"id":' row.id ","
            . '"from":' JsonQuote(row.source) ","
            . '"fromLabel":' JsonQuote(DisplayCombo(row.source)) ","
            . '"to":' JsonQuote(row.target) ","
            . '"toLabel":' JsonQuote(DisplayCombo(row.target)) ","
            . '"saved":true'
            . "}"
    }
    return json . '],"settings":{"autoStart":' (App.settings.autoStart ? "true" : "false")
        . ',"trayIcon":' (App.settings.trayIcon ? "true" : "false")
        . '},"version":' JsonQuote(APP_VERSION) "}"
}

MappingInitialize() {
    MappingLoad()
    MappingInstallMouseCaptureHotkeys()
}

MappingEnable() {
    global Mapping
    Mapping.enabled := true
    Mapping.suspended := false
    MappingApply()
}

MappingDisable() {
    global Mapping
    Mapping.enabled := false
    MappingCancelCapture(false)
    MappingDisableHotkeys()
}

MappingIsCaptureActive() {
    global Mapping
    return IsObject(Mapping.activeCapture)
}

SaveMapping(id, source, target) {
    global Mapping
    id := Integer(id)
    source := NormalizeCombo(source)
    target := NormalizeCombo(target)
    if target = ""
        target := "NONE"
    if source = ""
        return ResultJson(false, "请先录制原始按键。")
    if error := MappingValidateCombo(source, false)
        return ResultJson(false, error)
    if error := MappingValidateCombo(target, true)
        return ResultJson(false, error)

    for row in Mapping.rows {
        if row.id = id
            continue
        if MappingCombosConflict(source, row.source) {
            if ComboEquals(source, row.source)
                return ResultJson(false, "这个原始按键组合已经存在映射。")
            return ResultJson(false, "与“" DisplayCombo(row.source) "”存在前缀冲突，无法保证按下后立即生效。")
        }
    }

    found := false
    for row in Mapping.rows {
        if row.id = id {
            row.source := source
            row.target := target
            found := true
            break
        }
    }
    if !found
        Mapping.rows.InsertAt(1, {id: id, source: source, target: target})
    MappingSave()
    MappingApply()
    return ResultJson(true, "")
}

DeleteMapping(id) {
    global Mapping
    id := Integer(id)
    MappingCancelCapture()
    for index, row in Mapping.rows {
        if row.id = id {
            Mapping.rows.RemoveAt(index)
            break
        }
    }
    MappingSave()
    MappingApply()
    return ResultJson(true, "")
}

BeginCapture(id, field, pointerInside := true) {
    global Mapping
    if field != "from" && field != "to"
        return false
    MappingCancelCapture(false)
    MappingDisableHotkeys()
    Mapping.suspended := true
    Mapping.activeCapture := {id: Integer(id), field: String(field), pointerInside: ToBool(pointerInside)}
    Mapping.captureKeys := []
    Mapping.captureDown := Map()
    Mapping.ignoreUntilUp := Map()
    if GetKeyState("LButton", "P")
        Mapping.ignoreUntilUp["lbutton"] := true

    ih := InputHook("T30 L0")
    ih.VisibleText := false
    ih.VisibleNonText := false
    ih.KeyOpt("{All}", "N")
    ih.OnKeyDown := MappingCaptureKeyDown
    ih.OnKeyUp := MappingCaptureKeyUp
    ih.OnEnd := MappingCaptureEnded
    Mapping.captureHook := ih
    ih.Start()
    return true
}

SetMappingCapturePointerInside(inside) {
    global Mapping
    if IsObject(Mapping.activeCapture)
        Mapping.activeCapture.pointerInside := ToBool(inside)
    return true
}

CancelCapture(restoreMappings := true) {
    return MappingCancelCapture(restoreMappings)
}

MappingCancelCapture(restoreMappings := true) {
    global Mapping
    Mapping.activeCapture := 0
    Mapping.captureKeys := []
    Mapping.captureDown := Map()
    Mapping.ignoreUntilUp := Map()
    ih := Mapping.captureHook
    Mapping.captureHook := 0
    if IsObject(ih)
        try ih.Stop()
    if restoreMappings && Mapping.suspended {
        Mapping.suspended := false
        MappingApply()
    }
    return true
}

MappingCaptureEnded(ih) {
    global Mapping
    if !IsObject(Mapping.activeCapture) || Mapping.captureHook != ih
        return
    capture := Mapping.activeCapture
    MappingCancelCapture()
    MappingNotifyCancelled(capture)
}

MappingCaptureKeyDown(ih, vk, sc) {
    global Mapping
    if !IsObject(Mapping.activeCapture) || Mapping.captureHook != ih
        return
    keyName := GetInputKeyName(vk, sc)
    if keyName = ""
        return
    lower := StrLower(keyName)
    if Mapping.ignoreUntilUp.Has(lower)
        return
    if Mapping.captureDown.Has(lower) || ComboArrayHasKey(Mapping.captureKeys, keyName)
        return
    if Mapping.captureKeys.Length >= 3 {
        Mapping.ignoreUntilUp[lower] := true
        NotifyCaptureWarning("组合键最多只能包含 3 个按键。")
        return
    }
    if MappingRejectsProtectedSource(keyName) {
        Mapping.ignoreUntilUp[lower] := true
        NotifyCaptureWarning("鼠标左/右键不能单独映射。")
        return
    }
    Mapping.captureKeys.Push(keyName)
    Mapping.captureDown[lower] := true
    MappingNotifyProgress()
}

MappingCaptureKeyUp(ih, vk, sc) {
    global Mapping
    if !IsObject(Mapping.activeCapture) || Mapping.captureHook != ih
        return
    keyName := GetInputKeyName(vk, sc)
    lower := StrLower(keyName)
    if Mapping.ignoreUntilUp.Has(lower) {
        Mapping.ignoreUntilUp.Delete(lower)
        return
    }
    if Mapping.captureDown.Has(lower)
        Mapping.captureDown.Delete(lower)
    if Mapping.captureKeys.Length && Mapping.captureDown.Count = 0
        MappingCompleteCapture()
}

MappingInstallMouseCaptureHotkeys() {
    static installed := false
    if installed
        return
    installed := true
    for name in ["LButton", "RButton", "MButton", "XButton1", "XButton2", "WheelUp", "WheelDown", "WheelLeft", "WheelRight"] {
        HotIf MappingCaptureMouseDownActive.Bind(name)
        Hotkey("$*" name, MappingCaptureMouseDown.Bind(name), "On")
        if !IsWheel(name) {
            HotIf MappingCaptureMouseUpActive.Bind(name)
            Hotkey("$*" name " Up", MappingCaptureMouseUp.Bind(name), "On")
        }
    }
    HotIf
}

MappingCaptureMouseDownActive(name, *) {
    global Mapping
    if !IsObject(Mapping.activeCapture)
        return false
    if IsProtectedMouse(name) && Mapping.captureKeys.Length = 0
        return Mapping.activeCapture.pointerInside
    return true
}

MappingCaptureMouseUpActive(name, *) {
    global Mapping
    if !IsObject(Mapping.activeCapture)
        return false
    lower := StrLower(name)
    return Mapping.captureDown.Has(lower) || Mapping.ignoreUntilUp.Has(lower)
}

MappingCaptureMouseDown(name, *) {
    global Mapping
    lower := StrLower(name)
    if Mapping.ignoreUntilUp.Has(lower) || Mapping.captureDown.Has(lower) || ComboArrayHasKey(Mapping.captureKeys, name)
        return
    if Mapping.captureKeys.Length >= 3 {
        Mapping.ignoreUntilUp[lower] := true
        NotifyCaptureWarning("组合键最多只能包含 3 个按键。")
        return
    }
    if MappingRejectsProtectedSource(name) {
        Mapping.ignoreUntilUp[lower] := true
        NotifyCaptureWarning("鼠标左/右键不能单独映射。")
        return
    }
    Mapping.captureKeys.Push(name)
    if !IsWheel(name)
        Mapping.captureDown[lower] := true
    MappingNotifyProgress()
    if IsWheel(name)
        MappingCompleteCapture()
}

MappingCaptureMouseUp(name, *) {
    global Mapping
    lower := StrLower(name)
    if Mapping.ignoreUntilUp.Has(lower) {
        Mapping.ignoreUntilUp.Delete(lower)
        return
    }
    if Mapping.captureDown.Has(lower)
        Mapping.captureDown.Delete(lower)
    if Mapping.captureKeys.Length && Mapping.captureDown.Count = 0
        MappingCompleteCapture()
}

MappingCompleteCapture() {
    global Mapping
    if !IsObject(Mapping.activeCapture) || !Mapping.captureKeys.Length
        return
    capture := Mapping.activeCapture
    combo := JoinCombo(Mapping.captureKeys)
    MappingCancelCapture()
    SendCaptureToWeb(capture.id, capture.field, combo, DisplayCombo(combo))
}

MappingNotifyProgress() {
    global App, Mapping
    if !IsObject(Mapping.activeCapture)
        return
    capture := Mapping.activeCapture
    combo := JoinCombo(Mapping.captureKeys)
    script := "window.app&&window.app.receiveCaptureProgress(" capture.id "," JsonQuote(capture.field)
        . "," JsonQuote(combo) "," JsonQuote(DisplayCombo(combo)) ");"
    try App.gui.ExecuteScriptAsync(script)
}

MappingNotifyCancelled(capture := 0) {
    global App
    try App.gui.ExecuteScriptAsync("window.app&&window.app.captureCancelled();")
}

SendCaptureToWeb(id, field, keyName, label) {
    global App
    script := "window.app&&window.app.receiveCapture(" id "," JsonQuote(field) "," JsonQuote(keyName) "," JsonQuote(label) ");"
    try App.gui.ExecuteScriptAsync(script)
}

NotifyCaptureWarning(message) {
    global App
    try App.gui.ExecuteScriptAsync("window.app&&window.app.captureWarning(" JsonQuote(message) ");")
}

NotifyBackendError(message) {
    global App
    if IsObject(App.gui)
        try App.gui.ExecuteScriptAsync("window.app&&window.app.backendError(" JsonQuote(message) ");")
}

MappingApply() {
    global Mapping
    MappingDisableHotkeys()
    if !Mapping.enabled || Mapping.suspended
        return
    for row in Mapping.rows {
        row.sourceKeys := SplitCombo(row.source)
        row.targetKeys := SplitCombo(row.target)
        for keyName in row.sourceKeys
            MappingRegisterSourceHotkey(keyName)
    }
}

MappingDisableHotkeys() {
    global Mapping
    MappingReleaseAll()
    Mapping.pressedKeys := Map()
    Mapping.pressOrder := []
    Mapping.suppressedKeys := Map()
}

MappingRegisterSourceHotkey(keyName) {
    global Mapping
    lower := StrLower(keyName)
    if Mapping.installedSourceHotkeys.Has(lower)
        return
    try {
        HotIf MappingSourceKeyDownActive.Bind(keyName)
        Hotkey("$*" keyName, MappingSourceDown.Bind(keyName), "On")
        if !IsWheel(keyName) {
            HotIf MappingSourceKeyUpActive.Bind(keyName)
            Hotkey("$*" keyName " Up", MappingSourceUp.Bind(keyName), "On")
        }
        HotIf
        Mapping.installedSourceHotkeys[lower] := true
    } catch as err {
        HotIf
        NotifyBackendError("无法启用按键 “" DisplayName(keyName) "”：" err.Message)
    }
}

MappingSourceKeyDownActive(keyName, *) {
    global Mapping
    if !Mapping.enabled || Mapping.suspended || IsObject(Mapping.activeCapture) || UiGuardActive()
        return false
    lower := StrLower(keyName)
    if Mapping.pressedKeys.Has(lower)
        return true
    for row in Mapping.rows {
        keys := row.sourceKeys
        for index, candidate in keys {
            if StrLower(candidate) != lower
                continue
            if index = 1 || MappingPressOrderEndsWithPrefix(keys, index - 1)
                return true
        }
    }
    return false
}

MappingSourceKeyUpActive(keyName, *) {
    global Mapping
    return Mapping.enabled && !Mapping.suspended
        && !IsObject(Mapping.activeCapture) && Mapping.pressedKeys.Has(StrLower(keyName))
}

MappingPressOrderEndsWithPrefix(keys, prefixLength) {
    global Mapping
    if prefixLength > Mapping.pressOrder.Length
        return false
    offset := Mapping.pressOrder.Length - prefixLength
    Loop prefixLength {
        if StrLower(Mapping.pressOrder[offset + A_Index]) != StrLower(keys[A_Index])
            return false
    }
    return true
}

MappingSourceDown(keyName, *) {
    global Mapping
    lower := StrLower(keyName)
    if IsWheel(keyName) {
        MappingPushPressOrder(keyName)
        MappingTryActivate()
        MappingRemovePressOrder(keyName)
        return
    }
    if Mapping.pressedKeys.Has(lower)
        return
    Mapping.pressedKeys[lower] := keyName
    MappingPushPressOrder(keyName)
    MappingTryActivate()
}

MappingSourceUp(keyName, *) {
    global Mapping
    lower := StrLower(keyName)
    Mapping.pressedKeys.Delete(lower)
    MappingRemovePressOrder(keyName)
    ids := []
    for id, row in Mapping.activeMappings {
        if ComboArrayHasKey(row.sourceKeys, keyName)
            ids.Push(id)
    }
    for id in ids
        MappingDeactivate(id)
}

MappingTryActivate() {
    global Mapping
    best := 0
    bestLength := 0
    for row in Mapping.rows {
        if Mapping.activeMappings.Has(row.id) || row.sourceKeys.Length < bestLength
            continue
        if MappingComboMatchesPressOrder(row.sourceKeys) && row.sourceKeys.Length > bestLength {
            best := row
            bestLength := row.sourceKeys.Length
        }
    }
    if !IsObject(best)
        return
    Mapping.activeMappings[best.id] := best
    SendCombo(best.targetKeys, "down")
    if ComboContainsWheel(best.sourceKeys)
        MappingDeactivate(best.id)
}

MappingDeactivate(id) {
    global Mapping
    if !Mapping.activeMappings.Has(id)
        return
    row := Mapping.activeMappings[id]
    SendCombo(row.targetKeys, "up")
    Mapping.activeMappings.Delete(id)
}

MappingReleaseAll() {
    global Mapping
    ids := []
    for id in Mapping.activeMappings
        ids.Push(id)
    for id in ids
        MappingDeactivate(id)
}

MappingPushPressOrder(keyName) {
    global Mapping
    MappingRemovePressOrder(keyName)
    Mapping.pressOrder.Push(keyName)
}

MappingRemovePressOrder(keyName) {
    global Mapping
    lower := StrLower(keyName)
    Loop Mapping.pressOrder.Length {
        if StrLower(Mapping.pressOrder[A_Index]) = lower {
            Mapping.pressOrder.RemoveAt(A_Index)
            return
        }
    }
}

MappingComboMatchesPressOrder(keys) {
    global Mapping
    if keys.Length > Mapping.pressOrder.Length
        return false
    offset := Mapping.pressOrder.Length - keys.Length
    for index, keyName in keys {
        if StrLower(Mapping.pressOrder[offset + index]) != StrLower(keyName)
            return false
    }
    return true
}

MappingValidateCombo(value, allowNone := false) {
    if value = "NONE"
        return allowNone ? "" : "原始按键不能为空。"
    keys := SplitCombo(value)
    if keys.Length < 1
        return allowNone ? "" : "原始按键不能为空。"
    if keys.Length > 3
        return "组合键最多只能包含 3 个按键。"
    if !allowNone && IsProtectedMouse(keys[1])
        return "鼠标左/右键不能单独映射。"
    if !allowNone {
        Loop keys.Length - 1 {
            if IsWheel(keys[A_Index])
                return "滚轮没有持续按住状态，只能位于原始组合键的最后一位。"
        }
    }
    seen := Map()
    for keyName in keys {
        lower := StrLower(keyName)
        if seen.Has(lower)
            return "同一个组合键中不能重复使用按键。"
        seen[lower] := true
    }
    return ""
}

MappingCombosConflict(first, second) {
    a := SplitCombo(first), b := SplitCombo(second)
    Loop Min(a.Length, b.Length) {
        if StrLower(a[A_Index]) != StrLower(b[A_Index])
            return false
    }
    return true
}

MappingSave() {
    global App, Mapping
    DirCreate(App.configDir)
    IniWrite(Mapping.rows.Length, App.iniFile, "Mappings", "Count")
    for index, row in Mapping.rows {
        IniWrite(row.source, App.iniFile, "Map" index, "Source")
        IniWrite(row.target, App.iniFile, "Map" index, "Target")
    }

    leftover := Mapping.rows.Length + 1
    Loop {
        section := "Map" leftover
        source := IniRead(App.iniFile, section, "Source", Chr(1))
        if source = Chr(1)
            break
        IniDelete(App.iniFile, section)
        leftover += 1
        if leftover > 10000
            break
    }
}

MappingLoad() {
    global App, Mapping
    count := 0
    try count := Integer(IniRead(App.iniFile, "Mappings", "Count", "0"))
    catch
        count := 0
    Loop count {
        source := NormalizeCombo(IniRead(App.iniFile, "Map" A_Index, "Source", ""))
        target := NormalizeCombo(IniRead(App.iniFile, "Map" A_Index, "Target", "NONE"))
        if source != ""
            Mapping.rows.Push({id: Mapping.nextId++, source: source, target: target = "" ? "NONE" : target})
    }
}

InstallUiMouseGuardHotkeys() {
    static installed := false
    if installed
        return
    installed := true
    HotIf UiMouseGuardActive
    for name in ["RButton", "MButton", "XButton1", "XButton2"] {
        Hotkey("$*" name, BlockUiInput, "On")
        Hotkey("$*" name " Up", BlockUiInput, "On")
    }
    HotIf
}

UiMouseGuardActive(hotkeyName := "") {
    global App
    if !UiGuardActive(hotkeyName)
        return false
    MouseGetPos(,, &hoverHwnd)
    if !hoverHwnd
        return false
    return hoverHwnd = App.gui.Hwnd
        || DllCall("IsChild", "Ptr", App.gui.Hwnd, "Ptr", hoverHwnd, "Int")
}

UiGuardActive(hotkeyName := "") {
    global App
    if !IsObject(App.gui) || !WinActive("ahk_id " App.gui.Hwnd)
        return false
    if MappingIsCaptureActive()
        return false
    if hotkeyName != "" && (GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P"))
        && !RegExMatch(String(hotkeyName), "i)(RButton|MButton|XButton1|XButton2)")
        return false
    return true
}

BlockUiInput(*) {
}

MinimizeApp() {
    global App
    App.gui.Minimize()
}

CloseApp() {
    HideApp()
}

HideApp(*) {
    global App
    MappingCancelCapture()
    App.gui.Hide()
}

ShowApp(*) {
    global App
    if !IsObject(App.gui) {
        App.pendingShow := true
        return
    }
    try {
        App.gui.Show()
        if WinGetMinMax("ahk_id " App.gui.Hwnd) = -1
            App.gui.Restore()
        WinActivate("ahk_id " App.gui.Hwnd)
        App.pendingShow := false
    }
}

ExitFromTray(*) {
    ExitApp()
}

NormalizeCombo(value) {
    value := Trim(String(value))
    if value = "" || StrUpper(value) = "NONE"
        return value = "" ? "" : "NONE"
    return JoinCombo(SplitCombo(value))
}

SplitCombo(value) {
    value := Trim(String(value))
    keys := []
    if value = "" || StrUpper(value) = "NONE"
        return keys
    for keyName in StrSplit(value, "|") {
        keyName := Trim(keyName)
        if keyName != ""
            keys.Push(keyName)
    }
    return keys
}

JoinCombo(keys) {
    result := ""
    for index, keyName in keys
        result .= (index > 1 ? "|" : "") keyName
    return result
}

DisplayCombo(value) {
    if String(value) = "NONE" || String(value) = ""
        return "无"
    labels := ""
    for index, keyName in SplitCombo(value)
        labels .= (index > 1 ? " + " : "") DisplayName(keyName)
    return labels
}

DisplayName(value) {
    value := String(value)
    if value = "NONE"
        return "无"

    names := Map(
        "space", "空格", "escape", "Esc", "return", "Enter", "delete", "Delete",
        "backspace", "Backspace", "tab", "Tab", "capslock", "Caps Lock",
        "launch_media", "播放器", "volume_mute", "静音", "volume_up", "音量＋",
        "volume_down", "音量－", "media_play_pause", "播放/暂停",
        "media_next", "下一曲", "media_prev", "上一曲", "mbutton", "鼠标中键",
        "lbutton", "鼠标左键", "rbutton", "鼠标右键", "xbutton1", "鼠标侧键1",
        "xbutton2", "鼠标侧键2", "wheelup", "滚轮向上", "wheeldown", "滚轮向下",
        "wheelleft", "滚轮向左", "wheelright", "滚轮向右", "lcontrol", "左 Ctrl",
        "rcontrol", "右 Ctrl", "lshift", "左 Shift", "rshift", "右 Shift",
        "lalt", "左 Alt", "ralt", "右 Alt", "lwin", "左 Win", "rwin", "右 Win"
    )

    lower := StrLower(value)
    if names.Has(lower)
        return names[lower]
    if StrLen(value) = 1
        return StrUpper(value)
    return value
}

IsWheel(name) {
    name := StrLower(String(name))
    return name = "wheelup" || name = "wheeldown" || name = "wheelleft" || name = "wheelright"
}

IsAnyMouseButton(name) {
    name := StrLower(String(name))
    return name = "lbutton" || name = "rbutton" || name = "mbutton" || name = "xbutton1" || name = "xbutton2"
}

IsProtectedMouse(name) {
    name := StrLower(String(name))
    return name = "lbutton" || name = "rbutton"
}

MappingRejectsProtectedSource(keyName) {
    global Mapping
    return IsObject(Mapping.activeCapture)
        && Mapping.activeCapture.field = "from"
        && Mapping.captureKeys.Length = 0
        && IsProtectedMouse(keyName)
}

ComboArrayHasKey(keys, keyName) {
    lower := StrLower(String(keyName))
    for candidate in keys {
        if StrLower(candidate) = lower
            return true
    }
    return false
}

ComboContainsWheel(keys) {
    for keyName in keys {
        if IsWheel(keyName)
            return true
    }
    return false
}

ComboEquals(first, second) {
    firstKeys := SplitCombo(first)
    secondKeys := SplitCombo(second)
    if firstKeys.Length != secondKeys.Length
        return false
    for index, keyName in firstKeys {
        if StrLower(keyName) != StrLower(secondKeys[index])
            return false
    }
    return true
}

SendPhysicalKey(target, action) {
    if target = "" || target = "NONE"
        return
    SendLevel 0
    if IsWheel(target) {
        if action = "down"
            Click(target)
        return
    }
    if IsAnyMouseButton(target) {
        Click(target " " (action = "down" ? "Down" : "Up"))
        return
    }
    try SendEvent("{Blind}{" target " " action "}")
}

SendCombo(keys, action) {
    if !IsObject(keys) || !keys.Length
        return
    if action = "down" {
        for keyName in keys
            SendPhysicalKey(keyName, "down")
    } else {
        Loop keys.Length
            SendPhysicalKey(keys[keys.Length - A_Index + 1], "up")
    }
}

ResultJson(ok, message) {
    return '{"ok":' (ok ? "true" : "false") ',"message":' JsonQuote(message) "}"
}

JsonQuote(value) {
    value := String(value)
    value := StrReplace(value, "\", "\\")
    value := StrReplace(value, '"', '\"')
    value := StrReplace(value, "`r", "\r")
    value := StrReplace(value, "`n", "\n")
    value := StrReplace(value, "`t", "\t")
    return '"' value '"'
}

GetInputKeyName(vk, sc) {
    keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    return keyName != "" ? keyName : GetKeyName(Format("vk{:02X}", vk))
}
