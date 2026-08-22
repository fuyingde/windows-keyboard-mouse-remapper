#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Off
;@Ahk2Exe-SetVersion 1.8.0.0
;@Ahk2Exe-SetName KeyMouseMapper
;@Ahk2Exe-SetDescription Key Mouse Mapper v1.8 Open Source
#Include Lib\WebViewToo.ahk
#Include Core\GeneratedLocales.ahk
#Include Core\LanguageCore.ahk
#Include Core\InputCommon.ahk
#Include Core\SettingsCore.ahk
#Include Core\MappingCore.ahk

if A_Args.Length && A_Args[1] = "--syntax-check"
    ExitApp()

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
    version: "1.8",
    locale: "zh-CN",
    languageSelected: false,
    trayConfigured: false,
    mode: "mapping",
    inputEnabled: true,
    topMost: false,
    configDir: A_AppData "\FuYingKeyMouseTools",
    localDataDir: EnvGet("LOCALAPPDATA") "\FuYingKeyMouseTools",
    settingsFile: A_AppData "\FuYingKeyMouseTools\settings.ini",
    mappingsFile: A_AppData "\FuYingKeyMouseTools\mappings.ini",
    autoPressFile: A_AppData "\FuYingKeyMouseTools\auto-press.ini",
    languageFile: A_AppData "\FuYingKeyMouseTools\language.ini",
    startupKey: "HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
    startupValue: "FuYing.KeyMouseTools",
    settings: {autoStart: false, autoStartDesired: false, autoStartError: "", trayIcon: true,
        storedMode: "mapping", pressDurationMin: 2, pressDurationMax: 5, executionMode: "independent"}
}

InitializeSingleInstance()
DevTrace("instance initialized")
DirCreate(App.configDir)
DirCreate(App.localDataDir)
LanguageInitialize()
DevTrace("language initialized")
SettingsInitialize()
DevTrace("settings initialized")
MappingInitialize()
DevTrace("mapping initialized")
A_IconHidden := true
if App.languageSelected
    ConfigureTray()
BuildGui()
DevTrace("gui built")
if App.languageSelected
    EnableMappingRuntime()
return

DevTrace(message) {
    if !A_IsCompiled
        FileAppend(FormatTime(, "HH:mm:ss") " " message "`n", A_ScriptDir "\dev-startup.log", "UTF-8")
}

BuildGui() {
    global App
    stage := "load-ui"
    startupErrorLog := App.localDataDir "\startup-error.log"
    try FileDelete(startupErrorLog)
    try {
        DevTrace("gui load embedded ui start")
        LoadEmbeddedUi(&html, &bridge, &appIcon, &localesJson)
        DevTrace("gui load embedded ui done")
        webViewDataDir := App.localDataDir "\WebView2"
        DirCreate(webViewDataDir)
        stage := "create-webview"
        DevTrace("gui create webview start")
        App.gui := WebViewGui("-Caption -Resize +MinSize1020x600 +MaxSize1020x1200", AppWindowTitle(),, {
            DefaultWidth: 1020, DefaultHeight: 600, DataDir: webViewDataDir
        })
        DevTrace("gui create webview done")
        stage := "configure-webview"
        App.gui.AreDefaultContextMenusEnabled := false
        App.gui.AreDevToolsEnabled := false
        bootstrapJson := '{"locale":' JsonQuote(App.locale) ',"languageSelected":' (App.languageSelected ? "true" : "false") '}'
        embeddedData := "<script type=`"application/json`" id=`"locales-data`">" EscapeEmbeddedJson(localesJson) "</script>`n"
            . "<script type=`"application/json`" id=`"app-bootstrap`">" EscapeEmbeddedJson(bootstrapJson) "</script>`n"
        html := StrReplace(html, "</body>", "<template id=`"app-icon-template`">" appIcon "</template>`n"
            . embeddedData "<script>`n" bridge "`n</script>`n</body>")
        stage := "register-content"
        App.gui.AddTextRoute("index.html", html)
        stage := "navigate"
        App.gui.Navigate("index.html")
        stage := "show-window"
        App.gui.OnEvent("Close", CloseApp)
        App.gui.Show("w1020 h600 Center")
    } catch as err {
        DevTrace("BuildGui error at " stage ": " err.Message " | " err.What " | " err.Extra " | line " err.Line)
        WriteStartupErrorLog(startupErrorLog, stage, err)
        if !A_IsCompiled {
            MsgBox err.Message, "Key Mouse Mapper development error", "Iconx"
        } else if stage = "create-webview" {
            MsgBox "无法创建软件界面所需的 WebView2 环境。本软件依赖 Microsoft Edge WebView2 Runtime，请先安装或修复 WebView2 Runtime，然后重新运行本软件。`n`nUnable to create the WebView2 environment required by Key Mouse Mapper. This application requires Microsoft Edge WebView2 Runtime. Please install or repair WebView2 Runtime, then run the application again.", "键鼠映射工具 / Key Mouse Mapper", "Iconx"
        } else {
            MsgBox "无法完成键鼠映射工具的界面初始化，请重新运行本软件。`n`nUnable to initialize the Key Mouse Mapper interface. Please restart the application.", "键鼠映射工具 / Key Mouse Mapper", "Iconx"
        }
        ExitApp()
    }
}

