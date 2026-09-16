/*
 * coldclear_worker.c
 *
 * ColdClear decision worker for the tetris-tower Godot project.
 *
 * This is a small console program that dynamically loads the prebuilt
 * `cold_clear.dll` (the official ColdClear C ABI, see c-api/) at runtime and
 * exposes a tiny line-based protocol over stdin/stdout. Godot drives it via
 * `OS.execute_with_pipe` — this is the workaround for Godot 4.7 not exposing
 * an in-process FFI API (no NativeCallable / OS.load_dynamic_library).
 *
 * Protocol (one command per line, ASCII):
 *   W <width> <height>          set board dimensions (default 10x20)
 *   R <rowIndex> <0/1 string>   set board row (row 0 = TOP row) e.g. R 0 0001000000
 *   H <piece|->                 set hold piece (I O T L J S Z, '-' = none)
 *   GO <use_hold> <max_nodes> <min_nodes> <threads> <b2b> <combo> <incoming> <bag_remain> <qcount> <q0> <q1>...
 *                               threads: 并行搜索线程数（0=默认单线程，多线程可加速检索）
 *   QUIT                        destroy bot + exit
 *
 * Reply to GO (single line on stdout, flushed):
 *   OK <hold> <n> <mv0> ... <mv{n-1}>     hold=0/1, mv in {L,R,C,K,Z,D}
 *   DEAD                                  bot found it cannot survive
 *   ERR <message>                         anything went wrong
 *
 * Build (MinGW GCC):
 *   gcc -O2 -o coldclear_worker.exe coldclear_worker.c
 *
 * The struct layouts below MUST match `c-api/src/lib.rs` (all #[repr(C)]).
 */

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

/* ---- enums (match c-api/src/lib.rs cenum! definitions) ---- */
typedef enum {
	CC_I, CC_O, CC_T, CC_L, CC_J, CC_S, CC_Z
} CCPiece;

typedef enum {
	CC_NONE_TSPIN_STATUS, CC_MINI, CC_FULL
} CCTspinStatus;

typedef enum {
    CC_LEFT, CC_RIGHT, CC_CW, CC_CCW, CC_180, CC_DROP
} CCMovement;

typedef enum {
	CC_0G, CC_20G, CC_HARD_DROP_ONLY
} CCMovementMode;

typedef enum {
    CC_ROW_19_OR_20, CC_ROW_21_AND_FALL, CC_ROW_CUSTOM
} CCSpawnRule;

typedef enum {
	CC_PC_OFF, CC_PC_FASTEST, CC_PC_ATTACK
} CCPcPriority;

typedef enum {
	CC_MOVE_PROVIDED, CC_WAITING, CC_BOT_DEAD
} CCBotPollStatus;

typedef struct CCAsyncBot CCAsyncBot;
typedef struct CCBook CCBook;

/* ---- C structs (mirror Rust #[repr(C)] types) ---- */

typedef struct CCPlanPlacement {
	CCPiece piece;
	CCTspinStatus tspin;
	uint8_t expected_x[4];
	uint8_t expected_y[4];
	int32_t cleared_lines[4];
} CCPlanPlacement;

typedef struct CCMove {
	bool hold;
	uint8_t expected_x[4];
	uint8_t expected_y[4];
	uint8_t movement_count;
	CCMovement movements[32];
	uint32_t nodes;
	uint32_t depth;
	uint32_t original_rank;
} CCMove;

typedef struct CCOptions {
    CCMovementMode mode;
    CCSpawnRule spawn_rule;
    uint8_t spawn_y;
    uint8_t lockout_y;
    CCPcPriority pcloop;
    uint32_t min_nodes;
    uint32_t max_nodes;
    uint32_t threads;
    bool use_hold;
    bool speculate;
} CCOptions;

