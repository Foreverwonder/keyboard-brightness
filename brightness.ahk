#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================================
;  键盘亮度调节  v3.1
;
;  作用：把键盘上任意两个键变成「屏幕变暗 / 变亮」，
;        并按 Windows 原生样式弹出亮度条。
;
;  这个文件是程序本体，不要改它。
;  想换按键、改步长、改设置 —— 全部在 配置.ini 里改。
; ============================================================================

APP_NAME := "键盘亮度调节"
APP_VER  := "3.1"
BASE_DIR := A_ScriptDir
CFG_FILE := BASE_DIR "\配置.ini"
LOG_FILE := BASE_DIR "\bright.log"
LOG_MAX  := 102400          ; 日志超过 100KB 就清空重来

; 兜底必须抢在所有初始化之前装好：配置读崩了也要只写日志，不弹框。
OnError(QuietError)

global ALIAS := Map(
    "MediaStop",       0xB2,
    "MediaPrev",       0xB1,
    "MediaNext",       0xB0,
    "MediaPlayPause",  0xB3,
    "VolumeUp",        0xAF,
    "VolumeDown",      0xAE,
    "VolumeMute",      0xAD,
    "BrowserBack",     0xA6,
    "BrowserForward",  0xA7,
    "BrowserRefresh",  0xA8,
    "BrowserHome",     0xAC
)

global CFG          := LoadConfig()
global HOTKEYS      := []           ; 已注册的热键表达式
global MAPPING_ON   := ""
global CAPTURED_VK  := 0
global LAST_TICK    := 0

A_IconTip := APP_NAME "  v" APP_VER

; ------------------------------- 启动 ------------------------------------
LearnMissingKeys()                  ; 配置里写了 ? 就先抓键
RegisterMapping()
SyncStartup(CFG.Autostart)
RefreshDeviceState()
OnMessage(0x0219, OnDeviceChange)   ; WM_DEVICECHANGE：插拔键盘时重新判断
Log("启动  v" APP_VER "   变暗=" CFG.Dim "   变亮=" CFG.Bright "   步长=" CFG.Step)

; ------------------------------- 配置 ------------------------------------
; 不用系统自带的 IniRead：它按系统 ANSI 编码读，配置文件里的中文键名会读不出来。
; 这里自己按 UTF-8 解析，读写都统一。
ReadCfgText() {
    global CFG_FILE
    try {
        txt := FileRead(CFG_FILE, "UTF-8")
        ; 有人会用老编辑器把文件存成 ANSI(GBK)，中文键名随即变乱码、整份配置静默失效。
        ; 这时按 GBK 再读一遍——不算修复，只为了不让「改了没反应」这种事无声发生。
        if (!InStr(txt, "[按键]")) {
            alt := FileRead(CFG_FILE, "CP936")
            if (InStr(alt, "[按键]"))
                return alt
        }
        return txt
    }
    return ""
}

; 从配置文本里取值：先找 [段名]，再找 键=值
GetIni(section, key, def, text) {
    cur := ""
    for line in StrSplit(text, "`n", "`r") {
        t := Trim(line)
        if (t = "" || SubStr(t, 1, 1) = ";" || SubStr(t, 1, 1) = "#")
            continue
        if (SubStr(t, 1, 1) = "[" && SubStr(t, -1) = "]") {
            cur := Trim(t, "[]")
            continue
        }
        if (cur != section)
            continue
        eq := InStr(t, "=")
        if (!eq)
            continue
        if (Trim(SubStr(t, 1, eq - 1)) = key)
            return Trim(SubStr(t, eq + 1))
    }
    return def
}

; 把某个键的值写回配置文件，其余内容原样保留
SetIniValue(key, value, text) {
    return RegExReplace(text, "m)^[ \t]*" key "[ \t]*=.*$", key "=" value)
}

SaveCfgText(text) {
    global CFG_FILE
    try {
        f := FileOpen(CFG_FILE, "w", "UTF-8-RAW")
        f.Write(text)
        f.Close()
    }
}

LoadConfig() {
    global CFG_FILE
    txt := ReadCfgText()
    c := {}
    c.Dim       := GetIni("按键", "变暗", "MediaStop", txt)
    c.Bright    := GetIni("按键", "变亮", "MediaPrev", txt)
    ; 步长是人手填的，填成「五」或者留空都有可能。先验再转，别让它把启动搞崩。
    sStep       := GetIni("亮度", "步长", "5", txt)
    c.Step      := IsInteger(sStep) ? Integer(sStep) : 5
    if (c.Step < 1 || c.Step > 50)
        c.Step := 5
    c.DevID     := GetIni("设备", "键盘ID", "", txt)
    c.Autostart := GetIni("其他", "开机自启", "否", txt) = "是"
    c.DoLog     := GetIni("其他", "记日志", "是", txt) = "是"
    return c
}

