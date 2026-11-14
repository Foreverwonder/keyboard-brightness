#Requires -Version 5.1
<#
    一键安装：下载 AutoHotkey v2 便携版 → 部署脚本 → 写开机自启 → 立即启动
    用法：powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
$ErrorActionPreference = 'Stop'

$TargetDir = Join-Path $env:USERPROFILE '.workbuddy\keyboard-brightness'
$RunKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$ExePath   = Join-Path $TargetDir 'AutoHotkey64.exe'
$ScriptPath = Join-Path $TargetDir 'brightness.ahk'

$null = New-Item -ItemType Directory -Force -Path $TargetDir

# ---------- 1. AutoHotkey 引擎 ----------
if (-not (Test-Path $ExePath)) {
    Write-Host '下载 AutoHotkey v2 便携版 ...'
    $zip = Join-Path $env:TEMP 'ahk-v2.zip'
    if (Test-Path $zip) { Remove-Item $zip -Force }

    # Windows 自带的 curl，--ssl-no-revoke 绕过部分网络环境下证书吊销检查失败的问题
    & "$env:SystemRoot\System32\curl.exe" -sL --ssl-no-revoke --max-time 180 -o $zip `
        'https://www.autohotkey.com/download/ahk-v2.zip'

    if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 100000) {
        throw '下载失败。可以手动从 https://www.autohotkey.com/download/ahk-v2.zip 下载，解压后把 AutoHotkey64.exe 放到本目录再重跑。'
    }

    $tmp = Join-Path $env:TEMP ('ahk_' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $found = Get-ChildItem -Path $tmp -Recurse -Filter 'AutoHotkey64.exe' | Select-Object -First 1
    if (-not $found) { throw '压缩包里没找到 AutoHotkey64.exe' }
    Copy-Item $found.FullName $ExePath -Force
    Remove-Item $tmp -Recurse -Force
    Remove-Item $zip -Force
    Write-Host '  引擎就位'
}
else {
    Write-Host '引擎已存在，跳过下载'
}

# ---------- 2. 主脚本 ----------
Copy-Item (Join-Path $PSScriptRoot 'brightness.ahk') $ScriptPath -Force
Write-Host '脚本已部署'

# ---------- 3. 开机自启（用户级，不需要管理员） ----------
$cmdLine = '"' + $ExePath + '" "' + $ScriptPath + '"'
Set-ItemProperty -Path $RunKey -Name 'KeyboardBrightness' -Value $cmdLine -Type String
Write-Host '开机自启已写入'

# ---------- 4. 立刻启动 ----------
# 只结束跑着本脚本的那个进程。别写成 Get-Process AutoHotkey64，那会把机器上
# 所有 AutoHotkey 脚本一起带走——别人的东西不该被我们碰。
Get-CimInstance Win32_Process -Filter "Name = 'AutoHotkey64.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*brightness.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 600
Start-Process -FilePath $ExePath -ArgumentList ('"' + $ScriptPath + '"') -WorkingDirectory $TargetDir

Write-Host ''
Write-Host ('装好了：' + $TargetDir)
Write-Host '按一下键盘上的「停止」键，亮度应该降 5 点并弹出系统亮度条。'
Write-Host '没反应就看同目录的 bright.log，第一行会告诉你键盘认到没有。'
