shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;

// x: charge, y: pause-aware attack age, z: release intensity, w: shape/style.
// One shared material; each attack supplies its own small instance parameter.
instance uniform vec4 field_state = vec4(0.0);

void fragment() {
	float charge = field_state.x;
	float burst = field_state.z;
	float pulse = 0.5 + 0.5 * sin(UV.x * 19.0 - field_state.y * (3.0 + charge * 9.0));
	float electricity = smoothstep(0.58, 0.94, pulse);
	float boundary = 1.0 - UV.y;
	float strength = mix((0.06 + charge * 0.64) * electricity,
		0.3 + charge * 0.5 + electricity * 0.12, boundary);
	vec3 tint = mix(vec3(0.28, 0.67, 1.0), vec3(0.4, 0.87, 1.0),
		step(0.5, field_state.w));
	if (field_state.w > 1.5) {
		tint = vec3(0.56, 0.72, 1.0); // Capture field or attached link.
		// Broken, flowing bands distinguish capture from damaging fields.
		strength *= 0.45 + 0.55 * step(0.3, fract(UV.x * 6.0 - field_state.y));
	}
	if (field_state.w > 2.5) {
		tint = vec3(0.32, 0.55, 0.76); // Harmless relocation diamonds.
	}
	// Fully faded effects are hidden by their owner rather than rendered at zero.
	float released = sign(burst);
	float flash = max(burst, 0.0);
	strength = mix(strength, flash, released);
	ALBEDO = mix(tint, vec3(0.87, 0.97, 1.0), flash);
	EMISSION = ALBEDO * (0.18 + flash * 0.65);
	ALPHA = clamp(strength, 0.0, 1.0);
}