; 把配置里的键名翻译成 AutoHotkey 的热键写法
KeyExpr(name) {
    global ALIAS
    if (name = "")
        return ""
    if (ALIAS.Has(name))
        return "*vk" Format("{:02X}", ALIAS[name])
    return name                     ; 其余交给 AutoHotkey 自己的语法
}

; 反查：虚拟键码 -> 写回配置用的名字
VkToName(vk) {
    global ALIAS
    for k, v in ALIAS
        if (v = vk)
            return k
    if (vk >= 0x70 && vk <= 0x87)   ; F1 - F24
        return "F" (vk - 0x6F)
    if ((vk >= 0x30 && vk <= 0x39) || (vk >= 0x41 && vk <= 0x5A))
        return Chr(vk)
    return Format("vk{:02X}", vk)   ; 兜底：AutoHotkey 认这种写法
}

; ----------------------------- 按键学习 ----------------------------------
LearnMissingKeys() {
    global CFG
    if (CFG.Dim = "?") {
        vk := WaitForKey("现在设置「变暗」键")
        if (vk) {
            CFG.Dim := VkToName(vk)
            txt := SetIniValue("变暗", CFG.Dim, ReadCfgText())
            SaveCfgText(txt)
            Log("学习：变暗 = " CFG.Dim)
        }
    }
    if (CFG.Bright = "?") {
        vk := WaitForKey("现在设置「变亮」键")
        if (vk) {
            CFG.Bright := VkToName(vk)
            txt := SetIniValue("变亮", CFG.Bright, ReadCfgText())
            SaveCfgText(txt)
            Log("学习：变亮 = " CFG.Bright)
        }
    }
}

WaitForKey(title) {
    global CAPTURED_VK
    CAPTURED_VK := 0
    Log("等待按键：" title)
    SoundBeep(900, 120)
    Sleep(200)
    SoundBeep(900, 120)
    ToolTip(title "：请按一下键盘上想用的那个键（10 秒内）", 200, 120)
    hook := InputHook("L0 I0 T10")
    hook.KeyOpt("{All}", "N")
    hook.OnKeyDown := OnCaptureKey
    hook.Start()
    hook.Wait()
    try hook.Stop()
    ToolTip()
    return CAPTURED_VK
}

OnCaptureKey(hook, vk, sc) {
    global CAPTURED_VK
    ; 修饰键单独按下不算，等真正的功能键
    if (vk = 0x10 || vk = 0x11 || vk = 0x12 || vk = 0x5B || vk = 0x5C
        || vk = 0xA0 || vk = 0xA1 || vk = 0xA2 || vk = 0xA3 || vk = 0xA4 || vk = 0xA5)
        return
    CAPTURED_VK := vk
    hook.Stop()
}

; ----------------------------- 热键注册 ----------------------------------
RegisterMapping() {
    global CFG, HOTKEYS
    HOTKEYS := []
    pairs := [["dim", CFG.Dim], ["bright", CFG.Bright]]
    seen := Map()
    for p in pairs {
        expr := KeyExpr(p[2])
        if (expr = "") {
            Log("键名看不懂，跳过：" p[2])
            continue
        }
        ; 两个动作填成同一个键的话，后注册的会把前一个悄悄顶掉，
        ; 表现是「变暗失灵」而没有任何报错。当场记一笔，别让人去猜。
        if (seen.Has(StrUpper(expr))) {
            Log("两个动作填了同一个键（" p[2] "），只保留第一个")
            continue
        }
        seen[StrUpper(expr)] := true

        delta := (p[1] = "dim") ? -CFG.Step : CFG.Step
        try {
            Hotkey(expr, BrightnessStep.Bind(delta), "Off")
            HOTKEYS.Push(expr)
        } catch as e {
            Log("注册失败 " expr "：" e.Message)
        }
    }
}

RefreshDeviceState() {
    global MAPPING_ON, HOTKEYS
    present := IsKeyboardPresent()
    if (present = MAPPING_ON)
        return
    MAPPING_ON := present
    for expr in HOTKEYS {
        try Hotkey(expr, present ? "On" : "Off")
    }
    Log(present ? "键盘在位 → 映射启用" : "键盘不在 → 映射停用")
}

