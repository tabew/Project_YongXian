extends Node

## 跨场景信号总线：只放需要跨场景广播的事件，避免场景之间互相持有引用。

## 一个新世界准备就绪（种子已确定）。
signal world_ready(seed_value: int)

## 通用提示信息，由 HUD 负责显示。
signal notification(message: String)

## 世界中的噪音（脚步、投掷、爆炸等）：半径内的怪物记为可疑信息并进入搜索。
signal noise_reported(position: Vector2, radius: float, source: Node)

## 队友警报 / 警戒事件：与噪音走同一条感知通道，只是语义更明确。
signal alert_raised(position: Vector2, radius: float, source: Node)
