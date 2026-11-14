#Requires -Version 5.1
<#
    卸载：删开机自启 → 结束进程 → 删程序目录
    用法：powershell -ExecutionPolicy Bypass -File .\uninstall.ps1

    只删自己装的那一个目录，不碰别的东西。
#>
$ErrorActionPreference = 'SilentlyContinue'

$TargetDir = Join-Path $env:USERPROFILE '.workbuddy\keyboard-brightness'
$RunKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

Write-Host ('目标目录：' + $TargetDir)

Remove-ItemProperty -Path $RunKey -Name 'KeyboardBrightness'
Write-Host '开机自启已删除'

Get-Process AutoHotkey64 | Stop-Process -Force
Start-Sleep -Milliseconds 600
Write-Host '进程已结束'

if (Test-Path $TargetDir) {
    Remove-Item -LiteralPath $TargetDir -Recurse -Force
    Write-Host '程序目录已删除'
}

Write-Host ''
Write-Host '卸载完成。键盘的「停止」「上一曲」恢复成原来的多媒体功能。'
