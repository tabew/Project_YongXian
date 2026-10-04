extends Node

## 跨场景信号总线：只放需要跨场景广播的事件，避免场景之间互相持有引用。

## 一张地图生成并铺好之后发出，表现层（HUD 等）据此刷新。
signal map_ready(map: MapData)

## 通用提示信息，由 HUD 负责显示。
signal notification(message: String)