typedef struct CCWeights {
    int32_t back_to_back;
    int32_t bumpiness;
    int32_t bumpiness_sq;
    int32_t row_transitions;
    int32_t height;
    int32_t top_half;
    int32_t top_quarter;
    int32_t jeopardy;
    int32_t cavity_cells;
    int32_t cavity_cells_sq;
    int32_t overhang_cells;
    int32_t overhang_cells_sq;
    int32_t covered_cells;
    int32_t covered_cells_sq;
    int32_t tslot[4];
    int32_t well_depth;
    int32_t max_well_depth;
    int32_t well_column[10];
    int32_t b2b_clear;
    int32_t clear1;
    int32_t clear2;
    int32_t clear3;
    int32_t clear4;
    int32_t tspin1;
    int32_t tspin2;
    int32_t tspin3;
    int32_t mini_tspin1;
    int32_t mini_tspin2;
    int32_t allspin1;
    int32_t allspin2;
    int32_t allspin3;
    int32_t allspin3plus;
    int32_t perfect_clear;
    int32_t combo_garbage;
    int32_t move_time;
    int32_t wasted_t;
    bool use_bag;
    bool timed_jeopardy;
    bool stack_pc_damage;

    /* 实际游戏伤害模型参数（tower-tetris 规则，可由 buff 界面调整） */
    bool game_damage_enabled;
    int32_t base_damage[5];
    int32_t tspin_damage[4];
    int32_t allspin_damage[4];
    int32_t combo_damage[32];
    int32_t combo_formula;   /* 0=旧连击表，1=新公式（默认） */
    int32_t b2b_bonus;
    int32_t pc_damage;
    int32_t send_mult_attack;   /* 千分比 1000=1.0 */
    int32_t mult_defend;
    int32_t damage_eval_mult;
    int32_t attack_efficiency_weight;   /* 攻击效率权重：效率=伤害/消行数 */
    int32_t allspin_enabled;   /* allspin 规则模式：0=allmini，1=allspin，其余保留 */
    int32_t allspin_repeat_penalty;
    int32_t kick_table[64];
    int32_t kick_table_len;
    int32_t no_spin;   /* NoSpin 规则：0=正常Spin判定；1=所有Spin视为Mini；2=不判定任何Spin */
} CCWeights;

/* ---- function pointer signatures (from c-api coldclear.h) ---- */
typedef CCAsyncBot *(*Fn_launch_with_board)(CCOptions *, CCWeights *, CCBook *, bool *, uint32_t, CCPiece *, bool, uint32_t, CCPiece *, uint32_t, uint64_t);
typedef void (*Fn_destroy)(CCAsyncBot *);
typedef void (*Fn_reset)(CCAsyncBot *, bool *, bool, uint32_t, uint64_t);
typedef void (*Fn_add_next_piece)(CCAsyncBot *, CCPiece);
typedef void (*Fn_request_next_move)(CCAsyncBot *, uint32_t);
typedef CCBotPollStatus (*Fn_poll_next_move)(CCAsyncBot *, CCMove *, CCPlanPlacement *, uint32_t *);
typedef CCBotPollStatus (*Fn_block_next_move)(CCAsyncBot *, CCMove *, CCPlanPlacement *, uint32_t *);
typedef void (*Fn_default_options)(CCOptions *);
typedef void (*Fn_default_weights)(CCWeights *);

static CCAsyncBot *g_bot = NULL;
static bool g_field[400];           /* ColdClear field: row-major, index 0 = bottom-left */
static bool g_pred_field[400];      /* Predicted next field after previously returned move */
static int g_W = 10, g_H = 20;
static CCPiece g_hold = CC_I;
static bool g_has_hold = false;
static CCPiece g_prev_queue[32];
static int g_prev_qn = 0;
static bool g_has_last_config = false;
static int g_last_use_hold = 1;
static uint32_t g_last_max_nodes = 0;
static uint32_t g_last_min_nodes = 0;
static uint32_t g_last_threads = 0;
static bool g_has_pred_field = false;

