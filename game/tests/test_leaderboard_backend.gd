extends Node

## LIVE-backend smoke test for GlobalLeaderboard (needs network + the local
## addons/talo/settings.cfg). Logs into a fixed dev account (registering it on
## first ever run), fakes a short life (kills, damage, a death), then reads
## every board back and checks the deltas against the pre-run baseline — so the
## test is rerunnable without spamming accounts (registration is rate-limited).
## ALWAYS run with an isolated user dir so it can't touch a real session/save:
##   XDG_DATA_HOME=/tmp/talo_test godot --headless --path game res://tests/test_leaderboard_backend.tscn

const USERNAME := "cctest_smoke"
const PASSWORD := "test-password-1"

var _fails := 0

func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS: " + what)
	else:
		_fails += 1
		print("FAIL: " + what)

func _ready() -> void:
	await _run()
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit()

func _run() -> void:
	var err := await GlobalLeaderboard.login(USERNAME, PASSWORD)
	if err != null and err.code == TaloPlayerAuthError.ErrorCode.INVALID_CREDENTIALS:
		err = await GlobalLeaderboard.register(USERNAME, PASSWORD)
	if err != null:
		_check(false, "login/register: %s" % err.message)
		return
	# `identified` lands async after login resolves; wait for the flag.
	for _i in 50:
		if GlobalLeaderboard.logged_in:
			break
		await get_tree().create_timer(0.1).timeout
	_check(GlobalLeaderboard.logged_in, "logged in")
	if not GlobalLeaderboard.logged_in:
		return
	# Let the login snapshot settle, then take the baseline.
	await get_tree().create_timer(1.5).timeout
	var me: String = Talo.current_player.id
	var b0 := await GlobalLeaderboard.bestiary_of(me)
	var deaths_entry := await GlobalLeaderboard.my_entry(GlobalLeaderboard.LB_DEATHS)
	var deaths0 := int(deaths_entry.score) if deaths_entry != null else 0

	# Fake a short life: 3 sproutlings, 1 wasp, 1500/500 damage, one death.
	var sprout: CreatureResource = load("res://characters/enemies/sproutling/sproutling_data.tres")
	var wasp: CreatureResource = load("res://characters/enemies/wasp/wasp_data.tres")
	for _i in 3:
		GlobalEvent.creature_died.emit(sprout, Vector2.ZERO)
	GlobalEvent.creature_died.emit(wasp, Vector2.ZERO)
	GlobalLeaderboard._pending_dealt = 1500
	GlobalLeaderboard._pending_taken = 500
	var killer := Node.new()
	add_child(killer)
	GlobalEvent.player_died.emit(killer)
	# The death handler chains stat tracks, a feed entry and a full snapshot.
	await get_tree().create_timer(5.0).timeout

	var expected := b0.duplicate()
	expected["sproutling"] = int(expected.get("sproutling", 0)) + 3
	expected["wasp"] = int(expected.get("wasp", 0)) + 1

	var mine := await GlobalLeaderboard.my_entry(GlobalLeaderboard.LB_UNIQUE_KILLS)
	_check(mine != null, "unique_kills entry exists")
	if mine != null:
		_check(int(mine.score) == expected.size(),
				"unique_kills score == %d (got %d)" % [expected.size(), int(mine.score)])

	var deaths := await GlobalLeaderboard.my_entry(GlobalLeaderboard.LB_DEATHS)
	_check(deaths != null, "deaths entry exists")
	if deaths != null:
		_check(int(deaths.score) == deaths0 + 1,
				"deaths score == %d (got %d)" % [deaths0 + 1, int(deaths.score)])

	var ratio := await GlobalLeaderboard.my_entry(GlobalLeaderboard.LB_DAMAGE_RATIO)
	_check(ratio != null and ratio.score > 0.0, "damage_ratio entry exists")

	var feed := await GlobalLeaderboard.entries(0, GlobalLeaderboard.LB_DEATH_FEED)
	var ours: Array = [] if feed == null else feed.entries.filter(
			func(e: TaloLeaderboardEntry) -> bool: return e.player_alias.identifier == USERNAME)
	_check(not ours.is_empty(), "death feed entry present")
	if not ours.is_empty():
		var newest: TaloLeaderboardEntry = ours.front()
		_check(newest.get_prop("loadout", "x") != "x", "feed entry carries loadout prop")
		_check(newest.get_prop("seed", "") != "", "feed entry carries seed prop")

	var bestiary := await GlobalLeaderboard.bestiary_of(me)
	_check(int(bestiary.get("sproutling", 0)) == int(expected["sproutling"]) \
			and int(bestiary.get("wasp", 0)) == int(expected["wasp"]),
			"bestiary_of reads back the new counts (got %s)" % JSON.stringify(bestiary))

	# A repeat kill doesn't move the unique score — the entry prop must STILL
	# refresh on the next snapshot, or cards freeze at the last new-type kill.
	GlobalEvent.creature_died.emit(sprout, Vector2.ZERO)
	await GlobalLeaderboard.submit_snapshot()
	await get_tree().create_timer(2.0).timeout
	var bestiary2 := await GlobalLeaderboard.bestiary_of(me)
	_check(int(bestiary2.get("sproutling", 0)) == int(expected["sproutling"]) + 1,
			"unchanged-score push refreshes bestiary prop (got %s)" % JSON.stringify(bestiary2))
