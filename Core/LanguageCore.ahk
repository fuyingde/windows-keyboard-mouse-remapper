; Runtime localization shared by the native AHK layer and the WebView interface.

global LocaleCatalog := 0

LanguageInitialize() {
    global App, LocaleCatalog
    LocaleCatalog := GeneratedLocaleCatalog()
    App.locale := LocaleCatalog.defaultLocale
    App.languageSelected := false
    if !FileExist(App.languageFile)
        return
    try locale := Trim(IniRead(App.languageFile, "Language", "Locale", ""))
    catch
        return
    if LanguageIsAvailable(locale) {
        App.locale := locale
        App.languageSelected := true
    }
}

LanguageIsAvailable(locale) {
    global LocaleCatalog
    return IsObject(LocaleCatalog) && LocaleCatalog.packs.Has(String(locale))
}

T(key, replacements := 0) {
    global App, LocaleCatalog
    key := String(key)
    locale := IsObject(App) && App.HasOwnProp("locale") ? App.locale : LocaleCatalog.defaultLocale
    pack := LocaleCatalog.packs.Has(locale) ? LocaleCatalog.packs[locale] : LocaleCatalog.packs[LocaleCatalog.defaultLocale]
    fallback := LocaleCatalog.packs[LocaleCatalog.defaultLocale]
    text := pack.strings.Has(key) ? pack.strings[key]
        : fallback.strings.Has(key) ? fallback.strings[key] : key
    if IsObject(replacements) {
        for name, value in replacements
            text := StrReplace(text, "{" name "}", String(value))
    }
    return text
}

LanguageNativeName(locale := "") {
    global App, LocaleCatalog
    if locale = ""
        locale := App.locale
    return LocaleCatalog.packs.Has(locale) ? LocaleCatalog.packs[locale].nativeName : String(locale)
}

AppWindowTitle() {
    global App
    return T("app.windowTitle", Map("appName", T("app.name"), "version", App.version))
}

SetLanguage(locale) {
    global App
    locale := String(locale)
    if !LanguageIsAvailable(locale)
        return ResultJson(false, T("message.languageUnavailable"), ',"saved":false')

    MappingCancelCapture()
    wasSelected := App.languageSelected
    App.locale := locale
    App.languageSelected := true
    saved := true
    try {
        DirCreate(App.configDir)
        IniWrite(locale, App.languageFile, "Language", "Locale")
    } catch {
        saved := false
    }

    if wasSelected {
        ConfigureTray()
    } else {
        ConfigureTray()
        EnableMappingRuntime()
    }
    UpdateNativeLanguage()
    message := saved ? "" : T("message.languageSaveFailed")
    return ResultJson(true, message, ',"saved":' (saved ? "true" : "false") ',"state":' GetInitialState())
}

UpdateNativeLanguage() {
    global App
    if IsObject(App.gui) {
        try App.gui.Title := AppWindowTitle()
        try WinSetTitle(AppWindowTitle(), "ahk_id " App.gui.Hwnd)
    }
}
