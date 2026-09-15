class_name WorldHash
## Deterministic hashing / seeding core for the World generator.
## All static, all integer math. Every value flowing into generation RNGs comes from here.
extends RefCounted

# Namespaces, the second argument of unit_seed: one per kind of generated unit.
const NS_MACRO_PATH := 101
const NS_ZONE_ORDER := 102
const NS_ATTACHMENTS := 103
const NS_SET_PIECES := 104
const NS_CELL_GRAPH := 105
const NS_PORTS := 106
const NS_PASSAGES := 107
const NS_WARP := 108
const NS_ROLES := 109
const NS_SITES := 110
const NS_ROCKS := 111
const NS_SPINE := 112
const NS_DECORATION := 113
const NS_ENCOUNTERS := 114
const NS_MEMBERS := 115
const NS_LATTICE := 116

# SplitMix64 constants written as their two's-complement signed-64 values: GDScript clamps
# any int literal above INT64_MAX, so the raw 0x9E37... hex forms would silently corrupt.
const _GAMMA := -7046029254386353131  # 0x9E3779B97F4A7C15
const _MIX1 := -4658895280553007687   # 0xBF58476D1CE4E5B9
const _MIX2 := -7723592293110705685   # 0x94D049BB133111EB
# Masks keeping the low 64 - n bits after an arithmetic right shift by n (30, 27, 31).
const _LOW_34 := (1 << 34) - 1
const _LOW_37 := (1 << 37) - 1
const _LOW_33 := (1 << 33) - 1

# u32 range as int, so p=1.0 maps to a threshold (2^32) strictly above any randi() (max 2^32-1)
# and therefore always fires; p=0.0 maps to 0 and never fires.
const _U32_RANGE := 0x100000000


## SplitMix64 finalizer. GDScript `>>` is an arithmetic shift on signed 64-bit
## ints, so every right shift is masked to stay unsigned — an unmasked shift smears the sign
## bit and silently corrupts the hash. Multiply/add wrap naturally on 64-bit ints.
static func splitmix64(x: int) -> int:
	# _ushift inlined: streaming hashes every tile, and the calls cost more than the mixing.
	x = x + _GAMMA
	var z := (x ^ ((x >> 30) & _LOW_34)) * _MIX1
	z = (z ^ ((z >> 27) & _LOW_37)) * _MIX2
	return z ^ ((z >> 31) & _LOW_33)


## Logical (unsigned) right shift for signed 64-bit ints.
static func _ushift(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64 - n)) - 1)


## A generated unit's seed in the World generator, from the World seed, a namespace and the
## unit's place-derived key ("glade", "3,2/5"). No content hash or version goes in, and no unit's
## seed depends on another unit's draws.
static func unit_seed(world_seed: int, namespace_id: int, key: String) -> int:
	var h := splitmix64(splitmix64(world_seed) ^ namespace_id)
	return splitmix64(fold_bytes(h, key.to_utf8_buffer()))


## The one sanctioned way to make a per-unit RNG. Godot's RandomNumberGenerator
## is PCG32 internally, which gives the determinism we need directly.
static func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Precompute the integer threshold for a probability p in [0,1] (call at config-load time;
## generation loops never touch floats). Convention: threshold in [0, 2^32]; p=1.0 -> 2^32
## always fires, p=0.0 -> 0 never fires.
static func threshold(p: float) -> int:
	return clampi(int(round(clampf(p, 0.0, 1.0) * float(_U32_RANGE))), 0, _U32_RANGE)


## Fold a byte stream into an accumulator, one splitmix64 step per byte. Deterministic and
## order-sensitive — how unit_seed folds in a unit's place key. Not a fast general-purpose hash,
## but keys are short.
static func fold_bytes(h: int, bytes: PackedByteArray) -> int:
	for b in bytes:
		h = splitmix64(h ^ b)
	return h
