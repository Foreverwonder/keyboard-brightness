#Requires -Version 5.1
<#
    一键安装：下载 AutoHotkey v2 引擎 → 部署到 %LOCALAPPDATA%\键盘亮度 → 写开机自启 → 启动
    用法：双击 安装.bat
    也可以命令行跑：powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
$ErrorActionPreference = 'Stop'

$TargetDir  = Join-Path $env:LOCALAPPDATA '键盘亮度'
$ExePath    = Join-Path $TargetDir '键盘亮度.exe'
$ScriptPath = Join-Path $TargetDir '键盘亮度.ahk'
$ConfigPath = Join-Path $TargetDir '配置.ini'
$RunKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

Write-Host ''
Write-Host '键盘亮度调节 —— 安装'
Write-Host ('目标目录：' + $TargetDir)
Write-Host ''

$null = New-Item -ItemType Directory -Force -Path $TargetDir

# ---------- 1. 引擎 ----------
# 官方发布的 AutoHotkey64.exe 原样复制、只改名，一个字节都不改。
# 为什么不用 Ahk2Exe 编译成独立 exe，见 README。
if (-not (Test-Path $ExePath)) {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'AutoHotkey\v2\AutoHotkey64.exe')
        (Join-Path $PSScriptRoot 'AutoHotkey64.exe')
    ) | Where-Object { $_ -and (Test-Path $_) }

    $local = $candidates | Select-Object -First 1

    if ($local) {
        Copy-Item $local $ExePath -Force
        Write-Host '  引擎：用本机已装的 AutoHotkey'
    }
    else {
        Write-Host '  引擎：正在下载 AutoHotkey v2（约 4MB）...'
        $zip = Join-Path $env:TEMP 'ahk-v2.zip'
        if (Test-Path $zip) { Remove-Item $zip -Force }

        # 系统自带的 curl。--ssl-no-revoke 绕过部分网络环境下证书吊销检查失败的问题。
        & "$env:SystemRoot\System32\curl.exe" -sL --ssl-no-revoke --max-time 180 -o $zip `
            'https://www.autohotkey.com/download/ahk-v2.zip'

        if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 100000) {
            throw '下载失败。可以手动下载 https://www.autohotkey.com/download/ahk-v2.zip，解压后把 AutoHotkey64.exe 放到本目录，再重跑一次。'
        }

        $tmp = Join-Path $env:TEMP ('ahk_' + [guid]::NewGuid().ToString('N'))
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $found = Get-ChildItem -Path $tmp -Recurse -Filter 'AutoHotkey64.exe' | Select-Object -First 1
        if (-not $found) { throw '压缩包里没找到 AutoHotkey64.exe' }

        Copy-Item $found.FullName $ExePath -Force
        Remove-Item $tmp -Recurse -Force
        Remove-Item $zip -Force
        Write-Host '  引擎：已下载'
    }
}
else {
    Write-Host '  引擎：已存在，跳过'
}

# ---------- 2. 脚本 ----------
# exe 启动时会自动加载同目录下的同名 .ahk，所以文件名必须配对。
Copy-Item (Join-Path $PSScriptRoot 'brightness.ahk') $ScriptPath -Force
Write-Host '  脚本：已部署'

$readme = Join-Path $PSScriptRoot '说明.txt'
if (Test-Path $readme) { Copy-Item $readme (Join-Path $TargetDir '说明.txt') -Force }

# ---------- 3. 配置 ----------
# 已经有一份就不覆盖：升级的时候不该把用户改过的键位冲掉。
if (Test-Path $ConfigPath) {
    Write-Host '  配置：已存在，保留你的设置'
}
else {
    Copy-Item (Join-Path $PSScriptRoot 'config.ini') $ConfigPath -Force
    Write-Host '  配置：已生成 配置.ini'
}

# ---------- 4. 开机自启（用户级，不需要管理员） ----------Set-ItemProperty -Path $RunKey -Name 'KeyboardBrightness' -Value ('"' + $ExePath + '"') -Type String
Write-Host '  开机自启：已写入'

# ---------- 5. 结束旧实例，再启动 ----------
# 只杀命令行里带自己路径的那个进程。写成 Get-Process AutoHotkey64 会把机器上
# 别的 AutoHotkey 脚本一起带走——别人的东西不该被我们碰。
Get-CimInstance Win32_Process -Filter "Name = '键盘亮度.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like ('*' + $ExePath + '*') } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 600

# 有些机器上同时存在 HTTPS_PROXY 和 https_proxy 两个环境变量，PS 5.1 的
# Start-Process 在构造进程环境时会抛「已添加项」。这里兜底改用 WMI 起进程。
try {
    Start-Process -FilePath $ExePath -WorkingDirectory $TargetDir -ErrorAction Stop
}
catch {
    $null = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine      = '"' + $ExePath + '"'
        CurrentDirectory = $TargetDir
    }
}

Write-Host ''
Write-Host '装好了。'
Write-Host '按一下配置里指定的那两个键（默认是「停止」和「上一曲」），亮度会变，屏幕会弹系统亮度条。'
Write-Host ('没反应就看 ' + (Join-Path $TargetDir 'bright.log') + '，里面会写明白键盘认到没有。')
Write-Host ''
