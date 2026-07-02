class_name WgHash
## Deterministic hashing / seeding core for the new world generator (spec §4.1–4.3).
## All static, all integer math. Every value flowing into generation RNGs comes from here.
extends RefCounted

# Namespace constants (spec §4.1) — the second element of every seed_for parts list.
const NS_WORLD_LAYOUT := 1
const NS_BORDER := 2
const NS_ROOM_GRAPH := 3
const NS_INTERIOR := 4
const NS_POPULATION := 5
const NS_UNIQUE := 6

# SplitMix64 constants written as their two's-complement signed-64 values: GDScript clamps
# any int literal above INT64_MAX, so the raw 0x9E37... hex forms would silently corrupt.
const _GAMMA := -7046029254386353131  # 0x9E3779B97F4A7C15
const _MIX1 := -4658895280553007687   # 0xBF58476D1CE4E5B9
const _MIX2 := -7723592293110705685   # 0x94D049BB133111EB

# u32 range as int, so p=1.0 maps to a threshold (2^32) strictly above any randi() (max 2^32-1)
# and therefore always fires; p=0.0 maps to 0 and never fires.
const _U32_RANGE := 0x100000000


## SplitMix64 finalizer (spec §4.1). GDScript `>>` is an arithmetic shift on signed 64-bit
## ints, so every right shift is masked to stay unsigned — an unmasked shift smears the sign
## bit and silently corrupts the hash. Multiply/add wrap naturally on 64-bit ints.
static func splitmix64(x: int) -> int:
	x = x + _GAMMA
	var z := (x ^ _ushift(x, 30)) * _MIX1
	z = (z ^ _ushift(z, 27)) * _MIX2
	return z ^ _ushift(z, 31)


## Logical (unsigned) right shift for signed 64-bit ints.
static func _ushift(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64 - n)) - 1)


## Derive a seed from an ordered parts list (spec §4.1). Parts[0] is always world_seed,
## parts[1] a namespace constant. config_hash is a parameter for now (Task 2 supplies the
## real one).
static func seed_for(gen_version: int, config_hash: int, parts: Array[int]) -> int:
	var h := splitmix64(gen_version ^ config_hash)
	for p in parts:
		h = splitmix64(h ^ splitmix64(p))
	return h


## The one sanctioned way to make a per-unit RNG (spec §4.2). Godot's RandomNumberGenerator
## is PCG32 internally, which satisfies the spec directly.
static func rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


## True iff the next u32 draw is below the threshold. randi() returns an unsigned 32-bit
## value as a non-negative int, so the plain comparison is correct (spec §4.3.3).
static func chance(rng: RandomNumberGenerator, threshold_u32: int) -> bool:
	return rng.randi() < threshold_u32


## Precompute the integer threshold for a probability p in [0,1] (call at config-load time;
## generation loops never touch floats). Convention: threshold in [0, 2^32]; p=1.0 -> 2^32
## always fires, p=0.0 -> 0 never fires.
static func threshold(p: float) -> int:
	return clampi(int(round(clampf(p, 0.0, 1.0) * float(_U32_RANGE))), 0, _U32_RANGE)


## Fold a byte stream into an accumulator, one splitmix64 step per byte. Deterministic and
## order-sensitive — the basis of CONFIG_HASH (spec §4.4). Not a fast general-purpose hash,
## but config hashing happens once at load.
static func fold_bytes(h: int, bytes: PackedByteArray) -> int:
	for b in bytes:
		h = splitmix64(h ^ b)
	return h


## Fold any Variant by its canonical var_to_bytes() encoding. Used to hash config scalars in a
## fixed, hand-written field order (never rely on property-list order).
static func fold_var(h: int, value: Variant) -> int:
	return fold_bytes(h, var_to_bytes(value))
