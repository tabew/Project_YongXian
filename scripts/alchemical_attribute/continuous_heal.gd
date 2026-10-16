extends AlchemicalData

class_name ContinuousHeal

## 持续回复：先回一小口，再挂一段按秒回复的尾巴。
const INSTANT_RATIO: float = 0.10
const PER_SECOND_RATIO: float = 0.04
const DURATION_SECONDS: float = 5.0


func use_effect(object:Node) -> void:
	if object == null or not object.has_method("heal"):
		return
	var maximum: float = 0.0
	if "max_health" in object:
		maximum = float(object.get("max_health"))
	if maximum <= 0.0:
		return
	object.call("heal", maximum * INSTANT_RATIO)
	if object.has_method("add_regeneration"):
		object.call("add_regeneration", maximum * PER_SECOND_RATIO, DURATION_SECONDS)