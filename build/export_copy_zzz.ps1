# 导出辅助：把 zzztoj worker 复制到导出目录（<exe 目录>/zzztoj/zzztoj_worker.exe）
# 用法: pwsh build/export_copy_zzz.ps1 -ExportDir "<导出输出目录>"
param([string]$ExportDir = "")
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ExportDir)) { throw "用法: export_copy_zzz.ps1 -ExportDir <导出目录>" }
$src = Join-Path $PSScriptRoot "..\zzztoj\worker\zzztoj_worker.exe"
if (-not (Test-Path $src)) { throw "未找到 $src（请先运行 zzztoj/build_worker.ps1 构建 worker）" }
$dst = Join-Path $ExportDir "zzztoj"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Force $src (Join-Path $dst "zzztoj_worker.exe")
Write-Host "已复制 zzztoj_worker.exe 到 $dst"