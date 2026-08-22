; 键鼠映射核心。开源版仅运行普通 Enabled 映射；Global 字段只为配置兼容而保留。

global Mapping := {
    rows: [], nextId: 1, enabled: false, suspended: false,
    activeCapture: 0, captureKeys: [], captureDown: Map(), ignoreUntilUp: Map(), captureHook: 0,
    installedSourceHotkeys: Map(), pressedKeys: Map(), pressOrder: [], activeMappings: Map(),
    suppressedKeys: Map(), vkPointerInside: false
}

MappingInitialize() {
    DevTrace("mapping load start")
    MappingLoad()
    DevTrace("mapping mouse hotkeys start")
    try MappingInstallMouseCaptureHotkeys()
    catch as err {
        DevTrace("mapping hotkey error: " err.Message)
        throw
    }
    DevTrace("mapping init done")
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

MappingStateJson() {
    global Mapping
    json := "["
    for index, row in Mapping.rows {
        if index > 1
            json .= ","
        json .= '{"id":' row.id ',"from":' JsonQuote(row.source)
            . ',"fromLabel":' JsonQuote(DisplayCombo(row.source))
            . ',"to":' JsonQuote(row.target)
            . ',"toLabel":' JsonQuote(DisplayCombo(row.target))
            . ',"enabled":' (row.enabled ? "true" : "false")
            . ',"global":' (row.globalEnabled ? "true" : "false") ',"saved":true}'
    }
    return json "]"
}

SaveMapping(id, source, target) {
    global Mapping
    id := Integer(id)
    source := NormalizeCombo(source)
    target := NormalizeCombo(target)
    if target = ""
        target := "NONE"
    if source = ""
        return ResultJson(false, T("message.mappingSourceRequired"))
    if error := MappingValidateCombo(source, false)
        return ResultJson(false, error)
    if error := MappingValidateCombo(target, true)
        return ResultJson(false, error)

    for row in Mapping.rows {
        if row.id = id
            continue
        if MappingCombosConflict(source, row.source) {
            if ComboEquals(source, row.source)
                return ResultJson(false, T("message.mappingDuplicate"))
            return ResultJson(false, T("message.mappingPrefixConflict", Map("mapping", DisplayCombo(row.source))))
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
    if !found {
        row := {id: id, source: source, target: target, enabled: false, globalEnabled: false}
        Mapping.rows.InsertAt(1, row)
        Mapping.nextId := Max(Mapping.nextId, id + 1)
    }
    MappingSave()
    MappingApply()
    return ResultJson(true, "")
}

MappingFindRow(id) {
    global Mapping
    for row in Mapping.rows {
        if row.id = Integer(id)
            return row
    }
    return 0
}

SetMappingEnabled(id, enabled) {
    row := MappingFindRow(id)
    if !IsObject(row)
        return ResultJson(false, T("message.mappingNotFound"))
    row.enabled := ToBool(enabled)
    MappingSave()
    ; 重建热键前会释放当前映射输出；取消勾选后源按键不再被注册，因此恢复原输入。
    MappingApply()
    return ResultJson(true, "", ',"enabled":' (row.enabled ? "true" : "false"))
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
    global App, Mapping
    if App.mode != "mapping" || (field != "from" && field != "to")
        return false
    if !IsAppWindowCaptureEligible() {
        MappingNotifyCancelled()
        return false
    }
    MappingCancelCapture(false)
    ; 录制期间暂停已有映射，避免录制按键触发当前规则。
    MappingDisableHotkeys()
    Mapping.suspended := true
    Mapping.activeCapture := {id: Integer(id), field: String(field), pointerInside: ToBool(pointerInside),
        allowBackground: false, virtualUsed: false}
    Mapping.captureKeys := []
    Mapping.captureDown := Map()
    Mapping.ignoreUntilUp := Map()
    if GetKeyState("LButton", "P")
        Mapping.ignoreUntilUp["lbutton"] := true

    ; I1 忽略脚本以默认 SendLevel 0 发送的菜单屏蔽键；NS 显式通知并吞掉所有物理键。
    ih := InputHook("T30 L0 I1")
    ih.VisibleText := false
    ih.VisibleNonText := false
    ih.KeyOpt("{All}", "NS")
    ih.OnKeyDown := MappingCaptureKeyDown
    ih.OnKeyUp := MappingCaptureKeyUp
    ih.OnEnd := MappingCaptureEnded
    Mapping.captureHook := ih
    ih.Start()
    StartInputCaptureWindowMonitor()
    return true
}

SetMappingCapturePointerInside(inside) {
    global Mapping
    if IsObject(Mapping.activeCapture)
        Mapping.activeCapture.pointerInside := ToBool(inside)
    return true
}

SetVirtualKeyboardPointerInside(inside) {
    global Mapping
    Mapping.vkPointerInside := ToBool(inside)
    return true
}

CancelCapture(restoreMappings := true) {
    return MappingCancelCapture(restoreMappings)
}

MappingCancelCapture(restoreMappings := true) {
    global Mapping
    SetTimer(MappingCompleteCapture, 0)
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
    StopInputCaptureWindowMonitorIfIdle()
    return true
}

MappingCaptureEnded(ih) {
    global Mapping
    if !IsObject(Mapping.activeCapture) || Mapping.captureHook != ih
        return
    FinishCaptureOrCancel()
}

MappingCaptureKeyDown(ih, vk, sc) {
    global Mapping
    if !IsObject(Mapping.activeCapture) || Mapping.captureHook != ih
        return
    if vk = 0xE8 || (Mapping.activeCapture.HasOwnProp("completionPending") && Mapping.activeCapture.completionPending)
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
        NotifyCaptureWarning(T("message.comboTooLong"))
        return
    }
    if IsProtectedMouse(keyName) && Mapping.captureKeys.Length = 0 {
        Mapping.ignoreUntilUp[lower] := true
        NotifyCaptureWarning(T("message.mouseProtectedMapping"))
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
    if vk = 0xE8
        return
    keyName := GetInputKeyName(vk, sc)
    lower := StrLower(keyName)
    ; 在系统键弹起尚未交给 Windows 时插入屏蔽键，阻止开始菜单或菜单栏响应。
    MaskCapturedSystemMenuKey(keyName)
    if Mapping.ignoreUntilUp.Has(lower) {
        Mapping.ignoreUntilUp.Delete(lower)
        return
    }
    if Mapping.captureDown.Has(lower)
        Mapping.captureDown.Delete(lower)
    if Mapping.captureKeys.Length && Mapping.captureDown.Count = 0 && MappingCaptureShouldAutoComplete()
        MappingScheduleCompleteCapture()
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
    ; 左右键作为第一个键时，仅在当前激活的录制框内部拦截；框外交还给界面。
    if IsProtectedMouse(name) {
        if Mapping.vkPointerInside
            return false
        if Mapping.captureKeys.Length = 0
            return Mapping.activeCapture.pointerInside
    }
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
    if !IsObject(Mapping.activeCapture)
        return
    if Mapping.activeCapture.HasOwnProp("completionPending") && Mapping.activeCapture.completionPending
        return
    lower := StrLower(name)
    if Mapping.ignoreUntilUp.Has(lower) || Mapping.captureDown.Has(lower) || ComboArrayHasKey(Mapping.captureKeys, name)
        return
    if Mapping.captureKeys.Length >= 3 {
        Mapping.ignoreUntilUp[lower] := true
        NotifyCaptureWarning(T("message.comboTooLong"))
        return
    }
    if IsProtectedMouse(name) && Mapping.captureKeys.Length = 0 {
        Mapping.ignoreUntilUp[lower] := true
        NotifyCaptureWarning(T("message.mouseProtectedMapping"))
        return
    }
    Mapping.captureKeys.Push(name)
    if !IsWheel(name)
        Mapping.captureDown[lower] := true
    MappingNotifyProgress()
    if IsWheel(name)
        MappingScheduleCompleteCapture()
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
    if Mapping.captureKeys.Length && Mapping.captureDown.Count = 0 && MappingCaptureShouldAutoComplete()
        MappingScheduleCompleteCapture()
}

MappingCaptureShouldAutoComplete() {
    global Mapping
    if !IsObject(Mapping.activeCapture)
        return false
    return !(Mapping.activeCapture.HasOwnProp("virtualUsed") && Mapping.activeCapture.virtualUsed)
}

MappingScheduleCompleteCapture() {
    global Mapping
    if !IsObject(Mapping.activeCapture) || !Mapping.captureKeys.Length
        return
    if Mapping.activeCapture.HasOwnProp("completionPending") && Mapping.activeCapture.completionPending
        return
    Mapping.activeCapture.completionPending := true
    ; 等当前物理弹起事件被输入钩子完整吞掉后，再停止钩子并保存录制结果。
    SetTimer(MappingCompleteCapture, -1)
}

MappingCompleteCapture() {
    global Mapping
    if !IsObject(Mapping.activeCapture) || !Mapping.captureKeys.Length
        return
    capture := Mapping.activeCapture
    combo := JoinCombo(Mapping.captureKeys)
    label := DisplayCombo(combo)
    MappingCancelCapture()
    SendCaptureToWeb(capture.id, capture.field, combo, label)
}

AppendVirtualCaptureKey(keyName) {
    global Mapping
    if !IsObject(Mapping.activeCapture)
        return ResultJson(false, T("message.virtualKeyboardNeedCapture"))
    if Mapping.activeCapture.HasOwnProp("completionPending") && Mapping.activeCapture.completionPending
        return ResultJson(false, "")
    keyName := Trim(String(keyName))
    if keyName = ""
        return ResultJson(false, "")
    lower := StrLower(keyName)
    if Mapping.ignoreUntilUp.Has(lower) || Mapping.captureDown.Has(lower) || ComboArrayHasKey(Mapping.captureKeys, keyName)
        return ResultJson(true, "", ',"virtualUsed":true,"count":' Mapping.captureKeys.Length)
    if Mapping.captureKeys.Length >= 3 {
        NotifyCaptureWarning(T("message.comboTooLong"))
        return ResultJson(false, T("message.comboTooLong"))
    }
    if IsProtectedMouse(keyName) && Mapping.captureKeys.Length = 0
        return ResultJson(false, T("message.mouseProtectedMapping"))
    Mapping.captureKeys.Push(keyName)
    Mapping.activeCapture.virtualUsed := true
    MappingNotifyProgress()
    if Mapping.captureKeys.Length >= 3 {
        MappingCompleteCapture()
        return ResultJson(true, "", ',"virtualUsed":true,"completed":true,"count":3')
    }
    return ResultJson(true, "", ',"virtualUsed":true,"completed":false,"count":' Mapping.captureKeys.Length)
}

ConfirmVirtualCapture() {
    global Mapping
    if !IsObject(Mapping.activeCapture)
        return ResultJson(false, T("message.virtualKeyboardNeedCapture"))
    if !Mapping.captureKeys.Length || !(Mapping.activeCapture.HasOwnProp("virtualUsed") && Mapping.activeCapture.virtualUsed)
        return ResultJson(false, T("message.virtualKeyboardNeedCapture"))
    MappingCompleteCapture()
    return ResultJson(true, "")
}

FinishCaptureOrCancel() {
    global Mapping
    if !IsObject(Mapping.activeCapture)
        return ResultJson(true, "", ',"finished":false')
    if Mapping.captureKeys.Length && Mapping.activeCapture.HasOwnProp("virtualUsed") && Mapping.activeCapture.virtualUsed {
        MappingCompleteCapture()
        return ResultJson(true, "", ',"finished":true')
    }
    capture := Mapping.activeCapture
    MappingCancelCapture()
    MappingNotifyCancelled(capture)
    return ResultJson(true, "", ',"finished":false')
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

MappingApply() {
    global Mapping
    MappingDisableHotkeys()
    if !Mapping.enabled || Mapping.suspended
        return
    for row in Mapping.rows {
        if !MappingRowShouldRun(row)
            continue
        row.sourceKeys := SplitCombo(row.source)
        row.targetKeys := SplitCombo(row.target)
        for keyName in row.sourceKeys
            MappingRegisterSourceHotkey(keyName)
    }
}

MappingRefreshScope() {
    global Mapping
    if !Mapping.enabled || Mapping.suspended
        return
    ids := []
    for id, row in Mapping.activeMappings {
        if !MappingRowShouldRun(row)
            ids.Push(id)
    }
    for id in ids
        MappingDeactivate(id)
    for row in Mapping.rows {
        row.sourceKeys := SplitCombo(row.source)
        row.targetKeys := SplitCombo(row.target)
        if MappingRowShouldRun(row) {
            for keyName in row.sourceKeys
                MappingRegisterSourceHotkey(keyName)
        }
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
        NotifyBackendError(T("message.mappingEnableFailed", Map("key", DisplayName(keyName))))
    }
}

MappingSourceKeyDownActive(keyName, *) {
    global Mapping
    if !Mapping.enabled || Mapping.suspended || IsAnyInputCaptureActive()
        return false
    return MappingSourceKeyCanTrigger(keyName)
}

MappingSourceKeyCanTrigger(keyName) {
    global Mapping
    lower := StrLower(keyName)
    if Mapping.pressedKeys.Has(lower)
        return true
    for row in Mapping.rows {
        if !MappingRowShouldRun(row)
            continue
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
        && !IsAnyInputCaptureActive() && Mapping.pressedKeys.Has(StrLower(keyName))
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
    if Mapping.pressedKeys.Has(lower) {
        ; 源键连发时只重复已激活映射的目标键，不再重新匹配或重复按下。
        MappingRepeatActive(keyName)
        return
    }
    Mapping.pressedKeys[lower] := keyName
    MappingPushPressOrder(keyName)
    MappingTryActivate()
}

MappingRepeatActive(keyName) {
    global Mapping
    lower := StrLower(keyName)
    for id, row in Mapping.activeMappings {
        if !row.sourceKeys.Length
            continue
        ; 只有最后一个映射前按键的连发会重复目标，前缀修饰键连发不额外触发。
        if StrLower(row.sourceKeys[row.sourceKeys.Length]) != lower
            continue
        MappingRepeatTarget(row.targetKeys)
    }
}

MappingRepeatTarget(keys) {
    if !IsObject(keys)
        return
    Loop keys.Length {
        keyName := keys[keys.Length - A_Index + 1]
        if IsWheel(keyName) || IsAnyMouseButton(keyName)
            continue
        SendPhysicalKey(keyName, "down")
        return
    }
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
        if !MappingRowShouldRun(row)
            continue
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
        return allowNone ? "" : T("message.mappingSourceEmpty")
    keys := SplitCombo(value)
    if keys.Length < 1
        return allowNone ? "" : T("message.mappingSourceEmpty")
    if keys.Length > 3
        return T("message.comboTooLong")
    if IsProtectedMouse(keys[1])
        return T("message.mouseProtectedMapping")
    if !allowNone {
        Loop keys.Length - 1 {
            if IsWheel(keys[A_Index])
                return T("message.wheelSourceLast")
        }
    }
    seen := Map()
    for keyName in keys {
        lower := StrLower(keyName)
        if seen.Has(lower)
            return T("message.comboDuplicateKey")
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
    IniWrite(1, App.mappingsFile, "Mappings", "SchemaVersion")
    IniWrite(Mapping.rows.Length, App.mappingsFile, "Mappings", "Count")
    for index, row in Mapping.rows {
        IniWrite(row.source, App.mappingsFile, "Map" index, "Source")
        IniWrite(row.target, App.mappingsFile, "Map" index, "Target")
        IniWrite(row.enabled ? 1 : 0, App.mappingsFile, "Map" index, "Enabled")
        IniWrite(row.globalEnabled ? 1 : 0, App.mappingsFile, "Map" index, "Global")
    }
}

MappingLoad() {
    global App, Mapping
    count := 0
    try count := Integer(IniRead(App.mappingsFile, "Mappings", "Count", "0"))
    catch
        count := 0
    Loop count {
        source := NormalizeCombo(IniRead(App.mappingsFile, "Map" A_Index, "Source", ""))
        target := NormalizeCombo(IniRead(App.mappingsFile, "Map" A_Index, "Target", "NONE"))
        if source != "" {
            enabled := ToBool(IniRead(App.mappingsFile, "Map" A_Index, "Enabled", "0"))
            globalEnabled := ToBool(IniRead(App.mappingsFile, "Map" A_Index, "Global", "0"))
            Mapping.rows.Push({id: Mapping.nextId++, source: source, target: target = "" ? "NONE" : target,
                enabled: enabled, globalEnabled: globalEnabled})
        }
    }
}
