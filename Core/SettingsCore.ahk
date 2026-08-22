; v1.7 open-source settings. Removed-feature fields remain read/write compatible with v2.3.

SettingsInitialize() {
    global App
    DirCreate(App.configDir)
    DevTrace("settings defaults start")
    SettingsEnsureDefaults()
    DevTrace("settings load start")
    SettingsLoad()
    DevTrace("settings sync start")
    SettingsSynchronizeAutoStart()
    DevTrace("settings done")
}

SettingsEnsureDefaults() {
    global App
    sentinel := "__KEY_MOUSE_SETTING_MISSING__"
    IniWrite(1, App.settingsFile, "Settings", "SchemaVersion")
    DevTrace("default schema")
    if SettingsReadRaw("Settings", "AutoStart", sentinel) = sentinel
        IniWrite(0, App.settingsFile, "Settings", "AutoStart")
    DevTrace("default auto start")
    if SettingsReadRaw("Settings", "TrayIcon", sentinel) = sentinel
        IniWrite(1, App.settingsFile, "Settings", "TrayIcon")
    DevTrace("default tray")
    if SettingsReadRaw("Settings", "Mode", sentinel) = sentinel
        IniWrite("mapping", App.settingsFile, "Settings", "Mode")
    DevTrace("default mode")
    if SettingsReadRaw("Settings", "PressDurationMin", sentinel) = sentinel
        IniWrite(2, App.settingsFile, "Settings", "PressDurationMin")
    DevTrace("default min")
    if SettingsReadRaw("Settings", "PressDurationMax", sentinel) = sentinel
        IniWrite(5, App.settingsFile, "Settings", "PressDurationMax")
    DevTrace("default max")
    if SettingsReadRaw("Settings", "ExecutionMode", sentinel) = sentinel
        IniWrite("independent", App.settingsFile, "Settings", "ExecutionMode")
    DevTrace("default execution")
}

SettingsLoad() {
    global App
    desiredAutoStart := SettingsReadBool("Settings", "AutoStart", false)
    App.settings.autoStartDesired := desiredAutoStart
    App.settings.autoStart := desiredAutoStart
    App.settings.autoStartError := ""
    App.settings.trayIcon := SettingsReadBool("Settings", "TrayIcon", true)
    App.settings.pressDurationMin := SettingsReadPositiveInteger("Settings", "PressDurationMin", 2)
    App.settings.pressDurationMax := SettingsReadPositiveInteger("Settings", "PressDurationMax", 5)
    if App.settings.pressDurationMax < App.settings.pressDurationMin
        App.settings.pressDurationMax := App.settings.pressDurationMin
    App.settings.storedMode := StrLower(String(SettingsReadRaw("Settings", "Mode", "mapping")))
    if App.settings.storedMode != "mapping" && App.settings.storedMode != "autopress"
        App.settings.storedMode := "mapping"
    ; 开源版只显示映射，但不覆盖完整版最后使用的功能模式。
    App.mode := "mapping"
    App.settings.executionMode := StrLower(String(SettingsReadRaw("Settings", "ExecutionMode", "independent")))
    if App.settings.executionMode != "independent" && App.settings.executionMode != "global"
        App.settings.executionMode := "independent"
}

SettingsReadRaw(section, key, defaultValue) {
    global App
    try return IniRead(App.settingsFile, section, key, defaultValue)
    catch
        return defaultValue
}

SettingsReadBool(section, key, defaultValue) {
    value := Trim(String(SettingsReadRaw(section, key, defaultValue ? "1" : "0")))
    return ToBool(value)
}

SettingsReadPositiveInteger(section, key, defaultValue) {
    value := Trim(String(SettingsReadRaw(section, key, defaultValue)))
    if !RegExMatch(value, "^\d+$")
        return defaultValue
    try value := Integer(value)
    catch
        return defaultValue
    return value >= 1 ? value : defaultValue
}

StartupCommand() {
    return A_IsCompiled ? '"' A_ScriptFullPath '"' : '"' A_AhkPath '" "' A_ScriptFullPath '"'
}

SettingsRegistryValue(valueName) {
    global App
    try return Trim(String(RegRead(App.startupKey, valueName)))
    catch
        return ""
}

SettingsHasManagedStartupEntry() {
    global App
    return SettingsRegistryValue(App.startupValue) != ""
}

IsAutoStartEnabled() {
    global App
    command := SettingsRegistryValue(App.startupValue)
    return command != "" && StrLower(command) = StrLower(StartupCommand())
}

SettingsSynchronizeAutoStart() {
    global App
    desired := App.settings.autoStartDesired
    App.settings.autoStartError := ""

    ; 源码调试模式不修改用户的 Windows 启动项，正式编译版才执行系统同步。
    if !A_IsCompiled {
        App.settings.autoStart := desired
        return true
    }

    try {
        if desired {
            RegWrite StartupCommand(), "REG_SZ", App.startupKey, App.startupValue
        } else {
            try RegDelete App.startupKey, App.startupValue
        }
    } catch as err {
        App.settings.autoStartError := err.Message
    }

    App.settings.autoStart := desired ? IsAutoStartEnabled() : SettingsHasManagedStartupEntry()
    return App.settings.autoStart = desired
}

SetAutoStart(enabled) {
    global App
    enabled := ToBool(enabled)
    App.settings.autoStartDesired := enabled
    try SaveSettings()
    catch as err
        return SettingResultJson(false, App.settings.autoStart, T("message.autoStartSaveFailed"))

    if !SettingsSynchronizeAutoStart() {
        message := App.settings.autoStartError != ""
            ? T("message.autoStartChangeFailed")
            : T("message.autoStartRejected")
        return SettingResultJson(false, App.settings.autoStart, message)
    }
    return SettingResultJson(true, App.settings.autoStart, "")
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
        return SettingResultJson(false, App.settings.trayIcon, T("message.traySaveFailed"))
    }
}

SaveSettings() {
    global App
    DirCreate(App.configDir)
    IniWrite(1, App.settingsFile, "Settings", "SchemaVersion")
    IniWrite(App.settings.autoStartDesired ? 1 : 0, App.settingsFile, "Settings", "AutoStart")
    IniWrite(App.settings.trayIcon ? 1 : 0, App.settingsFile, "Settings", "TrayIcon")
    IniWrite(App.settings.storedMode, App.settingsFile, "Settings", "Mode")
    IniWrite(App.settings.pressDurationMin, App.settingsFile, "Settings", "PressDurationMin")
    IniWrite(App.settings.pressDurationMax, App.settingsFile, "Settings", "PressDurationMax")
    IniWrite(App.settings.executionMode, App.settingsFile, "Settings", "ExecutionMode")
}

SettingResultJson(ok, value, message) {
    return '{"ok":' (ok ? "true" : "false") ',"value":' (value ? "true" : "false") ',"message":' JsonQuote(message) "}"
}
