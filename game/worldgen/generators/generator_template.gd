class_name RoomGenTemplate
## Template generator (spec §8.2): pick one authored stamp uniformly, apply a uniform
## mirror/rotate variant, place centered. Tiles overlapping PROTECTED are dropped, so a stamp
## can never sever the corridor star.
extends RoomGenBase

@export var stamps: Array[RoomStamp] = []   ## hand-authored layouts; one is picked uniformly
@export var allow_mirror: bool = true
@export var allow_rotate: bool = true


func hash_fold(h: int) -> int:
	h = super.hash_fold(h)
	h = WgHash.fold_var(h, allow_mirror)
	h = WgHash.fold_var(h, allow_rotate)
	for s in stamps:
		if s != null:
			h = s.hash_fold(h)
	return h


func run(grid: PackedByteArray, protected: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator, _spec: RoomSpec) -> void:
	if stamps.is_empty():
		return
	var stamp: RoomStamp = stamps[rng.randi_range(0, stamps.size() - 1)]
	var rots := 4 if allow_rotate else 1
	var mirrors := 2 if allow_mirror else 1
	var variant := rng.randi_range(0, mirrors * rots - 1)
	var mirror := variant >= rots
	var rot := variant % rots

	var sw := stamp.width()
	var sh := stamp.height()
	var cells := stamp.cells()
	var tw := sw if rot % 2 == 0 else sh
	var th := sh if rot % 2 == 0 else sw
	var ox := (w - tw) >> 1
	var oy := (h - th) >> 1
	for sy in sh:
		for sx in sw:
			var c := cells[sy * sw + sx]
			if c == RoomStamp.SKIP:
				continue
			# Mirror horizontally in source space, then rotate 90° CW `rot` times:
			# (x, y) in (cw, ch) -> (ch - 1 - y, x) in (ch, cw).
			var x := (sw - 1 - sx) if mirror else sx
			var y := sy
			var cw := sw
			var ch := sh
			for _k in rot:
				var nx := ch - 1 - y
				y = x
				x = nx
				var t := cw
				cw = ch
				ch = t
			var gx := ox + x
			var gy := oy + y
			if gx < 1 or gy < 1 or gx >= w - 1 or gy >= h - 1:
				continue
			var idx := gy * w + gx
			if protected[idx] == 1:
				continue
			grid[idx] = c