/* ---- 实际游戏规则/伤害模型（由 S 命令设置，默认与游戏标准一致） ---- */
static bool g_has_game_rules = false;
static bool g_game_damage_enabled = true;
static int32_t g_base_damage[5] = {0, 0, 1, 2, 4};
static int32_t g_tspin_damage[4] = {0, 2, 4, 6};
static int32_t g_allspin_damage[4] = {0, 4, 6, 8};
static int32_t g_allspin_enabled = 0;   /* 0=allmini（非T卡住→minispin），1=allspin（非T卡住→fullspin），其余保留 */
static int32_t g_allspin_repeat_penalty = -120;   /* bot 评估权重：allspin 重复惩罚扣分 */
static int32_t g_clear1 = -143;
static int32_t g_clear2 = -100;
static int32_t g_clear3 = -58;
static int32_t g_tspin1 = 121;
static int32_t g_tspin2 = 410;
static int32_t g_tspin3 = 602;
static int32_t g_mini_tspin1 = -158;
static int32_t g_mini_tspin2 = -93;
static int32_t g_allspin1 = 121;
static int32_t g_allspin2 = 410;
static int32_t g_allspin3 = 602;
static int32_t g_allspin3plus = 602;
static int32_t g_perfect_clear = 999;
static int32_t g_combo_garbage = 150;
static int32_t g_wasted_t = -152;
static int32_t g_move_time = -3;
static int32_t g_kick_table[64] = {0};
static int32_t g_kick_len = 0;
static uint64_t g_solid_mask = 0;   /* 实心垃圾行位掩码（bit = CC 行号，0=底部） */
static int32_t g_combo_damage[32] = {
    0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 4, 4, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5
};
static int32_t g_combo_formula = 1;   /* 0=旧连击表，1=新公式（默认） */
static int32_t g_b2b_bonus = 1;
static int32_t g_pc_damage = 10;
static int32_t g_send_mult_attack = 1000;   /* 千分比 1000=1.0 */
static int32_t g_mult_defend = 1000;
static int32_t g_damage_eval_mult = 100;
static int32_t g_attack_efficiency_weight = 100;   /* bot 评估权重：攻击效率=伤害/消行数 */
static int32_t g_b2b_clear = 200;    /* bot 评估权重：维持 BTB */
static int32_t g_height = -39;       /* bot 评估权重：放块后的堆叠最高点（负值=压高） */
static int32_t g_clear4 = 260;       /* bot 评估权重：四消 */
static int32_t g_no_spin = 0;        /* NoSpin 规则：0=正常；1=所有Spin视为Mini；2=不判定任何Spin */
static uint32_t g_rules_version = 0;
static uint32_t g_last_rules_version = 0;

static int piece_char_to_enum(char c) {
	switch (c) {
		case 'I': return CC_I;
		case 'O': return CC_O;
		case 'T': return CC_T;
		case 'L': return CC_L;
		case 'J': return CC_J;
		case 'S': return CC_S;
		case 'Z': return CC_Z;
		default: return -1;
	}
}

static char piece_enum_to_char(int e) {
	switch (e) {
		case CC_I: return 'I';
		case CC_O: return 'O';
		case CC_T: return 'T';
		case CC_L: return 'L';
		case CC_J: return 'J';
		case CC_S: return 'S';
		case CC_Z: return 'Z';
		default: return '?';
	}
}

static void field_set_cell(int cold_row, int col, bool filled) {
	if (cold_row < 0 || cold_row >= 40) return;
	if (col < 0 || col >= g_W) return;
	g_field[cold_row * 10 + col] = filled;
}

static int min_int(int a, int b) {
	return a < b ? a : b;
}

/*
 * Compute overlap length k so that suffix(prev, k) == prefix(cur, k).
 * Expected normal case per placed piece: k == prev_qn - 1.
 */
static int queue_overlap(const CCPiece *prev, int prev_n, const CCPiece *cur, int cur_n) {
	int max_k = min_int(prev_n, cur_n);
	for (int k = max_k; k >= 0; --k) {
		bool ok = true;
		for (int i = 0; i < k; ++i) {
			if (prev[prev_n - k + i] != cur[i]) {
				ok = false;
				break;
			}
		}
		if (ok) return k;
	}
	return 0;
}

static void remember_queue(const CCPiece *queue, int qn) {
	if (qn < 0) qn = 0;
	if (qn > 32) qn = 32;
	for (int i = 0; i < qn; ++i) g_prev_queue[i] = queue[i];
	g_prev_qn = qn;
}

static void clear_field(bool *field) {
	memset(field, 0, sizeof(bool) * 400);
}

static void copy_field(bool *dst, const bool *src) {
	memcpy(dst, src, sizeof(bool) * 400);
}

/* Compare only rows [0, h) and cols [0, w), which are the rows provided by the host snapshot. */
static bool snapshot_matches_pred(const bool *cur, const bool *pred, int w, int h) {
	if (w <= 0 || w > 10 || h <= 0 || h > 40) return false;
	for (int r = 0; r < h; ++r) {
		for (int c = 0; c < w; ++c) {
			int idx = r * 10 + c;
			if (cur[idx] != pred[idx]) return false;
		}
	}
	return true;
}

