; 键鼠小工具公共输入工具。这里只负责按键格式、显示和最底层的发送动作。

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
        return T("key.none")
    labels := ""
    for index, keyName in SplitCombo(value)
        labels .= (index > 1 ? " + " : "") DisplayName(keyName)
    return labels
}

DisplayName(value) {
    value := String(value)
    if value = "NONE"
        return T("key.none")

    lower := StrLower(value)
    translated := T("key." lower)
    if translated != "key." lower
        return translated
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

IsModifierKey(name) {
    name := StrLower(String(name))
    return name = "lcontrol" || name = "rcontrol" || name = "control" || name = "ctrl"
        || name = "lshift" || name = "rshift" || name = "shift"
        || name = "lalt" || name = "ralt" || name = "alt"
        || name = "lwin" || name = "rwin" || name = "win"
}

ComboArrayHasKey(keys, keyName) {
    lower := StrLower(String(keyName))
    for candidate in keys {
        if StrLower(candidate) = lower
            return true
    }
    return false
}

ComboContainsKey(combo, keyName) {
    return ComboArrayHasKey(SplitCombo(combo), keyName)
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

JsonQuote(value) {
    value := String(value)
    value := StrReplace(value, "\", "\\")
    value := StrReplace(value, '"', '\"')
    value := StrReplace(value, "`r", "\r")
    value := StrReplace(value, "`n", "\n")
    value := StrReplace(value, "`t", "\t")
    return '"' value '"'
}

ResultJson(ok, message, extra := "") {
    return '{"ok":' (ok ? "true" : "false") ',"message":' JsonQuote(message) extra "}"
}

ToBool(value) {
    value := StrLower(Trim(String(value)))
    return value = "1" || value = "true" || value = "yes" || value = "on"
}

GetInputKeyName(vk, sc) {
    keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    return keyName != "" ? keyName : GetKeyName(Format("vk{:02X}", vk))
}

MaskCapturedSystemMenuKey(keyName) {
    lower := StrLower(String(keyName))
    if lower != "lwin" && lower != "rwin" && lower != "lalt" && lower != "ralt" && lower != "alt"
        return
    ; vkE8 是无功能的菜单屏蔽键，避免 Win/Alt 弹起时激活开始菜单或窗口菜单。
    SendLevel 0
    try SendEvent("{Blind}{vkE8}")
}
