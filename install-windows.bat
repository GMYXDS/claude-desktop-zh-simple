@echo off
setlocal EnableExtensions
chcp 936 >nul 2>&1

echo Claude Desktop 轻量汉化工具
echo GitHub: https://github.com/GMYXDS/claude-desktop-zh-simple
echo Gitee : https://gitee.com/GMYXDS/claude-desktop-zh-simple
echo 声明: 本工具永久免费，请勿从收费渠道购买。
echo.

set "SCRIPT=%~dp0scripts\claude-desktop-zh-simple.ps1"

if not exist "%SCRIPT%" (
  echo 未找到脚本:
  echo "%SCRIPT%"
  pause
  exit /b 1
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo 未找到 powershell.exe。
  pause
  exit /b 1
)

net session >nul 2>&1
if errorlevel 1 (
  echo 正在请求管理员权限...
  set "LAUNCH_BAT=%~f0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:LAUNCH_BAT -Verb RunAs"
  if errorlevel 1 (
    echo 请求管理员权限失败。如果你取消了 UAC，请重新运行本文件。
    pause
    exit /b 1
  )
  exit /b 0
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
pause
exit /b %EXIT_CODE%
