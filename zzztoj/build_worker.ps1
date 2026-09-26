# Build the zzztoj worker (the bot process used by this game).
# Usage (from any directory):  powershell -File zzztoj\build_worker.ps1
# Needs MinGW g++ on PATH, or at the fallback path below, or pass -Gxx <path>.
# For an MSVC/CMake build, see the io_dll target in CMakeLists.txt (same sources).
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less files as ANSI,
#       and non-ASCII text then breaks parsing.
param(
    [string]$Gxx = ""
)
$ErrorActionPreference = "Stop"

# All relative paths below are relative to zzztoj/, so always switch to the script's own
# directory first: running `powershell -File zzztoj\build_worker.ps1` from the project root
# would otherwise fail to find src/.
Set-Location $PSScriptRoot

$srcs = @(
    "src/zzztoj_worker.cpp",
    "src/ai_zzz.cpp",
    "src/tetris_core.cpp",
    "src/rule_asc.cpp",      # ASC wall-kick rule used by this game
    "src/rule_srs.cpp",      # node geometry / rotation templates
    "src/search_amini.cpp",  # search with T / AllSpin / Mini handling
    "src/integer_utils.cpp",
    "src/random.cpp"
)

$candidates = @()
if ($Gxx -ne "") { $candidates += $Gxx }
$candidates += @("g++", "E:\mingw64\mingw64\bin\g++.exe")
$compiler = $null
foreach ($c in $candidates) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $compiler = $c; break }
}
if ($null -eq $compiler) {
    throw ("g++ not found. Tried: " + ($candidates -join ", ") + ". Install MinGW-w64 or pass -Gxx <path>.")
}

New-Item -ItemType Directory -Force -Path "worker" | Out-Null
Write-Host ("compiler: " + $compiler)
Write-Host "building zzztoj_worker.exe ..."
& $compiler -std=c++17 -O2 -Isrc @srcs -o worker/zzztoj_worker.exe -static -static-libgcc -static-libstdc++
if ($LASTEXITCODE -ne 0) { throw "build failed" }
Write-Host ("done: {0} bytes" -f (Get-Item worker/zzztoj_worker.exe).Length)
Write-Host "selftest: .\worker\zzztoj_worker.exe selftest"
