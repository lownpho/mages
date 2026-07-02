class_name RoomStamp
## A hand-authored tile-class layout for the `template` generator (spec §8.2), written as
## ASCII rows so it stays readable and diffable in the .tres:
##   '.' skip (leave the room tile as-is)   '#' WALL   'B' BLOCKER
##   'd' DECOR_FLOOR                        'f' force FLOOR
## All rows must have equal length.
extends Resource

const SKIP := 255

@export var rows: Array[String] = []

var _cells := PackedByteArray()   # parsed cache


func width() -> int:
	return rows[0].length() if not rows.is_empty() else 0


func height() -> int:
	return rows.size()


func cells() -> PackedByteArray:
	if _cells.is_empty() and not rows.is_empty():
		for r in rows:
			for i in r.length():
				match r.unicode_at(i):
					35:  # '#'
						_cells.append(RoomBuilder.WALL)
					66:  # 'B'
						_cells.append(RoomBuilder.BLOCKER)
					100:  # 'd'
						_cells.append(RoomBuilder.DECOR_FLOOR)
					102:  # 'f'
						_cells.append(RoomBuilder.FLOOR)
					_:
						_cells.append(SKIP)
	return _cells


func hash_fold(h: int) -> int:
	for r in rows:
		h = WgHash.fold_var(h, r)
	return h