IsKeyboardPresent() {
    global CFG
    if (CFG.DevID = "")
        return true                 ; 没指定键盘 = 任何键盘都生效
    try {
        svc := ComObjGet("winmgmts:\\.\root\cimv2")
        q := "SELECT DeviceID FROM Win32_PnPEntity WHERE DeviceID LIKE '%" CFG.DevID "%'"
        for item in svc.ExecQuery(q)
            return true
        return false
    } catch {
        return true                 ; 查询失败不等于没插，宁可多响应一次
    }
}

OnDeviceChange(wParam, lParam, msg, hwnd) {
    if (wParam = 0x8000 || wParam = 0x8004)
        SetTimer(RefreshDeviceState, -800)
    return 0
}

; ------------------------------- 亮度 ------------------------------------
BrightnessStep(delta, *) {
    global CFG, LAST_TICK
    ; 按住不放时系统会连续发键（F 键尤其明显），挡掉 45ms 内的连发。
    ; 人手再快也要 60ms 以上，不会误伤正常连按。
    now := A_TickCount
    if (now - LAST_TICK < 45)
        return
    LAST_TICK := now

    try {
        wmi := GetWmi()
        cur := wmi.ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness").ItemIndex(0).CurrentBrightness
        nv := cur + delta
        nv := nv > 100 ? 100 : (nv < 0 ? 0 : nv)
        if (nv = cur)
            return
        wmi.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods").ItemIndex(0).WmiSetBrightness(1, nv)
        ShowBrightnessOSD()
        Log(Format("亮度 {1} → {2}", cur, nv))
    } catch as e {
        Log("出错：" e.Message)
    }
}

GetWmi() {
    static cached := ""
    if (cached = "")
        cached := ComObjGet("winmgmts:\\.\root\wmi")
    return cached
}

; 调 Windows Shell 里那个没公开的 FlyoutController，让系统自己弹亮度条。
; 路子：ImmersiveShell → IServiceProvider::QueryService → FlyoutController
ShowBrightnessOSD() {
    static fly := 0
    static VT_SHOW := 3

    if (fly) {
        try {
            if (DllCall(NumGet(NumGet(fly, "UPtr"), VT_SHOW * A_PtrSize, "UPtr"),
                        "Ptr", fly, "Int", 3, "UInt", 0, "Int") = 0)
                return true
        }
        fly := 0
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
        Log("OSD 调用失败：" e.Message)
        return false
    }
}

GuidBuf(s) {
    b := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", s, "Ptr", b)
    return b
}

; ----------------------------- 开机自启 ----------------------------------
; 不用 RegWrite：这个版本的引擎对它的参数校验有毛病，写不进去。
; 改用 WMI 的注册表接口，行为稳定，而且不用起子进程。
SyncStartup(want) {
    global BASE_DIR
    sub  := "Software\Microsoft\Windows\CurrentVersion\Run"
    name := "KeyboardBrightness"
    exe  := BASE_DIR "\" RegExReplace(A_ScriptName, "\.ahk$", ".exe")
    if (!FileExist(exe))
        exe := A_AhkPath
    cmd := '"' exe '"'

    try {
        reg := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    } catch {
        return
    }
    cur := ""
    try reg.GetStringValue(-2147483647, sub, name, &cur)

    if (want && cur != cmd) {
        if (reg.SetStringValue(-2147483647, sub, name, cmd) = 0)
            Log("已设为开机自启")
    } else if (!want && cur != "") {
        if (reg.DeleteValue(-2147483647, sub, name) = 0)
            Log("已取消开机自启")
    }
}

; ------------------------------- 日志 ------------------------------------
QuietError(err, mode) {
    Log("内部错误：" err.Message "（" err.File " 第 " err.Line " 行）")
    return true                     ; true = 已处理，不再弹窗
}

Log(text) {
    global LOG_FILE, LOG_MAX, CFG
    ; 这个函数在配置还没读出来的时候就会被调用（启动期出错），自己得能扛住。
    try {
        if (IsSet(CFG) && !CFG.DoLog)
            return
        if (FileExist(LOG_FILE) && FileGetSize(LOG_FILE) > LOG_MAX)
            FileDelete(LOG_FILE)
        FileAppend(FormatTime(, "MM-dd HH:mm:ss") "  " text "`n", LOG_FILE, "UTF-8")
    }
}
