shader_type canvas_item;

// CanvasGroup 合成整个外形，再统一闪红，不改变名字和血条。
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.02, 0.02, 1.0);

void fragment() {
	vec4 body = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (body.a > 0.0001) {
		body.rgb /= body.a;
	}
	body.rgb = mix(body.rgb, flash_color.rgb, hit_flash);
	COLOR *= body;
}
