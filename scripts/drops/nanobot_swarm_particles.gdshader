shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// One tiny outlined point per original particle, with ordinary world occlusion.
instance uniform float particle_size_pixels : hint_range(1.0, 8.0) = 3.2;

void vertex() {
	POINT_SIZE = particle_size_pixels;
}

void fragment() {
	float radius = length(POINT_COORD * 2.0 - 1.0);
	float antialias = max(fwidth(radius), 0.03);
	float silhouette = 1.0 - smoothstep(0.93 - antialias * 0.5, 0.93 + antialias * 0.5, radius);
	float fill = 1.0 - smoothstep(0.68 - antialias * 0.4, 0.68 + antialias * 0.4, radius);
	vec3 bright_cyan = vec3(0.18, 0.85, 1.0) * mix(vec3(0.85), COLOR.rgb, 0.5) * 1.4;
	ALBEDO = mix(vec3(0.004, 0.012, 0.018), bright_cyan, fill);
	ALPHA = COLOR.a * silhouette;
}
