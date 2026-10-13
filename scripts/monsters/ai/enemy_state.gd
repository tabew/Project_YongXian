class_name EnemyState
extends RefCounted

## 通用怪物 AI 的四个状态。所有怪物共用这一套状态机，只有配置与攻击实现不同。
##
## 丢失玩家视野后不允许出现"回家"行为：PatrolAnchor 会被改写成怪物当前位置，
## 因此状态集合里不需要 Return / GoHome / Flee。

enum State {
	PATROL,  ## 巡逻：围绕 PatrolAnchor 选可达点、寻路、到达后等待环顾。
	CHASE,   ## 追击：已确认看到玩家，追向玩家当前位置或最后已知位置。
	ATTACK,  ## 攻击：在攻击距离内且可见，面向玩家并按冷却出手。
	SEARCH,  ## 搜索：收到噪音/警报/被攻击等可疑信息，但还没确认玩家位置。
}


static func describe(state: State) -> String:
	match state:
		State.PATROL:
			return "Patrol"
		State.CHASE:
			return "Chase"
		State.ATTACK:
			return "Attack"
		State.SEARCH:
			return "Search"
	return "Unknown"
