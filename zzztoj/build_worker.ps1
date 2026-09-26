# 构建 zzztoj worker（本游戏用的 bot 进程）
# 依赖：MinGW g++（本机 E:\mingw64\mingw64\bin\g++.exe，已加入 PATH）
# 若要改用 MSVC/CMake，可参考 CMakeLists.txt 的 io_dll 目标（同一套源文件）
$ErrorActionPreference = "Stop"
$srcs = @(
    "src/zzztoj_worker.cpp",
    "src/ai_zzz.cpp",
    "src/tetris_core.cpp",
    "src/rule_asc.cpp",      # 本游戏 ASC 踢墙规则
    "src/rule_srs.cpp",      # 节点几何/转向模板来源
    "src/search_amini.cpp",  # 覆盖 T/AllSpin/Mini 的搜索
    "src/integer_utils.cpp",
    "src/random.cpp"
)
Write-Host "编译 zzztoj_worker.exe ..."
& g++ -std=c++17 -O2 -Isrc @srcs -o zzztoj_worker.exe -static -static-libgcc -static-libstdc++
if ($LASTEXITCODE -ne 0) { throw "编译失败" }
Write-Host ("完成: {0} 字节" -f (Get-Item zzztoj_worker.exe).Length)
Write-Host "自检： .\zzztoj_worker.exe selftest"