static void clear_full_lines(bool *field) {
	for (int r = 0; r < 40; ++r) {
		bool full = true;
		for (int c = 0; c < 10; ++c) {
			if (!field[r * 10 + c]) {
				full = false;
				break;
			}
		}
		if (!full) continue;

		for (int rr = r; rr < 39; ++rr) {
			for (int c = 0; c < 10; ++c) {
				field[rr * 10 + c] = field[(rr + 1) * 10 + c];
			}
		}
		for (int c = 0; c < 10; ++c) {
			field[39 * 10 + c] = false;
		}
		r -= 1;
	}
}

static void apply_expected_move_to_field(bool *field, const CCMove *mv) {
	for (int i = 0; i < 4; ++i) {
		int x = (int)mv->expected_x[i];
		int y = (int)mv->expected_y[i];
		if (x < 0 || x >= 10 || y < 0 || y >= 40) continue;
		field[y * 10 + x] = true;
	}
	clear_full_lines(field);
}

/* 把已存储的实际游戏规则应用到 CCWeights（在 GO 前调用） */
static void apply_game_rules(CCWeights *w) {
    w->game_damage_enabled = g_game_damage_enabled;
    memcpy(w->base_damage, g_base_damage, sizeof(g_base_damage));
    memcpy(w->tspin_damage, g_tspin_damage, sizeof(g_tspin_damage));
    memcpy(w->allspin_damage, g_allspin_damage, sizeof(g_allspin_damage));
    memcpy(w->combo_damage, g_combo_damage, sizeof(g_combo_damage));
    w->combo_formula = g_combo_formula;
    w->b2b_bonus = g_b2b_bonus;
    w->pc_damage = g_pc_damage;
    w->send_mult_attack = g_send_mult_attack;
    w->mult_defend = g_mult_defend;
    w->damage_eval_mult = g_damage_eval_mult;
    w->attack_efficiency_weight = g_attack_efficiency_weight;
    w->b2b_clear = g_b2b_clear;
    w->height = g_height;
    w->clear4 = g_clear4;
    w->allspin_enabled = g_allspin_enabled;
    w->allspin_repeat_penalty = g_allspin_repeat_penalty;
    w->clear1 = g_clear1;
    w->clear2 = g_clear2;
    w->clear3 = g_clear3;
    w->tspin1 = g_tspin1;
    w->tspin2 = g_tspin2;
    w->tspin3 = g_tspin3;
    w->mini_tspin1 = g_mini_tspin1;
    w->mini_tspin2 = g_mini_tspin2;
    w->allspin1 = g_allspin1;
    w->allspin2 = g_allspin2;
    w->allspin3 = g_allspin3;
    w->allspin3plus = g_allspin3plus;
    w->perfect_clear = g_perfect_clear;
    w->combo_garbage = g_combo_garbage;
    w->wasted_t = g_wasted_t;
    w->move_time = g_move_time;
    memset(w->kick_table, 0, sizeof(w->kick_table));
    for (int k = 0; k < g_kick_len && k < 32; ++k) {
        w->kick_table[k * 2] = g_kick_table[k * 2];
        w->kick_table[k * 2 + 1] = g_kick_table[k * 2 + 1];
    }
    w->kick_table_len = g_kick_len;
    w->no_spin = g_no_spin;
}

/* 解析 S 命令：
 * S <enabled> <base0..4> <tspin0..3> <allspin0..3> <b2b> <pc> <sendMult> <defendMult> <evalMult>
 *   <attack_efficiency_weight>
 *   <b2b_clear> <height> <clear4> <allspin_enabled> <allspin_repeat_penalty>
 *   <clear1> <clear2> <clear3> <tspin1> <tspin2> <tspin3> <mini_tspin1> <mini_tspin2>
 *   <allspin1> <allspin2> <allspin3> <allspin3plus>
 *   <perfect_clear> <combo_garbage> <wasted_t> <move_time>
 *   <kickLen> <kick dx,dy pairs: 2*kickLen> <combo0..31> <combo_formula> <no_spin>
 * 更精确的协议由 bridge 拼接；这里按固定顺序读取。 */
