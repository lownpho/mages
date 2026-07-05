class_name AimAssist

## Shared aim-assist math for anything that flies at a locked target (weapon
## bullets, fireball, future projectiles). All static — never instantiated.

## Nearest member of `group` within `radius_px` of `point`, or null when nothing
## is close enough — aiming at empty space means no lock, so the shot flies
## straight.
static func nearest_in_group(tree: SceneTree, group: StringName, point: Vector2, radius_px: float) -> Node2D:
	var best_d := radius_px * radius_px
	var best: Node2D = null
	for node in tree.get_nodes_in_group(group):
		if node.is_queued_for_deletion():
			continue
		var d: float = point.distance_squared_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best

## One frame of steering: rotate `velocity` toward `target_pos` at up to
## `turn_deg` degrees/second, but only while the target sits inside the
## `cone_deg` assist cone of the current heading, with the turn rate fading to
## zero at the cone edge. A shot aimed deliberately away from the locked target
## is never hijacked, and a projectile that overshoots (target now behind it)
## drops the assist instead of orbiting. Speed is preserved (pure rotation).
static func steer(velocity: Vector2, from: Vector2, target_pos: Vector2, turn_deg: float, cone_deg: float, delta: float) -> Vector2:
	var to_target := velocity.angle_to(from.direction_to(target_pos))
	var cone := deg_to_rad(cone_deg)
	if cone <= 0.0 or absf(to_target) >= cone:
		return velocity
	var fade := 1.0 - absf(to_target) / cone
	var max_turn := deg_to_rad(turn_deg) * fade * delta
	return velocity.rotated(clampf(to_target, -max_turn, max_turn))
