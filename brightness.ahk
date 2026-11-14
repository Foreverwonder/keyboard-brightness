#Requires AutoHotkey v2.0
#SingleInstance Force
; === 外接键盘 F5 / F6（原「停止」「上一曲」）→ 屏幕亮度 -5 / +5
;
; 三条设计约束：
;   1. 只对这颗键盘生效。拔掉自动停用，插回自动恢复，不干扰其他键盘。
;   2. 不联网、不读外部输入、不执行外部命令。攻击面就是一个 WMI 调用。
;   3. 提示条直接借用 Windows 自己的亮度 OSD（系统 Shell 的 Flyout），
;      动画、位置、主题全部原生，脚本本身不画任何界面。
; ==========================================================================

; ------------------------------- 配置 ------------------------------------
STEP      := 5                        ; 每次调几个点（音量键是 2，亮度 5 比较跟手）
TARGET_ID := "VID_1A2C&PID_40E2"      ; 只认这颗键盘的硬件 ID
LOGPATH   := A_ScriptDir "\bright.log"
LOG_MAX   := 102400                   ; 日志上限 100 KB

; ------------------------------- 启动 ------------------------------------
global HOTKEYS_ON := ""
RefreshDeviceState()
OnMessage(0x0219, OnDeviceChange)     ; WM_DEVICECHANGE：插拔时重新判断

; ------------------------------- 设备态 ----------------------------------
OnDeviceChange(wParam, lParam, msg, hwnd) {
    ; 0x8000 = 设备接入，0x8004 = 设备移除
    if (wParam = 0x8000 || wParam = 0x8004)
        SetTimer(RefreshDeviceState, -800)   ; 等系统枚举完再查
    return 0
}

RefreshDeviceState() {
    present := IsKeyboardPresent()
    EnableHotkeys(present)
    LogLine(present ? "键盘在位 → 映射启用" : "键盘不在 → 映射停用")
}

EnableHotkeys(on) {
    global HOTKEYS_ON, STEP
    if (on = HOTKEYS_ON)
        return
    HOTKEYS_ON := on
    try {
        if (on) {
            Hotkey("*vkB2", BrightnessStep.Bind(-STEP))
            Hotkey("*vkB1", BrightnessStep.Bind(STEP))
        } else {
            Hotkey("*vkB2", "Off")
            Hotkey("*vkB1", "Off")
        }
    }
}

IsKeyboardPresent() {
    global TARGET_ID
    try {
        svc := ComObjGet("winmgmts:\\.\root\cimv2")
        q := "SELECT DeviceID FROM Win32_PnPEntity WHERE DeviceID LIKE '%" TARGET_ID "%'"
        for item in svc.ExecQuery(q)
            return true
        return false
    } catch {
        return true          ; 查不到不等于没插，宁可多响应一次也不误关
    }
}

; ------------------------------- 亮度 ------------------------------------
BrightnessStep(delta, *) {
    try {
        wmi := GetWmi()
        cur := wmi.ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness").ItemIndex(0).CurrentBrightness
        nv := cur + delta
        nv := nv > 100 ? 100 : (nv < 0 ? 0 : nv)
        if (nv = cur)
            return           ; 已经到头了，不做无意义的 WMI 调用
        wmi.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods").ItemIndex(0).WmiSetBrightness(1, nv)
        ShowBrightnessOSD()
        LogLine(Format("亮度 {1} → {2}", cur, nv))
    } catch as e {
        LogLine("出错: " e.Message)
    }
}

GetWmi() {
    static cached := ""
    if (cached = "")
        cached := ComObjGet("winmgmts:\\.\root\wmi")
    return cached
}

; ------------------------- Windows 原生亮度 OSD --------------------------
; Shell 里有个没公开的 FlyoutController，调它的 ShowFlyout(3) 就能让系统
; 自己弹出「太阳图标 + 滑块」的亮度条，动画、位置、深浅色主题全部原生。
; 拿接口的路子：ImmersiveShell → IServiceProvider::QueryService → FlyoutController
ShowBrightnessOSD() {
    static fly := 0
    static VT_SHOW := 3

    if (fly) {
        try {
            if (DllCall(NumGet(NumGet(fly, "UPtr"), VT_SHOW * A_PtrSize, "UPtr"),
                        "Ptr", fly, "Int", 3, "UInt", 0, "Int") = 0)
                return true
        }
        fly := 0                       ; 失效了（比如资源管理器重启过），重建
    }

    try {
        DllCall("ole32\CoInitialize", "Ptr", 0)
        clsid  := GuidBuf("{C2F03A33-21F5-47FA-B4BB-156362A2F239}")
        iidUnk := GuidBuf("{00000000-0000-0000-C000-000000000046}")
        iidSP  := GuidBuf("{6D5140C1-7436-11CE-8034-00AA006009FA}")
        iidFly := GuidBuf("{41f9d2fb-7834-4ab6-8b1b-73e74064b465}")

        p := 0
        if (DllCall("ole32\CoCreateInstance", "Ptr", clsid, "Ptr", 0, "UInt", 0x17,
                    "Ptr", iidUnk, "Ptr*", &p, "Int") != 0)
            return false
        sp := 0
        if (DllCall(NumGet(NumGet(p, "UPtr"), 0, "UPtr"),
                    "Ptr", p, "Ptr", iidSP, "Ptr*", &sp, "Int") != 0)
            return false
        f := 0
        if (DllCall(NumGet(NumGet(sp, "UPtr"), 3 * A_PtrSize, "UPtr"),
                    "Ptr", sp, "Ptr", iidFly, "Ptr", iidFly, "Ptr*", &f, "Int") != 0)
            return false

        fly := f
        return DllCall(NumGet(NumGet(fly, "UPtr"), VT_SHOW * A_PtrSize, "UPtr"),
                       "Ptr", fly, "Int", 3, "UInt", 0, "Int") = 0
    } catch as e {
        LogLine("OSD 调用失败: " e.Message)
        return false
    }
}

GuidBuf(s) {
    b := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", s, "Ptr", b)
    return b
}

; ------------------------------- 日志 ------------------------------------
LogLine(text) {
    global LOGPATH, LOG_MAX
    try {
        if (FileExist(LOGPATH) && FileGetSize(LOGPATH) > LOG_MAX)
            FileDelete(LOGPATH)
        FileAppend(FormatTime(, "MM-dd HH:mm:ss") "  " text "`n", LOGPATH)
    }
}
