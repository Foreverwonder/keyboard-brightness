#Requires -Version 5.1
<#
    卸载：删开机自启 → 结束进程 → 删程序目录
    用法：双击 卸载.bat
    也可以命令行跑：powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
    只删自己装的那一个目录，别的东西一概不碰。
#>
$ErrorActionPreference = 'SilentlyContinue'

$TargetDir = Join-Path $env:LOCALAPPDATA '键盘亮度'
$ExePath   = Join-Path $TargetDir '键盘亮度.exe'
$RunKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

Write-Host ''
Write-Host ('目标目录：' + $TargetDir)

Remove-ItemProperty -Path $RunKey -Name 'KeyboardBrightness' -ErrorAction SilentlyContinue
Write-Host '  开机自启：已删除'

# 只结束跑着本程序的进程，机器上其它 AutoHotkey 脚本不碰
Get-CimInstance Win32_Process -Filter "Name = '键盘亮度.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*键盘亮度*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 600
Write-Host '  进程：已结束'

# 递归删除前先确认叶子目录名，防止变量被改坏时误删别的地方
if ((Test-Path $TargetDir) -and (Split-Path $TargetDir -Leaf) -eq '键盘亮度') {
    Remove-Item -LiteralPath $TargetDir -Recurse -Force
    Write-Host '  程序目录：已删除'
}
else {
    Write-Host '  程序目录：不存在，跳过'
}

Write-Host ''
Write-Host '卸载完成。那两个键恢复成原来的多媒体功能。'
Write-Host ''