WriteStartupErrorLog(path, stage, err) {
    global App
    try {
        details := "Key Mouse Mapper v" App.version " startup diagnostic`r`n"
            . "Time: " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`r`n"
            . "Stage: " stage "`r`n"
            . "Message: " err.Message "`r`n"
            . "What: " err.What "`r`n"
            . "Extra: " err.Extra "`r`n"
            . "File: " err.File "`r`n"
            . "Line: " err.Line "`r`n"
            . "Stack:`r`n" err.Stack "`r`n"
        FileAppend(details, path, "UTF-8")
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
                DllCall("PostMessage", "Ptr", targetHwnd, "UInt", App.showMessage, "Ptr", 0, "Ptr", 0)
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

LoadEmbeddedUi(&html, &bridge, &appIcon, &localesJson) {
    processId := DllCall("GetCurrentProcessId", "UInt")
    tempDir := A_Temp "\KeyMouseMapper-" processId
    tempHtml := tempDir "\index.html"
    tempBridge := tempDir "\bridge.js"
    tempIcon := tempDir "\app-icon.svg"
    tempLocales := tempDir "\compiled-locales.json"
    DirCreate(tempDir)
    try {
        FileInstall "index.html", tempHtml, true
        FileInstall "bridge.js", tempBridge, true
        FileInstall "img\img.svg", tempIcon, true
        FileInstall "locales\compiled-locales.json", tempLocales, true
        html := FileRead(tempHtml, "UTF-8")
        bridge := FileRead(tempBridge, "UTF-8")
        appIcon := RegExReplace(FileRead(tempIcon, "UTF-8"), "s)^.*?(<svg)", "$1")
        localesJson := FileRead(tempLocales, "UTF-8")
    } finally {
        try FileDelete(tempHtml)
        try FileDelete(tempBridge)
        try FileDelete(tempIcon)
        try FileDelete(tempLocales)
        try DirDelete(tempDir)
    }
}

EscapeEmbeddedJson(value) {
    value := StrReplace(String(value), "&", "\u0026")
    value := StrReplace(value, "<", "\u003C")
    return StrReplace(value, ">", "\u003E")
}

ConfigureTray() {
    global App
    App.trayConfigured := true
    A_IconTip := T("app.name")
    A_TrayMenu.Delete()
    A_TrayMenu.Add(T("tray.exit"), ExitFromTray)
    try TraySetIcon(A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\img\img.ico", 1, true)
    A_IconHidden := !App.settings.trayIcon
    OnMessage(0x404, TrayIconMessage)
}

TrayIconMessage(wParam, lParam, *) {
    eventCode := lParam & 0xFFFF
    if eventCode = 0x202 || eventCode = 0x203
        ShowApp()
}

GetInitialState() {
    global App
    return '{"version":' JsonQuote(App.version) ',"locale":' JsonQuote(App.locale)
        . ',"languageSelected":' (App.languageSelected ? "true" : "false") ',"mode":' JsonQuote(App.mode)
        . ',"inputEnabled":' (App.inputEnabled ? "true" : "false")
        . ',"topMost":' (App.topMost ? "true" : "false")
        . ',"mappings":' MappingStateJson()
        . ',"settings":{"autoStart":' (App.settings.autoStart ? "true" : "false")
        . ',"trayIcon":' (App.settings.trayIcon ? "true" : "false") "}}"
}

SetWindowTopMost(enabled) {
    global App
    enabled := ToBool(enabled)
    try {
        App.gui.Opt(enabled ? "+AlwaysOnTop" : "-AlwaysOnTop")
        App.topMost := enabled
        return ResultJson(true, "", ',"enabled":' (enabled ? "true" : "false"))
    } catch as err {
        return ResultJson(false, T("message.windowTopMostFailed"),
            ',"enabled":' (App.topMost ? "true" : "false"))
    }
}

OpenAuthorWebsite() {
    try {
        Run "https://www.imtr.cn/keymousetools"
        return ResultJson(true, "")
    } catch {
        return ResultJson(false, T("message.openWebsiteFailed"))
    }
}

OpenRepositoryWebsite() {
    try {
        Run "https://github.com/fuyingde/windows-keyboard-mouse-remapper"
        return ResultJson(true, "")
    } catch {
        return ResultJson(false, T("message.openRepositoryFailed"))
    }
}

SetInputEnabled(enabled) {
    global App
    enabled := ToBool(enabled)
    if enabled = App.inputEnabled
        return ResultJson(true, "", ',"enabled":' (enabled ? "true" : "false"))

    MappingCancelCapture()
    MappingDisable()

    App.inputEnabled := enabled
    if enabled
        EnableMappingRuntime()
    return ResultJson(true, "", ',"enabled":' (enabled ? "true" : "false"))
}

EnableMappingRuntime() {
    global App
    if !App.inputEnabled
        return
    MappingEnable()
}

MappingRowShouldRun(row) {
    return row.enabled
}

IsAnyInputCaptureActive() {
    return MappingIsCaptureActive()
}

IsAppWindowCaptureEligible() {
    global App
    if !IsObject(App.gui) || !WinActive("ahk_id " App.gui.Hwnd)
        return false
    try return WinGetMinMax("ahk_id " App.gui.Hwnd) != -1
    return false
}

ActiveInputCaptureAllowsBackground() {
    global Mapping
    if IsObject(Mapping.activeCapture)
        return Mapping.activeCapture.HasOwnProp("allowBackground") && Mapping.activeCapture.allowBackground
    return false
}

StartInputCaptureWindowMonitor() {
    SetTimer(InputCaptureWindowMonitor, 40)
}

StopInputCaptureWindowMonitorIfIdle() {
    if !IsAnyInputCaptureActive()
        SetTimer(InputCaptureWindowMonitor, 0)
}

InputCaptureWindowMonitor(*) {
    if !IsAnyInputCaptureActive() {
        SetTimer(InputCaptureWindowMonitor, 0)
        return
    }
    if !ActiveInputCaptureAllowsBackground() && !IsAppWindowCaptureEligible()
        CancelInputCapturesForWindowChange()
}

CancelInputCapturesForWindowChange(*) {
    if MappingIsCaptureActive()
        FinishCaptureOrCancel()
    SetTimer(InputCaptureWindowMonitor, 0)
}

NotifyBackendError(message) {
    global App
    if IsObject(App.gui)
        try App.gui.ExecuteScriptAsync("window.app&&window.app.backendError(" JsonQuote(message) ");")
}

MinimizeApp() {
    global App
    CancelInputCapturesForWindowChange()
    App.gui.Minimize()
}

CloseApp(*) {
    global App
    if App.languageSelected
        HideApp()
    else
        ExitApp()
}

HideApp(*) {
    global App
    CancelInputCapturesForWindowChange()
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

GetAppWorkArea(&left, &top, &right, &bottom) {
    global App
    App.gui.GetPos(&x, &y, &w, &h)
    cx := x + w // 2
    cy := y + h // 2
    count := MonitorGetCount()
    Loop count {
        MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
        if cx >= left && cx < right && cy >= top && cy < bottom
            return
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
}

RestoreBaseWindowSize() {
    global App
    App.gui.GetPos(&x, &y)
    GetAppWorkArea(&left, &top, &right, &bottom)
    if y + 600 > bottom
        y := bottom - 600
    if y < top
        y := top
    App.gui.Move(x, y, 1020, 600)
}

SetVirtualKeyboardVisible(visible, panelHeight := 240) {
    global App
    if !IsObject(App.gui)
        return ResultJson(false, "")
    visible := ToBool(visible)
    panelHeight := Integer(panelHeight)
    if panelHeight < 120
        panelHeight := 240
    if !visible {
        RestoreBaseWindowSize()
        return ResultJson(true, "", ',"mode":"hidden"')
    }

    GetAppWorkArea(&left, &top, &right, &bottom)
    neededHeight := 600 + panelHeight
    if (bottom - top) < neededHeight {
        RestoreBaseWindowSize()
        return ResultJson(true, "", ',"mode":"floating"')
    }

    App.gui.GetPos(&x, &y)
    newY := y
    if y + neededHeight > bottom
        newY := bottom - neededHeight
    if newY < top
        newY := top
    if x < left
        x := left
    if x + 1020 > right
        x := Max(left, right - 1020)
    try App.gui.Move(x, newY, 1020, neededHeight)
    catch {
        RestoreBaseWindowSize()
        return ResultJson(true, "", ',"mode":"floating"')
    }
    return ResultJson(true, "", ',"mode":"docked"')
}

ExitFromTray(*) {
    ExitApp()
}