static void parse_game_rules(char *toks[], int nt) {
    if (nt < 9) return;
    int i = 1;
    g_game_damage_enabled = atoi(toks[i++]) != 0;
    for (int k = 0; k < 5 && i < nt; ++k) g_base_damage[k] = atoi(toks[i++]);
    for (int k = 0; k < 4 && i < nt; ++k) g_tspin_damage[k] = atoi(toks[i++]);
    for (int k = 0; k < 4 && i < nt; ++k) g_allspin_damage[k] = atoi(toks[i++]);
    if (i >= nt) return;
    g_b2b_bonus = atoi(toks[i++]);
    if (i >= nt) return;
    g_pc_damage = atoi(toks[i++]);
    if (i >= nt) return;
    g_send_mult_attack = atoi(toks[i++]);   /* 千分比 */
    if (i >= nt) return;
    g_mult_defend = atoi(toks[i++]);        /* 千分比 */
    if (i >= nt) return;
    g_damage_eval_mult = atoi(toks[i++]);
    if (i >= nt) return;
    g_attack_efficiency_weight = atoi(toks[i++]);
    if (i >= nt) return;
    g_b2b_clear = atoi(toks[i++]);
    if (i >= nt) return;
    g_height = atoi(toks[i++]);
    if (i >= nt) return;
    g_clear4 = atoi(toks[i++]);
    if (i >= nt) return;
    /* allspin_enabled 为 int：0=allmini（非T卡住→minispin），1=allspin（非T卡住→fullspin），其余保留 */
    g_allspin_enabled = atoi(toks[i++]);
    if (i >= nt) return;
    g_allspin_repeat_penalty = atoi(toks[i++]);
    if (i >= nt) return;
    g_clear1 = atoi(toks[i++]);
    if (i >= nt) return;
    g_clear2 = atoi(toks[i++]);
    if (i >= nt) return;
    g_clear3 = atoi(toks[i++]);
    if (i >= nt) return;
    g_tspin1 = atoi(toks[i++]);
    if (i >= nt) return;
    g_tspin2 = atoi(toks[i++]);
    if (i >= nt) return;
    g_tspin3 = atoi(toks[i++]);
    if (i >= nt) return;
    g_mini_tspin1 = atoi(toks[i++]);
    if (i >= nt) return;
    g_mini_tspin2 = atoi(toks[i++]);
    if (i >= nt) return;
    g_allspin1 = atoi(toks[i++]);
    if (i >= nt) return;
    g_allspin2 = atoi(toks[i++]);
    if (i >= nt) return;
    g_allspin3 = atoi(toks[i++]);
    if (i >= nt) return;
    g_allspin3plus = atoi(toks[i++]);
    if (i >= nt) return;
    g_perfect_clear = atoi(toks[i++]);
    if (i >= nt) return;
    g_combo_garbage = atoi(toks[i++]);
    if (i >= nt) return;
    g_wasted_t = atoi(toks[i++]);
    if (i >= nt) return;
    g_move_time = atoi(toks[i++]);
    if (i >= nt) return;
    int kick_len = atoi(toks[i++]);
    if (kick_len < 0) kick_len = 0;
    if (kick_len > 32) kick_len = 32;
    g_kick_len = kick_len;
    for (int k = 0; k < kick_len && i + 1 < nt; ++k) {
        g_kick_table[k * 2] = atoi(toks[i++]);
        g_kick_table[k * 2 + 1] = atoi(toks[i++]);
    }
    for (int k = 0; k < 32 && i < nt; ++k) g_combo_damage[k] = atoi(toks[i++]);
    if (i < nt) g_combo_formula = atoi(toks[i++]);
    if (i < nt) g_no_spin = atoi(toks[i++]);
    g_has_game_rules = true;
}

/* append tokenized words of a line into out[]; returns count */
static int tokenize(char *line, char *out[], int max) {
	int n = 0;
	char *save = NULL;
	char *p = strtok(line, " \t\r\n");
	while (p != NULL && n < max) {
		out[n++] = p;
		p = strtok(NULL, " \t\r\n");
	}
	return n;
}

