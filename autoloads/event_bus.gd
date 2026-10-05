extends Node

## 跨场景信号总线：只放需要跨场景广播的事件，避免场景之间互相持有引用。

## 一个新世界准备就绪（种子已确定）。
signal world_ready(seed_value: int)

## 通用提示信息，由 HUD 负责显示。
signal notification(message: String)
