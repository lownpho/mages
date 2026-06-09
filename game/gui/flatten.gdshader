shader_type canvas_item;

// Replaces every opaque texel with one flat color, keeping the alpha shape.
// Used for palette-safe icon flashes: the output is exactly the given color,
// never a blend, so it can't leave the game palette.
uniform vec4 flat_color : source_color = vec4(1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(flat_color.rgb, tex.a * flat_color.a);
}
