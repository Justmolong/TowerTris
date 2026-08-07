# ============================================================
# 导出辅助脚本方案A：把 ColdClear 原生文件（worker/dll）作为松散文件
# 复制到导出的 exe 同目录下，使导出后的游戏能启动 CC bot。
#
# 用法：
#   powershell -File build/export_copy_native.ps1 -ExePath "C:/path/to/TowerTetris.exe"
#   （不传 ExePath 时，自动从 export_presets.cfg 读取 Windows Desktop 的 export_path）
#
# 复制目标：<exe 所在目录>/native/coldclear_worker.exe 等（与 coldclear_bridge.gd
# 中 _resolve_native_dir() 的 exe 旁 native/ 探测逻辑一致）。
# ============================================================
param(
    [string]$ExePath = ""
)

$ErrorActionPreference = "Stop"

# --- 1. 确定 exe 路径 ---
if (-not $ExePath) {
    $cfg = Get-Content -Path (Join-Path $PSScriptRoot "..\export_presets.cfg") -Raw
    if ($cfg -match 'export_path="([^"]+)"') {
        $ExePath = $matches[1]
        # export_presets.cfg 里的路径是相对项目目录的
        $ExePath = [System.IO.Path]::GetFullPath((Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) $ExePath))
    } else {
        Write-Error "未指定 -ExePath，且无法从 export_presets.cfg 读取 export_path"
        exit 1
    }
}

$exeDir = Split-Path $ExePath -Parent
if (-not (Test-Path $ExePath)) {
    Write-Warning "exe 不存在（可能尚未导出）：$ExePath"
    New-Item -ItemType Directory -Force -Path $exeDir | Out-Null
}

# --- 2. 源 native 目录 ---
$srcNative = Join-Path $PSScriptRoot "..\rust\cold_clear_engine\native"
if (-not (Test-Path $srcNative)) {
    Write-Error "源 native 目录不存在：$srcNative"
    exit 1
}

# --- 3. 复制到 exe 旁 native/ ---
$dstNative = Join-Path $exeDir "native"
New-Item -ItemType Directory -Force -Path $dstNative | Out-Null
Copy-Item -Path (Join-Path $srcNative "*") -Destination $dstNative -Recurse -Force

Write-Host "已把 ColdClear 原生文件复制到：$dstNative"
Get-ChildItem -Path $dstNative | ForEach-Object { Write-Host ("  - " + $_.Name) }
Write-Host "完成。导出的 exe 现在可以使用 CC bot。"