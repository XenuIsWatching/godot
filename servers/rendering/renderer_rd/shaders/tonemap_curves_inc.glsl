// Tonemapping curves with the parameters passed in, so a scene shader can apply
// them when it draws straight into the LDR render target and the tonemap pass is
// skipped. Bodies match tonemap.glsl / tonemap_mobile.glsl; p_params is what
// RendererEnvironmentStorage::environment_get_tonemap_parameters computed for
// the tonemapper in use, p_output_max is the target's maximum value (1.0 for SDR).

vec3 tmc_reinhard(vec3 color, vec4 p_params, float p_output_max) {
	float white_squared = p_params.x;
	return color * (1.0f + color / white_squared) / (1.0f + color / p_output_max);
}

vec3 tmc_filmic(vec3 color, vec4 p_params) {
	const float exposure_bias = 2.0f;
	const float A = 0.22f * exposure_bias * exposure_bias;
	const float B = 0.30f * exposure_bias;
	const float C = 0.10f;
	const float D = 0.20f;
	const float E = 0.01f;
	const float F = 0.30f;

	vec3 color_tonemapped = ((color * (A * color + C * B) + D * E) / (color * (A * color + B) + D * F)) - E / F;

	return color_tonemapped / p_params.x;
}

vec3 tmc_aces(vec3 color, vec4 p_params) {
	const float exposure_bias = 1.8f;
	const float A = 0.0245786f;
	const float B = 0.000090537f;
	const float C = 0.983729f;
	const float D = 0.432951f;
	const float E = 0.238081f;

	const mat3 rgb_to_rrt = mat3(
			vec3(0.59719f * exposure_bias, 0.35458f * exposure_bias, 0.04823f * exposure_bias),
			vec3(0.07600f * exposure_bias, 0.90834f * exposure_bias, 0.01566f * exposure_bias),
			vec3(0.02840f * exposure_bias, 0.13383f * exposure_bias, 0.83777f * exposure_bias));

	const mat3 odt_to_rgb = mat3(
			vec3(1.60475f, -0.53108f, -0.07367f),
			vec3(-0.10208f, 1.10813f, -0.00605f),
			vec3(-0.00327f, -0.07276f, 1.07602f));

	color *= rgb_to_rrt;
	vec3 color_tonemapped = (color * (color + A) - B) / (color * (C * color + D) + E);
	color_tonemapped *= odt_to_rgb;

	return color_tonemapped / p_params.x;
}

vec3 tmc_allenwp_curve(vec3 x, vec4 p_params, float p_output_max) {
	const float awp_crossover_point = 0.18;
	const float awp_shoulder_max = p_output_max - awp_crossover_point;

	float awp_contrast = p_params.x;
	float awp_toe_a = p_params.y;
	float awp_slope = p_params.z;
	float awp_w = p_params.w;

	vec3 s = x - awp_crossover_point;
	vec3 slope_s = awp_slope * s;
	s = slope_s * (1.0 + s / awp_w) / (1.0 + (slope_s / awp_shoulder_max));
	s += awp_crossover_point;

	vec3 t = pow(x, vec3(awp_contrast));
	t = t / (t + awp_toe_a);

	return mix(s, t, lessThan(x, vec3(awp_crossover_point)));
}

vec3 tmc_agx(vec3 color, vec4 p_params, float p_output_max) {
	const mat3 rec709_to_rec2020_agx_inset_matrix = mat3(
			0.544814746488245, 0.140416948464053, 0.0888104196149096,
			0.373787398372697, 0.754137554567394, 0.178871756420858,
			0.0813978551390581, 0.105445496968552, 0.732317823964232);

	const mat3 agx_outset_rec2020_to_rec709_matrix = mat3(
			1.96488741169489, -0.299313364904742, -0.164352742528393,
			-0.855988495690215, 1.32639796461980, -0.238183969428088,
			-0.108898916004672, -0.0270845997150571, 1.40253671195648);

	color = rec709_to_rec2020_agx_inset_matrix * color;
	color = tmc_allenwp_curve(color, p_params, p_output_max);
	color = min(vec3(p_output_max), color);
	color = agx_outset_rec2020_to_rec709_matrix * color;
	return color;
}

vec3 tmc_linear_to_srgb(vec3 color) {
	const vec3 a = vec3(0.055f);
	return mix((vec3(1.0f) + a) * pow(color.rgb, vec3(1.0f / 2.4f)) - a, 12.92f * color.rgb, lessThan(color.rgb, vec3(0.0031308f)));
}

// p_mode is RenderingServer::EnvironmentToneMapper: 0 linear, 1 reinhard, 2 filmic, 3 aces, 4 agx.
vec3 tmc_apply(vec3 color, uint p_mode, vec4 p_params, float p_output_max) {
	if (p_mode == 0u) {
		return color;
	}
	color = max(vec3(0.0), color);
	if (p_mode == 1u) {
		return tmc_reinhard(color, p_params, p_output_max);
	} else if (p_mode == 2u) {
		return tmc_filmic(color, p_params);
	} else if (p_mode == 3u) {
		return tmc_aces(color, p_params);
	}
	return tmc_agx(color, p_params, p_output_max);
}