int main(int argc, char **argv) {
	(void)argc; (void)argv;

	/* Resolve cold_clear.dll relative to this exe's own directory. */
	char dll_path[1024];
	DWORD len = GetModuleFileNameA(NULL, dll_path, sizeof(dll_path) - 32);
	if (len == 0 || len >= sizeof(dll_path) - 32) {
		printf("ERR cannot resolve exe path\n"); fflush(stdout);
		return 1;
	}
	char *slash = strrchr(dll_path, '\\');
	if (slash != NULL) strcpy(slash + 1, "cold_clear.dll");
	else strcpy(dll_path, "cold_clear.dll");

	HMODULE m = LoadLibraryA(dll_path);
	if (m == NULL) {
		printf("ERR LoadLibrary failed for %s (err=%lu)\n", dll_path, (unsigned long)GetLastError());
		fflush(stdout);
		return 1;
	}

	Fn_launch_with_board launch_with_board = (Fn_launch_with_board)GetProcAddress(m, "cc_launch_with_board_async");
	Fn_destroy destroy = (Fn_destroy)GetProcAddress(m, "cc_destroy_async");
	Fn_reset reset_bot = (Fn_reset)GetProcAddress(m, "cc_reset_async");
	Fn_add_next_piece add_next = (Fn_add_next_piece)GetProcAddress(m, "cc_add_next_piece_async");
	Fn_request_next_move request_next = (Fn_request_next_move)GetProcAddress(m, "cc_request_next_move");
	Fn_block_next_move block_next = (Fn_block_next_move)GetProcAddress(m, "cc_block_next_move");
	Fn_default_options def_opts = (Fn_default_options)GetProcAddress(m, "cc_default_options");
	Fn_default_weights def_weights = (Fn_default_weights)GetProcAddress(m, "cc_default_weights");

	if (launch_with_board == NULL || destroy == NULL || reset_bot == NULL || add_next == NULL ||
		request_next == NULL || block_next == NULL || def_opts == NULL || def_weights == NULL) {
		printf("ERR missing required cc_* symbols in %s\n", dll_path);
		fflush(stdout);
		FreeLibrary(m);
		return 1;
	}

	char line[4096];
	while (fgets(line, sizeof(line), stdin) != NULL) {
		char cmd[32];
		if (sscanf(line, "%31s", cmd) != 1) continue;

		if (strcmp(cmd, "W") == 0) {
			int w = 10, h = 20;
			sscanf(line, "%*s %d %d", &w, &h);
			if (w > 0 && w <= 10) g_W = w;
			if (h > 0 && h <= 40) g_H = h;
			/* Host sends R rows after each W; clear previous snapshot first to avoid stale cells. */
			clear_field(g_field);
			g_solid_mask = 0;   /* 实心行掩码由随后的 G 命令提供 */
		}
		else if (strcmp(cmd, "R") == 0) {
			int r = -1; char row[64];
			if (sscanf(line, "%*s %d %63s", &r, row) == 2 && r >= 0 && r < g_H) {
				/* input row r is TOP-first; ColdClear row 0 is BOTTOM */
				int cold_row = (g_H - 1) - r;
				for (int c = 0; c < g_W && row[c] != '\0'; c++) {
					field_set_cell(cold_row, c, row[c] == '1');
				}
			}
		}
		else if (strcmp(cmd, "H") == 0) {
			char p[16];
			if (sscanf(line, "%*s %15s", p) == 1) {
				if (strcmp(p, "-") == 0) {
					g_has_hold = false;
				} else {
					int e = piece_char_to_enum(p[0]);
					if (e >= 0) { g_hold = (CCPiece)e; g_has_hold = true; }
				}
			}
		}
		else if (strcmp(cmd, "S") == 0) {
            /* 设置实际游戏规则/伤害模型（buff 界面可调整） */
            char *rtoks[80];
            int rnt = tokenize(line, rtoks, 80);
            parse_game_rules(rtoks, rnt);
            g_rules_version++;
        }        else if (strcmp(cmd, "G") == 0) {
            /* 实心垃圾行掩码：G <mask>，mask 位 i = 发送窗口行 i 是实心行（0=窗口顶部，与 R 一致） */
            unsigned long long m = 0;
            sscanf(line, "%*s %llu", &m);
            /* 转成 CC 行号（0=底部）位掩码：窗口行 r ↔ cold_row = (g_H-1)-r */
            g_solid_mask = 0;
            for (int r = 0; r < g_H; r++) {
                if ((m >> r) & 1ULL) {
                    g_solid_mask |= 1ULL << (unsigned)((g_H - 1) - r);
                }
            }
        }        else if (strcmp(cmd, "GO") == 0) {
			char *toks[80];
			int nt = tokenize(line, toks, 80);
			int use_hold = (nt > 1) ? atoi(toks[1]) : 1;
			uint32_t max_nodes = (nt > 2) ? (uint32_t)strtoul(toks[2], NULL, 10) : 4000000000u;
			uint32_t min_nodes = (nt > 3) ? (uint32_t)strtoul(toks[3], NULL, 10) : 0u;
			/* 并行搜索线程数：0 = 默认单线程 */
			uint32_t threads = (nt > 4) ? (uint32_t)strtoul(toks[4], NULL, 10) : 0u;
			int b2b = (nt > 5) ? atoi(toks[5]) : 0;
			int combo = (nt > 6) ? atoi(toks[6]) : 0;
			int incoming = (nt > 7) ? atoi(toks[7]) : 0;
			unsigned int bag_remain = (nt > 8) ? (unsigned int)strtoul(toks[8], NULL, 0) : 0x7F;
			int qcount = (nt > 9) ? atoi(toks[9]) : 0;
			CCPiece queue[32];
			int qn = 0;
			for (int i = 10; i < nt && qn < 32; i++) {
				int e = piece_char_to_enum(toks[i][0]);
				if (e >= 0) queue[qn++] = (CCPiece)e;
			}
			(void)qcount;

            /* 队列为空时，bot 无法产出任何 move（其线程会一直等待下一个方块），
             * 直接报错让宿主回退到默认 bot，避免永久挂起。 */
            if (qn == 0) {
                printf("ERR empty_queue\n");
                fflush(stdout);
                continue;
            }

            CCOptions opts;
            def_opts(&opts);
            opts.use_hold = use_hold ? true : false;
            opts.max_nodes = max_nodes;
            opts.min_nodes = min_nodes;
            opts.threads = threads > 0 ? threads : 1;   /* 0 = 默认单线程 */
            /*
             * Adapt ColdClear to the tower-tetris board: the host sends a window of
             * `g_H` rows (e.g. 24). New pieces spawn near the top of the window
             * (g_H - 3) and lockout is at the top 2 rows (g_H - 2).
             */
            opts.spawn_rule = CC_ROW_CUSTOM;
            opts.spawn_y = (uint8_t)(g_H - 3);
            opts.lockout_y = (uint8_t)(g_H - 2);

			CCWeights weights;
            def_weights(&weights);
            apply_game_rules(&weights);   /* 应用实际游戏规则/伤害模型 */

            bool need_relaunch = false;
            bool need_reset = false;
            if (g_bot == NULL) {
                need_relaunch = true;
            }
            if (g_has_last_config) {
                if (g_last_use_hold != use_hold) {
                    need_relaunch = true;
                }
                if (g_last_max_nodes != max_nodes) {
                    need_relaunch = true;
                }
                if (g_last_min_nodes != min_nodes) {
                    need_relaunch = true;
                }
                if (g_last_threads != threads) {
                    need_relaunch = true;
                }
            }
            /* 游戏规则变化 → 强制重建 bot（评估权重已变） */
            if (g_has_game_rules && g_last_rules_version != g_rules_version) {
                need_relaunch = true;
            }

			if (need_relaunch) {
				if (g_bot != NULL) {
					destroy(g_bot);
					g_bot = NULL;
				}

				g_bot = launch_with_board(&opts, &weights, NULL,
					g_field, bag_remain,
					g_has_hold ? &g_hold : NULL,
					b2b ? true : false, (uint32_t)combo,
					queue, (uint32_t)qn, g_solid_mask);
			} else {
				if (g_has_pred_field && !snapshot_matches_pred(g_field, g_pred_field, g_W, g_H)) {
					need_reset = true;
				}

				/*
				 * Reuse the existing bot and only append truly new queue pieces.
				 * This avoids rebuilding search state on every piece.
				 */
				int overlap = queue_overlap(g_prev_queue, g_prev_qn, queue, qn);
				int expected_overlap = g_prev_qn > 0 ? (g_prev_qn - 1) : 0;
				if (overlap != expected_overlap) {
					/* Queue progression broke contract; safest recovery is full relaunch. */
					if (g_bot != NULL) {
						destroy(g_bot);
						g_bot = NULL;
					}
					g_bot = launch_with_board(&opts, &weights, NULL,
						g_field, bag_remain,
						g_has_hold ? &g_hold : NULL,
						b2b ? true : false, (uint32_t)combo,
						queue, (uint32_t)qn, g_solid_mask);
					need_reset = false;
				} else {
					if (need_reset) {
						/* Board changed unexpectedly (e.g. sudden garbage rise): reset field state. */
						reset_bot(g_bot, g_field, b2b ? true : false, (uint32_t)combo, g_solid_mask);
					}
					for (int i = overlap; i < qn; ++i) {
						add_next(g_bot, queue[i]);
					}
				}
			}

			if (g_bot == NULL) {
				printf("ERR cc_launch_with_board_async returned NULL\n");
				fflush(stdout);
				continue;
			}

			g_last_use_hold = use_hold;
            g_last_max_nodes = max_nodes;
            g_last_min_nodes = min_nodes;
            g_last_threads = threads;
            g_last_rules_version = g_rules_version;
            g_has_last_config = true;
            remember_queue(queue, qn);

			request_next(g_bot, (uint32_t)incoming);
			CCMove mv;
			memset(&mv, 0, sizeof(mv));
			CCPlanPlacement plan_buf[32];
			uint32_t plan_len = 32;
			CCBotPollStatus st = block_next(g_bot, &mv, plan_buf, &plan_len);

			if (st == CC_BOT_DEAD) {
				g_has_pred_field = false;
				printf("DEAD\n");
				fflush(stdout);
			} else {
				copy_field(g_pred_field, g_field);
				apply_expected_move_to_field(g_pred_field, &mv);
				g_has_pred_field = true;

				unsigned int n = mv.movement_count;
				if (n > 32) n = 32;
				/* 附带 CC 期望落点 cells 坐标（调试用）：OK <hold> <n> E <ex0> <ey0> ... <ex3> <ey3> <mv...> */
				printf("OK %d %u E", mv.hold ? 1 : 0, n);
				for (int e = 0; e < 4; e++) {
					printf(" %d %d", (int)mv.expected_x[e], (int)mv.expected_y[e]);
				}
				for (unsigned int i = 0; i < n; i++) {
					char c = '?';
					switch (mv.movements[i]) {
                        case CC_LEFT:  c = 'L'; break;
                        case CC_RIGHT: c = 'R'; break;
                        case CC_CW:    c = 'C'; break;
                        case CC_CCW:   c = 'K'; break;
                        case CC_180:   c = 'Z'; break;
                        case CC_DROP:  c = 'D'; break;
                        default:       c = '?'; break;
                    }
					printf(" %c", c);
				}
				/* 整条最优计划（可绘制）：... <mv> P <count> <piece> <x0> <y0> <x1> <y1> <x2> <y2> <x3> <y3> <c0> <c1> <c2> <c3> ...
				 * piece = 方块类型字符（I/O/T/L/J/S/Z，用于绘制颜色）；
				 * x/y = 该方块最终落定的 4 个 cells 绝对坐标（CC：x 0..9，y 向上，y=0 底部）；
				 * c0..c3 = 该落块消去的行号（CC 绝对行号，-1=该槽位无消行）。
				 * plan_buf[0] = 当前块落点，其后为未来各块。 */
				printf(" P %u", plan_len);
				for (uint32_t p = 0; p < plan_len; p++) {
					printf(" %c %d %d %d %d %d %d %d %d %d %d %d %d",
						piece_enum_to_char((int)plan_buf[p].piece),
						(int)plan_buf[p].expected_x[0], (int)plan_buf[p].expected_y[0],
						(int)plan_buf[p].expected_x[1], (int)plan_buf[p].expected_y[1],
						(int)plan_buf[p].expected_x[2], (int)plan_buf[p].expected_y[2],
						(int)plan_buf[p].expected_x[3], (int)plan_buf[p].expected_y[3],
						(int)plan_buf[p].cleared_lines[0], (int)plan_buf[p].cleared_lines[1],
						(int)plan_buf[p].cleared_lines[2], (int)plan_buf[p].cleared_lines[3]);
				}
				printf("\n");
				fflush(stdout);
			}
		}
		else if (strcmp(cmd, "QUIT") == 0) {
			break;
		}
	}

	if (g_bot != NULL) destroy(g_bot);
	FreeLibrary(m);
	return 0;
}
