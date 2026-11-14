# keyboard-brightness

把外接键盘上那两个用不上的多媒体键，改成屏幕亮度调节。按下去弹的是 **Windows 自己的亮度条**，不是自己画的。

## 为什么需要它

笔记本的屏幕亮度本来靠 Fn 组合键调。换了外接键盘之后，键盘上没有亮度键，这个功能就没了。

有人第一反应是「刷固件改键」。这条路走不通。这类几十块钱的键盘用的是掩膜在芯片里的公版主控（我这把是 China Resource Semico 的 `1A2C:40E2`），没有固件升级口、没有厂商驱动、也不支持 QMK/VIA。想改等于换主控。

但根本不用动固件。**Fn 键根本不进操作系统**——你按 Fn+F5，是键盘芯片自己把它翻译成一个标准「停止播放」信号发给 Windows，系统从来不知道你按了 Fn。所以只要在系统这一层把这个信号截下来换成调亮度，效果跟原生亮度键完全一样。

## 它做了什么

1. 监听键盘发出的「停止」（`VK 0xB2`）和「上一曲」（`VK 0xB1`）两个标准多媒体键，按一下亮度变化 5 点
2. 通过 WMI 的 `WmiSetBrightness` 真正改背光
3. 调 Windows Shell 里那个未公开的 Flyout 控制器，让系统自己弹出亮度条

第 3 步是这套东西里最有意思的部分，详见下面。

## 装

```powershell
git clone https://github.com/Foreverwonder/keyboard-brightness.git
cd keyboard-brightness
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` 会做四件事：下载 AutoHotkey v2 便携版（只有 1.2MB，免安装）、把脚本放到 `%USERPROFILE%\.workbuddy\keyboard-brightness`、写一条用户级开机自启（不需要管理员）、立刻启动。

装完按一下键盘上的「停止」键，亮度应该降 5 点，屏幕底部弹出系统亮度条。

## 配置

打开 `brightness.ahk`，顶部三行就是要改的东西。

```ahk
STEP      := 5                        ; 每次调几个点
TARGET_ID := "VID_1A2C&PID_40E2"      ; 只认这颗键盘的硬件 ID
LOG_MAX   := 102400                   ; 日志上限 100 KB
```

`STEP` 改成 3 或 2 会更细腻。`TARGET_ID` 是绑定键盘用的——只在这颗键盘插着的时候热键才生效，拔掉自动停用、插回自动恢复，不会干扰笔记本自带键盘或别的键盘。

查自己键盘的 ID：

```powershell
Get-CimInstance Win32_PnPEntity | Where-Object { $_.DeviceID -like '*VID_*PID_*' } |
    Select-Object Name, DeviceID
```

找到键盘那一项，取 `VID_xxxx&PID_xxxx` 这一段填进去。

改完要重启进程才生效：结束 `AutoHotkey64.exe`，再双击 `start.bat`。

## 那个亮度条是怎么来的

Windows 从来没公开过「显示亮度 OSD」的 API。第三方亮度工具（Twinkle Tray、Monitorian 之类）基本都是自己画一条。

但系统内部其实有接口。Shell 里有个未公开的浮层控制器，调用链是这样的：

1. `CoCreateInstance` 创建 ImmersiveShell，CLSID `{C2F03A33-21F5-47FA-B4BB-156362A2F239}`
2. `QueryInterface` 到 `IServiceProvider` `{6D5140C1-7436-11CE-8034-00AA006009FA}`
3. `IServiceProvider::QueryService` 取 `{41f9d2fb-7834-4ab6-8b1b-73e74064b465}`，得到 FlyoutController
4. 调它的 `ShowFlyout(3, 0)`，`3` 是亮度、`0` 是音量、`1` 是飞行模式

返回 `S_OK` 之后，系统自己会把那条「太阳图标 + 蓝色滑块」弹出来，位置、动画、深浅色主题、DPI 缩放全部原生，一行界面代码都不用写。

两个坑值得记下来。直接 `QueryInterface` 到 Flyout 接口会返回 `E_NOINTERFACE`，必须先拿到 `IServiceProvider` 再 `QueryService`。另外 AutoHotkey v2 的 `ComObject()` / `ComObjQuery()` 拿不到这个接口，必须纯 `DllCall` 手写 vtable 调用。脚本里的 `ShowBrightnessOSD()` 就是能干活的完整版本，直接抄。

接口失效时（Windows 大版本更新、资源管理器重启）脚本只记一行日志，亮度照调，不弹提示条，不崩不卡。界面是锦上添花，调亮度才是本体。

## 常见问题

**按了没反应。** 先看同目录的 `bright.log`。有「键盘在位 → 映射启用」说明脚本活着、设备认到了，问题在键码；连这一行都没有说明脚本没启动；有「键盘不在 → 映射停用」说明 `TARGET_ID` 对不上。

**日志是乱码。** 脚本写的是 UTF-8，PowerShell 5.1 的 `Get-Content` 默认按 ANSI 读会花屏。加 `-Encoding UTF8`，或者用编辑器打开。

**亮度变了但没弹条。** OSD 接口失效了，功能正常，只是少了视觉反馈。

**想确认自己的键盘发的是什么键。** 写个 AutoHotkey 的 `InputHook("L0 I0")` 探测，把 `{All}` 的 `N` 选项打开，`OnKeyDown` 里记 `vk` 和 `sc`。跑之前先让程序自己发一个已知键验证探测链路通不通，否则分不清「没按」和「探测瞎了」。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

删注册表自启项、结束进程、删掉程序目录，三步干净。

手动作也行：注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 里删掉 `KeyboardBrightness`，结束 `AutoHotkey64.exe`，删目录。

## 已知限制

只对笔记本内屏有效。WMI 那套亮度接口管的是面板背光，外接显示器走的是 DDC/CI，是另一条路，这个脚本不管。

只测过 Windows 11（3072×1920 / 200% 缩放）。Windows 10 应该也能跑，但亮度 OSD 那个内部接口在旧版本上行为可能不一样。

## 踩过的坑

1. **AutoHotkey 变量不能叫 `LOG`**。`Log` 是内置数学函数，赋值直接语法错误，脚本一行都不执行，进程挂在错误弹窗上，从外面看特别像被安全软件杀了。
2. **`SetWindowRgn` 做圆角会让 Text 控件不绘字**。试过自己画圆角胶囊，窗口出来是个空框，隔离测试确认是 region 的锅，透明没问题。最后改用系统 OSD，这个问题自然消失了。
3. **`FileDelete` 删不存在的文件会抛异常**，必须先 `if FileExist`。
4. **一些流传很广的 gist 用 `FindWindow("NativeHWNDHost")` + `PostMessage(WM_SHELLHOOK, 0x38)` 弹亮度条**，在我这台机器上 `FindWindow` 直接返回 0，不可靠。走上面那条 COM 路子更稳。
