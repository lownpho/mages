class_name Hash extends RefCounted
## Deterministic, position-keyed pseudo-randomness — the backbone of streamed world
## generation. `value(seed, x, y, channel)` always returns the same float for the same
## inputs, so a tile's contents can be computed without ever building its neighbours,
## and a discarded chunk rebuilds identically. Uses a self-contained integer bit-mix
## (SplitMix-style), NOT `Array.hash()`, so results don't depend on engine hashing.
##
## `channel` separates independent rolls on the same tile (ground variant vs cover vs
## enemy) so they don't correlate — pass a distinct small int per roll.
##
## The whole class is static + stateless: identical inputs → identical outputs, always.

# 63-bit mask: ANDing with this clears the sign bit, keeping every intermediate
# non-negative so `>>` behaves as a logical shift (GDScript `>>` is arithmetic).
const _M := 0x7FFFFFFFFFFFFFFF

# Distinct odd multipliers per axis so (x,y,channel) scramble independently.
const _PX := 73856093
const _PY := 19349663
const _PC := 83492791
const _MIX := 0x2545F4914F6CDD1D


static func _mix(n: int) -> int:
	n = (n * _MIX) & _M
	n = (n ^ (n >> 29)) & _M
	n = (n * _MIX) & _M
	n = (n ^ (n >> 32)) & _M
	return n


## A stable value in [0, 1) for the given seed/coordinate/channel.
static func value(world_seed: int, x: int, y: int, channel: int = 0) -> float:
	var h := _mix(world_seed & _M)
	h = _mix(h ^ ((x * _PX) & _M))
	h = _mix(h ^ ((y * _PY) & _M))
	h = _mix(h ^ ((channel * _PC) & _M))
	# 24 bits is plenty of precision for placement rolls and divides exactly.
	return float(h & 0xFFFFFF) / float(0x1000000)


## True with probability `p` — one independent coin flip per (tile, channel).
static func chance(world_seed: int, x: int, y: int, channel: int, p: float) -> bool:
	return value(world_seed, x, y, channel) < p


## Deterministically pick one element of `arr` for this (tile, channel).
static func pick(world_seed: int, x: int, y: int, channel: int, arr: Array) -> Variant:
	return arr[int(value(world_seed, x, y, channel) * arr.size()) % arr.size()]


## A stable integer in the inclusive range [lo, hi] for this (tile, channel).
## `value` is in [0, 1), so the product never reaches hi + 1 — every result lands in range.
static func range_i(world_seed: int, x: int, y: int, channel: int, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(value(world_seed, x, y, channel) * (hi - lo + 1))
