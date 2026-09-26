# zzztoj 接入说明（替换 ColdClear）

本目录是第三方项目 [paback2/zzztoj](https://github.com/paback2/zzztoj)（master，已 vendored，注释原为 GBK 已转 UTF-8）。
它是一个 **C++17 位棋盘俄罗斯方块 AI 框架**（最大 32×40，bitboard/位运算优化），不是现成的 bot 进程，
需要写一个适配层才能给游戏用。原先的 ColdClear（`rust/cold_clear_engine` + `coldclear_worker.exe`）由本框架取代。

## 1. zzztoj 的两套对外接口

### A. `AIPath`（demo.cpp，最贴近本游戏）
```c
int AIPath(int boardW, int boardH, char board[], char curPiece,
           int curX, int curY, int curR, char nextPiece, char path[]);
```
- `board`：一维 char 数组，`'1'` = 实心（按 `y*boardW + x` 排布）
- `curX/curY/curR`：当前方块的位置与旋转（注意 demo 里传的是 `curX-1, curY-1, curR-1`，说明外部是 1-based/0-based 差异）
- `path`：输出操作串，字符集与**本游戏的动作几乎一一对应**：

| zzztoj | 含义 | 本游戏 BotAction |
|---|---|---|
| `l` / `r` | 左/右移一格 | `left` / `right` |
| `L` / `R` | 左/右移到墙 | 连续 `left`/`right`（游戏 ARR=0 本身就是滑到墙） |
| `d` | 下移一格 | 单步下落（`_try_move(0,1)`，游戏无独立动作，可省或映射为软降一步） |
| `D` | 落到底（不锁定） | `soft_drop`（`soft_drop_to_bottom()`） |
| `z` / `c` | 逆/顺时针旋转 | `rotate_left` / `rotate_right` |
| `\0` | 落地（硬降） | `hard_drop` |

### B. io-DLL 接口（`src/io_dll_specs.h`，作者给自己外挂用的）
`TETRISAI(const Field*, const Queue*, const Status*) -> const char*`，额外的 `Status` 带 b2b/combo/预告垃圾，
`Config` 带 `allow180 / canHold / garbageCap / clutch / lockout`，`Field` 是 `int field[32]` 行位掩码 + width。
信息比 A 多（能给 AI 看 b2b/combo/垃圾），适合做“完全体”接入。

## 2. 规则（踢墙/SRS 系）是可插拔模块

`TetrisRule` 需要实现：
```cpp
static bool init(int w, int h);
static std::map<std::pair<char,uint8_t>, m_tetris::TetrisOpertion> get_opertion();
static std::map<char, m_tetris::TetrisBlockStatus(*)(m_tetris::TetrisContext const*)> get_generate();
```
`TetrisOpertion` 形如 `{ node, cw模板, ccw模板, nullptr, {N, CW踢墙偏移表}, {N, CCW踢墙偏移表} }`
（见 `rule_srs.cpp`：I 块 `{4, {{-2,0},{1,0},{-2,-1},{1,2}}}` 即 SRS I 表）。
现成规则：`rule_srs`(SRS) / `rule_srsx` / `rule_toj`(TOJ) / `rule_asrs` / `rule_qq` / `rule_st` / `rule_tag` / `rule_c2` / `rule_io`。

### 适配本游戏的 ASC 踢墙（要新增 `rule_asc.cpp/.h`）
本游戏（`TetrisController.kick_table["all"]`）用的是**单张 21 组 ASC 表**，且：
- 不区分方块、不区分 from→to 状态；
- 逆时针 = 该表 **X 取反**；180° 复用同一张表。
zzztoj 的模型是“每个旋转状态各有一张 CW/CCW 表”，因此**忠实等价的做法**是：
- 所有方块、所有状态的 **CW 表** = 21 组 ASC 偏移原样；
- 所有状态的 **CCW 表** = 同一张表逐项 `(-dx, dy)`；
- O 块给空表（游戏里 O 旋转是几何空操作，只有 (0,0)）；
- 180：本游戏 180 走 ASC 表，zzz 侧由 `search_tspin::Config::allow_180` 控制是否允许 180 操作即可。
> 计分坐标系需按 `tetris_core.h` 的 y 方向把 dy 取反（本游戏 y 向下）；两边必须逐项对齐，否则会出现“AI 以为能踢、游戏踢不动”的错位。

### 适配本游戏的 spin / allspin 判定
本游戏规则（`Scripts/main_game/tetris_clear_line.gd`）：
1. **不可移动判定为 spin**：上下左右四方向都撞（查询时排除自身格子）→ full spin；
2. T 块额外 mini：**下 2 角 + 上 1 角**被封堵 → `Mini T-Spin`；
3. **O 块永不判 spin**；
4. 模式：`tetris_allspin`（非 T 块卡住 → full spin）／`NoSpin=1`（全部降级 mini）／`NoSpin=2`（不判 spin）。
zzztoj 侧对应模块：`search_tspin`（T 的 None/TSpin/TSpinMini）与 `search_amini`（all-mini，非 T 旋转）。
适配点：让这两个模块的分类函数与本游戏 `_detect_spin_type / _is_piece_stuck / _detect_t_spin_mini` 一致
（自重叠排除、O 排除、mini 角块规则、allspin 开关），否则 AI 的评估与实际得分不一致。

## 3. AI 参数（替代 CC 权重）

- `src/ai_zzz.h`：主 AI（作者最强 AI）的全部可调参数；`src/ai_zzz.cpp` 为实现。
- `src/search_tspin.h :: Config`：`allow_rotate_move / allow_180 / allow_d / allow_D / allow_LR / is_20g / last_rotate`。
- 原 `GameSaveData/BuffChoseData.json` 的 `ExtraBotChange`（tspin1/allspin1/combo_garbage… 都是 CC 权重名）
  已改名为 `_disabled_ExtraBotChange` 停用，保留作参考；新的 zzz 参数将集中放在
  `Scripts/bot_play/zzz_bridge.gd` 的 `zzz_*` 配置里，并由 buff 覆盖。

## 4. 构建与接入方案（待实施）

**worker 方案**：新增独立 worker 可执行文件（替代 `coldclear_worker.exe`），直接用 g++/MSVC 编译：
```
src/tetris_core.cpp  src/ai.cpp  src/ai_zzz.cpp  src/search_tspin.cpp
src/rule_asc.cpp     src/integer_utils.cpp  src/random.cpp  zzztoj_worker.cpp
```
- `integer_utils.h` 用 `__SSE4_2__` 守卫 popcount，非 SSE4.2 走 `BitCountImpl` → MinGW 也能编。
- 本机可用工具链：**MinGW g++（E:\mingw64）**；无 cmake/ninja/MSVC（MSVC 需在你机器上用 `.vcxproj`/CMake 编）。
- Godot 侧：把 `Scripts/bot_play/coldclear_bridge.gd` 换成 `zzz_bridge.gd`（或在其内切换引擎），
  协议由“CC 的 S/W/R/H/GO + L/R/C/K/Z/D 移动串”改为 zzz 的 `AIPath` 风格（板面 + 当前块 + next → 操作串），
  `TetrisController._apply_bot_action` 的动作映射基本不变。

## 5. 剩余工作清单
- [x] vendored 源码、GBK→UTF-8
- [x] JSON 中 CC 参数停用（改名 `_disabled_ExtraBotChange`）
- [ ] `rule_asc.cpp/.h`：ASC 21 组踢墙 + O 空表 + 坐标对齐
- [ ] spin/allspin 分类对齐（`search_tspin`/`search_amini` 或新增 `search_game.cpp`）
- [ ] `zzztoj_worker.cpp`：板面/队列/Hold 转换 + `AIPath` 式输出 + 行协议
- [ ] 用 g++ 编译 worker 并做离线单测（给定板面 → 打印操作串）
- [ ] `zzz_bridge.gd`：接 worker、PPS 节奏、卡死保护、参数下发
- [ ] 导出流程（`export_presets.cfg`/`build/export_copy_native.ps1`）里替换 native 文件
