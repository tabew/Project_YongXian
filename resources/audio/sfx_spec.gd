class_name SfxSpec
extends RefCounted

## 音效参数表：每个音效的音量、音高抖动、最小间隔、同时发声上限与所属总线。
##
## 音效 id 就是 assets/audio/sfx 下的文件名（不含扩展名）。新增素材时先放文件，
## 再在这里补一行参数；没写进表里的 id 会退回 DEFAULT，所以漏配不会静音。
##
## 参数含义：
## - volume_db：相对总线音量的衰减，数值越小越轻。
## - pitch_variation：每次播放的音高抖动幅度（±比例），避免同一音效连播时听感发木。
## - min_interval：两次播放之间的最小间隔（秒），用于压制连击刷屏。
## - max_voices：同时允许存在的发声数，超出直接丢弃本次播放。
## - bus：SFX 走世界音效总线，UI 走界面总线，方便分别调节。

const DEFAULT: Dictionary = {
	"volume_db": -6.0,
	"pitch_variation": 0.05,
	"min_interval": 0.02,
	"max_voices": 2,
	"bus": &"SFX",
}

const SPECS: Dictionary = {
	# 挥砍：三把武器各有音色，缺素材时由 swing_generic 兜底。
	&"swing_longsword": {"volume_db": -8.0, "pitch_variation": 0.10, "min_interval": 0.05, "max_voices": 3},
	&"swing_long_staff": {"volume_db": -9.0, "pitch_variation": 0.10, "min_interval": 0.05, "max_voices": 3},
	&"swing_yoyo": {"volume_db": -10.0, "pitch_variation": 0.10, "min_interval": 0.05, "max_voices": 3},
	&"swing_depth_strike": {"volume_db": -7.0, "pitch_variation": 0.08, "min_interval": 0.05, "max_voices": 3},
	&"swing_generic": {"volume_db": -9.0, "pitch_variation": 0.10, "min_interval": 0.05, "max_voices": 3},

	# 命中：按受击目标材质区分，暴击单独一档。
	&"hit_flesh": {"volume_db": -4.0, "pitch_variation": 0.12, "min_interval": 0.03, "max_voices": 4},
	&"hit_critical": {"volume_db": -3.0, "pitch_variation": 0.06, "min_interval": 0.05, "max_voices": 4},
	&"hit_wood": {"volume_db": -6.0, "pitch_variation": 0.12, "min_interval": 0.03, "max_voices": 4},
	&"hit_stone": {"volume_db": -6.0, "pitch_variation": 0.12, "min_interval": 0.03, "max_voices": 3},

	# 草丛被武器切断：连扫时每 0.07 秒最多响一次。
	&"cut_grass": {"volume_db": -15.0, "pitch_variation": 0.20, "min_interval": 0.07, "max_voices": 3},

	# 怪物与主角。
	&"monster_hurt": {"volume_db": -7.0, "pitch_variation": 0.14, "min_interval": 0.06, "max_voices": 4},
	&"monster_die": {"volume_db": -4.0, "pitch_variation": 0.10, "min_interval": 0.08, "max_voices": 3},
	&"player_hurt": {"volume_db": -3.0, "pitch_variation": 0.05, "min_interval": 0.15, "max_voices": 2},
	&"player_defeat": {"volume_db": -2.0, "pitch_variation": 0.0, "min_interval": 0.50, "max_voices": 1},

	# 材料进出背包。
	&"pickup_material": {"volume_db": -10.0, "pitch_variation": 0.14, "min_interval": 0.04, "max_voices": 4},
	&"absorb_material": {"volume_db": -12.0, "pitch_variation": 0.16, "min_interval": 0.05, "max_voices": 4},

	# 炼金：注入、激活、叠加、替换爆发、过期、拒绝、过载、热量预警。
	&"brew_open": {"volume_db": -7.0, "pitch_variation": 0.05, "min_interval": 0.20, "max_voices": 2},
	&"brew_activate": {"volume_db": -4.0, "pitch_variation": 0.04, "min_interval": 0.10, "max_voices": 2},
	&"brew_stack": {"volume_db": -6.0, "pitch_variation": 0.06, "min_interval": 0.08, "max_voices": 2},
	&"brew_burst": {"volume_db": -4.0, "pitch_variation": 0.05, "min_interval": 0.10, "max_voices": 2},
	&"brew_expire": {"volume_db": -8.0, "pitch_variation": 0.05, "min_interval": 0.20, "max_voices": 2},
	&"brew_reject": {"volume_db": -6.0, "pitch_variation": 0.04, "min_interval": 0.15, "max_voices": 1},
	&"brew_overload": {"volume_db": -2.0, "pitch_variation": 0.0, "min_interval": 0.50, "max_voices": 1},
	&"heat_warning": {"volume_db": -12.0, "pitch_variation": 0.05, "min_interval": 0.40, "max_voices": 1},

	# 界面。
	&"wheel_open": {"volume_db": -8.0, "pitch_variation": 0.05, "min_interval": 0.10, "max_voices": 2, "bus": &"UI"},
	&"wheel_close": {"volume_db": -8.0, "pitch_variation": 0.05, "min_interval": 0.10, "max_voices": 2, "bus": &"UI"},
	&"ui_click": {"volume_db": -8.0, "pitch_variation": 0.04, "min_interval": 0.04, "max_voices": 3, "bus": &"UI"},
	&"ui_hover": {"volume_db": -16.0, "pitch_variation": 0.05, "min_interval": 0.06, "max_voices": 2, "bus": &"UI"},
	&"ui_back": {"volume_db": -8.0, "pitch_variation": 0.04, "min_interval": 0.08, "max_voices": 2, "bus": &"UI"},
	&"ui_toggle": {"volume_db": -12.0, "pitch_variation": 0.04, "min_interval": 0.08, "max_voices": 2, "bus": &"UI"},

	# 世界与投掷。
	&"world_ready": {"volume_db": -8.0, "pitch_variation": 0.0, "min_interval": 1.00, "max_voices": 1},
	&"gate_transition": {"volume_db": -8.0, "pitch_variation": 0.05, "min_interval": 0.30, "max_voices": 2},
	&"stone_throw": {"volume_db": -10.0, "pitch_variation": 0.10, "min_interval": 0.08, "max_voices": 3},
	&"stone_land": {"volume_db": -9.0, "pitch_variation": 0.12, "min_interval": 0.06, "max_voices": 3},

	# 灵感光点：小怪轻叮、精英铃、Boss 钟鸣、事件柔铃。
	# 小怪掉得频繁，音高抖动大一点、同时发声上限压到 2，避免连掉时叠成噪音。
	&"inspiration_ding": {"volume_db": -12.0, "pitch_variation": 0.18, "min_interval": 0.03, "max_voices": 2},
	&"inspiration_bell": {"volume_db": -9.0, "pitch_variation": 0.08, "min_interval": 0.05, "max_voices": 3},
	&"inspiration_chime": {"volume_db": -6.0, "pitch_variation": 0.04, "min_interval": 0.20, "max_voices": 2},
	&"inspiration_bell_soft": {"volume_db": -13.0, "pitch_variation": 0.06, "min_interval": 0.06, "max_voices": 2},
	&"inspiration_merge": {"volume_db": -14.0, "pitch_variation": 0.08, "min_interval": 0.12, "max_voices": 1},
	&"inspiration_death": {"volume_db": -5.0, "pitch_variation": 0.03, "min_interval": 0.60, "max_voices": 1},
	&"sage_stone": {"volume_db": -4.0, "pitch_variation": 0.0, "min_interval": 1.00, "max_voices": 1},
}


## 表里登记的全部音效 id；单元测试用它核对素材文件是否齐全。
static func ids() -> Array:
	return SPECS.keys()


static func has(id: StringName) -> bool:
	return SPECS.has(id)


## 取某个音效的完整参数；表里只写需要偏离默认值的项。
static func for_id(id: StringName) -> Dictionary:
	var merged: Dictionary = DEFAULT.duplicate()
	var overrides: Dictionary = SPECS.get(id, {})
	for key: Variant in overrides:
		merged[key] = overrides[key]
	return merged
