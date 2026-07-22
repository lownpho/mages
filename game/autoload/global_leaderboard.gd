extends Node

## The one place the game talks to Talo. Everything here is opt-in and a silent
## no-op until the player logs into an account (title screen), so an anonymous
## player never sees a network error or a login nag — and by design logged-out
## play counts for nothing online: the local bestiary UI still fills in, but only
## play while logged in reaches the server. The session token is stored by the
## plugin and restored at boot (`auto_start_session`).
##
## All state is server-authoritative, so there is no local sync ledger:
## - the account's per-enemy kill map is the `bestiary` player prop, loaded with
##   the identify payload, debounce-synced as it grows, and fetched on demand for
##   other players (bestiary_of) — the card interaction both boards share.
## - counters are Talo stats (see STAT_*), advanced by increment tracks; a track
##   lost to a dead network is captured and replayed by the plugin's continuity
##   manager, so tracks are fire-and-forget and never self-retried (that would
##   double count). A landed track returns the server total, which also folds in
##   what other devices contributed.
## - each sortable metric in the UI is its own Talo leaderboard (see LB_*);
##   "sorting" is fetching a different board. The death feed is a non-unique
##   board whose score is the death's unix timestamp: descending = most recent.

## Metric boards (unique mode, descending): score mirrors the account value.
const LB_UNIQUE_KILLS := "unique_kills"  ## distinct enemy types killed (bestiary size)
const LB_DEATHS := "deaths"  ## lifetime deaths — most deaths first, badge of honor
const LB_DAMAGE_RATIO := "damage_ratio"  ## damage dealt / taken, gated (see below)
## Death feed (NON-unique mode, descending): score = unix timestamp, one entry
## per death; props carry killer / biome / loadout / seed / run_seconds so a
## browser can replay the doomed world.
const LB_DEATH_FEED := "death_feed"

## Talo stat internal names — each must be defined in the dashboard before
## anything tracks. The batched ones need a max-change-per-request that clears a
## whole flush window.
const STAT_DEATHS := "deaths"
const STAT_DAMAGE_DEALT := "damage_dealt"
const STAT_DAMAGE_TAKEN := "damage_taken"
const STAT_TOTAL_KILLS := "total_kills"
const STAT_PLAYTIME := "playtime"

## A young account produces absurd ratios (3 dealt, 0 taken), so the ratio board
## only sees players past this much lifetime damage dealt.
const RATIO_MIN_DAMAGE_DEALT := 1000

## Kills, damage and playtime are too chatty for one PUT each, so they accumulate
## locally and flush on this timer and at the session edges (death, logout, quit).
## A crash loses at most one window — acceptable for dev metrics.
const FLUSH_INTERVAL := 60.0

## How long a close-time submit may hold the window open before quitting anyway.
const QUIT_SUBMIT_TIMEOUT := 2.0

var logged_in := false

# The account's kill map (the `bestiary` player prop, parsed). Only ever touched
# while logged in; the identify payload carries the authoritative copy.
var _bestiary: Dictionary = {}

# Server stat values for the metric boards, plus their "known" flags: a value is
# pushed as a score only once a stat fetch or a landed track has confirmed it —
# never guessed, so a failed fetch can't clobber a real score with a zero.
var _deaths := 0
var _deaths_known := false
var _damage_dealt := 0
var _dealt_known := false
var _damage_taken := 0
var _taken_known := false

# Locally accumulated counters awaiting a flush.
var _pending_kills := 0
var _pending_dealt := 0
var _pending_taken := 0
var _pending_playtime := 0.0

var _submitting := false

# Dev-analytics run context (see the Dev analytics section at the bottom).
var _current_biome := &""
var _run_started_ms := 0
var _boss_fights: Dictionary = {}  # CreatureResource path -> fight start msec

func _ready() -> void:
	# Not session_found: that fires before the async identify() completes, so the
	# identity isn't usable yet. `identified` fires once it is — on boot restore,
	# login and register alike.
	Talo.players.identified.connect(func(_alias: TaloPlayerAlias) -> void: _on_session_changed(true))
	Talo.player_auth.session_not_found.connect(_on_session_changed.bind(false))
	# In-memory override (settings.cfg is gitignored, so don't trust it): the quit
	# belongs to _quit_after_submit below, not to Talo's close handler.
	Talo.settings.handle_tree_quit = false
	# Gameplay taps: counters + dev analytics.
	GlobalEvent.world_ready.connect(_on_world_ready)
	GlobalEvent.biome_entered.connect(_on_biome_entered)
	GlobalEvent.player_died.connect(_on_player_died)
	GlobalEvent.creature_died.connect(_on_creature_died)
	GlobalEvent.entity_damaged.connect(_on_entity_damaged)
	GlobalEvent.equipment_changed.connect(_on_equipment_changed)
	GlobalEvent.item_dropped.connect(_on_item_dropped)
	var flush_timer := Timer.new()
	flush_timer.wait_time = FLUSH_INTERVAL
	flush_timer.timeout.connect(_on_flush_tick)
	add_child(flush_timer)
	flush_timer.start()

func _process(delta: float) -> void:
	if logged_in and GameState.in_run():
		_pending_playtime += delta


# Talo's handle_tree_quit is off (settings.cfg): its close handler still flushes
# its own queues, but the actual quit is ours, held until the goodbye snapshot
# lands. The timer caps the hold so a dead network can't wedge the window shut.
# (Web builds never get this notification — there the login/open submits carry it.)
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_after_submit()

func _quit_after_submit() -> void:
	get_tree().create_timer(QUIT_SUBMIT_TIMEOUT).timeout.connect(func() -> void: get_tree().quit())
	await submit_snapshot()
	await Talo.events.flush()
	get_tree().quit()

## The account name to display, empty when logged out.
func username() -> String:
	return Talo.current_alias.identifier if logged_in and Talo.current_alias else ""

## Returns null on success, a TaloPlayerAuthError on failure (code IDENTIFIER_TAKEN /
## IDENTIFIER_PROFANITY are the ones the dialog gives distinct feedback for).
func register(p_username: String, password: String) -> TaloPlayerAuthError:
	var res := await Talo.player_auth.register(p_username, password)
	return res.error

## Returns null on success, a TaloPlayerAuthError on failure. Verification is never
## enabled (accounts are password-only), so verification_required can't happen.
## Success state lands via the `identified` signal, not here.
func login(p_username: String, password: String) -> TaloPlayerAuthError:
	var res := await Talo.player_auth.login(p_username, password)
	return res.error

func logout() -> void:
	await _flush_pending()
	await Talo.player_auth.logout()
	_on_session_changed(false)

## One page of a board (Talo caps them at 50 entries); null on failure/logged out.
func entries(page: int = 0, board: String = LB_UNIQUE_KILLS) -> LeaderboardsAPI.EntriesPage:
	if not logged_in:
		return null
	var options := LeaderboardsAPI.GetEntriesOptions.new()
	options.page = page
	return await Talo.leaderboards.get_entries(board, options)

## The logged-in player's own entry on a board, null when logged out or not on it.
func my_entry(board: String = LB_UNIQUE_KILLS) -> TaloLeaderboardEntry:
	if not logged_in or Talo.current_alias == null:
		return null
	var options := LeaderboardsAPI.GetEntriesOptions.new()
	options.alias_id = Talo.current_alias.id
	var page := await Talo.leaderboards.get_entries(board, options)
	return page.entries[0] if page != null and not page.entries.is_empty() else null

## Another player's bestiary ({enemy_id: kills}) for the card view. Read from
## their unique_kills entry's `bestiary` prop — entry props are readable with
## the plain leaderboard scope, unlike another player's player props. Empty on
## failure or when they've never scored a kill.
func bestiary_of(player_id: String) -> Dictionary:
	var entry := await player_entry(player_id, LB_UNIQUE_KILLS)
	return _parse_kills(entry.get_prop("bestiary", "{}")) if entry != null else {}

## Any player's entry on a board (the card reads their deaths this way), null
## when logged out, on failure, or when they aren't on that board.
func player_entry(player_id: String, board: String) -> TaloLeaderboardEntry:
	if not logged_in:
		return null
	var options := LeaderboardsAPI.GetEntriesOptions.new()
	options.player_id = player_id
	var page := await Talo.leaderboards.get_entries(board, options)
	return page.entries[0] if page != null and not page.entries.is_empty() else null

## Push the account's full snapshot: flush pending counters, sync the bestiary
## prop now (not on the debounce), and mirror every known value onto its board.
## Called on login/session restore, death, and game close.
func submit_snapshot() -> void:
	if _submitting or Talo.identity_check(false) != OK:
		return
	_submitting = true
	if not (_deaths_known and _dealt_known and _taken_known):
		await _fetch_stats()
	await _flush_pending()
	await Talo.players.update()
	await _push_boards()
	_submitting = false

func _on_session_changed(now_logged_in: bool) -> void:
	logged_in = now_logged_in
	_bestiary = {}
	_deaths = 0
	_deaths_known = false
	_damage_dealt = 0
	_dealt_known = false
	_damage_taken = 0
	_taken_known = false
	_pending_kills = 0
	_pending_dealt = 0
	_pending_taken = 0
	_pending_playtime = 0.0
	GlobalEvent.leaderboard_session_changed.emit(logged_in)
	if logged_in:
		_bestiary = _parse_kills(Talo.current_player.get_prop("bestiary", "{}"))
		submit_snapshot()

# An empty list is ambiguous (a brand-new account and a failed request look the
# same), so the known flags stay down and the stat-backed boards go unpushed — a
# landed track raises them with the true server total, and a fresh account joins
# those boards on its first death / first flushed damage anyway.
func _fetch_stats() -> void:
	var stats := await Talo.stats.list_player_stats()
	if stats.is_empty():
		return
	_deaths = 0
	_damage_dealt = 0
	_damage_taken = 0
	for player_stat in stats:
		var value := int(player_stat.value)
		match player_stat.stat.internal_name:
			STAT_DEATHS: _deaths = value
			STAT_DAMAGE_DEALT: _damage_dealt = value
			STAT_DAMAGE_TAKEN: _damage_taken = value
	_deaths_known = true
	_dealt_known = true
	_taken_known = true

# Quiet minutes cost nothing; active ones run a full snapshot, which also
# rewrites the boards' props — keeping browsed cards at most a minute stale.
func _on_flush_tick() -> void:
	if _pending_kills > 0 or _pending_dealt > 0 or _pending_taken > 0 or _pending_playtime >= 1.0:
		submit_snapshot()

# Ship the accumulated counters. Nothing is re-queued on failure (continuity
# replays it; re-adding would double count) — the damage caches advance
# optimistically instead, and a landed track snaps them to the server total.
func _flush_pending() -> void:
	if not logged_in:
		return
	if _pending_kills > 0:
		Talo.stats.track(STAT_TOTAL_KILLS, _pending_kills)
		_pending_kills = 0
	var seconds := floori(_pending_playtime)
	if seconds > 0:
		Talo.stats.track(STAT_PLAYTIME, seconds)
		_pending_playtime -= seconds
	if _pending_dealt > 0:
		var change := _pending_dealt
		_pending_dealt = 0
		var stat := await Talo.stats.track(STAT_DAMAGE_DEALT, change)
		if stat != null:
			_damage_dealt = int(stat.value)
			_dealt_known = true
		else:
			_damage_dealt += change
	if _pending_taken > 0:
		var change := _pending_taken
		_pending_taken = 0
		var stat := await Talo.stats.track(STAT_DAMAGE_TAKEN, change)
		if stat != null:
			_damage_taken = int(stat.value)
			_taken_known = true
		else:
			_damage_taken += change

# Mirror each known account value onto its board. Unknown values (failed stat
# fetch) are skipped rather than clobbered with a guess; empty accounts stay off
# the boards rather than seeding them with zeros.
func _push_boards() -> void:
	if not _bestiary.is_empty():
		await Talo.leaderboards.add_entry(LB_UNIQUE_KILLS, _unique_score(),
				{bestiary = JSON.stringify(_bestiary)})
	if _deaths_known and _deaths > 0:
		await Talo.leaderboards.add_entry(LB_DEATHS, _deaths)
	if _dealt_known and _taken_known and _damage_dealt >= RATIO_MIN_DAMAGE_DEALT:
		await Talo.leaderboards.add_entry(LB_DAMAGE_RATIO,
				float(_damage_dealt) / maxf(float(_damage_taken), 1.0))

# A logged-in kill: grow the account bestiary (the prop debounce-syncs), queue
# the total_kills track, and on a new enemy type push the unique board — the
# only moment that score can move.
func _count_kill(enemy_id: String) -> void:
	if enemy_id.is_empty():
		return
	var new_type := not _bestiary.has(enemy_id)
	_bestiary[enemy_id] = int(_bestiary.get(enemy_id, 0)) + 1
	_pending_kills += 1
	Talo.current_player.set_prop("bestiary", JSON.stringify(_bestiary))
	if new_type:
		Talo.leaderboards.add_entry(LB_UNIQUE_KILLS, _unique_score(),
				{bestiary = JSON.stringify(_bestiary)})

# Unique board score: whole part = distinct enemy types (what the UI shows and
# what primarily ranks), fractional part = total kills, capped under 1 so it can
# never bleed into the next whole type. The fraction breaks ties by total kills
# — and, critically, makes the score move on EVERY kill: Talo only rewrites an
# entry (and its props) when the score changes, so a score that only moved on
# new types froze the card's bestiary prop between them.
func _unique_score() -> float:
	var total := 0.0
	for id in _bestiary:
		total += int(_bestiary[id])
	return _bestiary.size() + minf(total, 999_999.0) / 1_000_000.0

func _parse_kills(raw: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw)
	var out := {}
	if parsed is Dictionary:
		for key in parsed:
			out[String(key)] = int(parsed[key])
	return out

# Spell slot contents in slot order, e.g. "pew_3,,heal_1,..." — empty string for an
# empty slot. Ids are the .tres basenames, the same ids the design data uses.
# Outside a run (login submit at the title) the live inventory is empty, but a saved
# run may still hold the real loadout — peek the save rather than report nothing.
func _loadout_string() -> String:
	var out := PackedStringArray()
	for slot in GlobalInventory.spell_slots.slots:
		out.append(slot.item.resource_path.get_file().get_basename() if slot.item else "")
	if not "".join(out).is_empty():
		return ",".join(out)
	return _saved_loadout_string(out.size())


func _saved_loadout_string(slot_count: int) -> String:
	var out := PackedStringArray()
	var cfg := ConfigFile.new()
	var loaded := cfg.load(GameState.SAVE_PATH) == OK if GameState.has_save() else false
	for i in slot_count:
		var path: String = cfg.get_value("inventory", "spell_%d" % i, "") if loaded else ""
		out.append(path.get_file().get_basename())
	return ",".join(out)


# --- Death handling -----------------------------------------------------------

func _on_player_died(source: Node) -> void:
	if not logged_in:
		return
	# Captured before the first await: the moment this handler yields, player.gd
	# resumes and game_over() wipes the seed, the inventory and the save.
	# (Typed: Talo's typed-dictionary params reject untyped Dictionary variables.)
	var context: Dictionary[String, String] = {
		"killer": _source_enemy_id(source),
		"biome": String(_current_biome),
		"run_seconds": _run_seconds(),
		"loadout": _loadout_string(),
		"seed": str(GameState.active_seed),
	}
	var stat := await Talo.stats.track(STAT_DEATHS)
	if stat != null:
		_deaths = int(stat.value)
		_deaths_known = true
	else:
		# Continuity will land the track eventually; keep counting forward.
		_deaths += 1
	context["deaths"] = str(_deaths)
	# One feed entry per death: timestamp score sorts the feed by recency.
	var feed_props: Dictionary[String, Variant] = {}
	feed_props.assign(context)
	await Talo.leaderboards.add_entry(LB_DEATH_FEED, Time.get_unix_time_from_system(), feed_props)
	_track("player_died", context)
	# Death is a session edge like login/close: refresh the boards and don't
	# leave the death event sitting in the queue.
	submit_snapshot()
	Talo.events.flush()


# --- Dev analytics ------------------------------------------------------------
# Gameplay events shipped through Talo's events API for balance/design reading,
# never shown to players. Same opt-in as the board: _track no-ops while logged
# out, so an anonymous player sends nothing. The plugin batches and flushes.

func _track(event: String, props: Dictionary[String, String] = {}) -> void:
	if logged_in:
		Talo.events.track(event, props)

func _on_world_ready(_streamer: WorldStreamer) -> void:
	_run_started_ms = Time.get_ticks_msec()
	_current_biome = &""
	_boss_fights.clear()
	# fresh_start is still set here — world.gd consumes it after emitting world_ready.
	_track("run_started", {
		"seed": str(GameState.active_seed),
		"fresh": str(GameState.fresh_start),
	})

func _on_biome_entered(biome_id: StringName) -> void:
	_current_biome = biome_id
	_track("biome_entered", {"biome": String(biome_id), "run_seconds": _run_seconds()})

# Damage totals for the ratio: hits on real enemies count as dealt (a minion's
# damage is the player's), hits on the player as taken; summons (no data) are
# neither. Doubles as the boss-fight detector: the first landed hit on a boss
# opens its fight window, its death (below) closes it.
func _on_entity_damaged(victim: Node, amount: int, _source: Node) -> void:
	if victim is Creature:
		if victim.data == null:
			return
		if logged_in:
			_pending_dealt += amount
		if victim.data.rarity == CreatureResource.Rarity.BOSS:
			var key: String = victim.data.resource_path
			if not _boss_fights.has(key):
				_boss_fights[key] = Time.get_ticks_msec()
				_track("boss_started", {"boss": _enemy_id_in_path(key), "run_seconds": _run_seconds()})
	elif logged_in:
		_pending_taken += amount

func _on_creature_died(data: CreatureResource, _position: Vector2) -> void:
	if data == null:
		return
	if logged_in:
		_count_kill(_enemy_id_in_path(data.resource_path))
	if data.rarity != CreatureResource.Rarity.BOSS:
		return
	var started: int = _boss_fights.get(data.resource_path, Time.get_ticks_msec())
	_boss_fights.erase(data.resource_path)
	_track("boss_won", {
		"boss": _enemy_id_in_path(data.resource_path),
		"fight_seconds": str((Time.get_ticks_msec() - started) / 1000),
		"run_seconds": _run_seconds(),
	})

# Only mid-run choices are interesting; the Continue restore and new_game reset
# fire the same signals from the title and are gated out by in_run().
func _on_equipment_changed(slot: GlobalInventory.Slot) -> void:
	if slot.item != null and GameState.in_run():
		_track("spell_equipped", {"spell": slot.item.resource_path.get_file().get_basename()})

func _on_item_dropped(item: ItemResource) -> void:
	if GameState.in_run():
		_track("spell_dropped", {"spell": item.resource_path.get_file().get_basename()})

func _run_seconds() -> String:
	return str((Time.get_ticks_msec() - _run_started_ms) / 1000)

# characters/enemies/<id>/... — the same folder-name id everything else uses.
func _enemy_id_in_path(path: String) -> String:
	var parts := path.split("/")
	var i := parts.find("enemies")
	return parts[i + 1] if i >= 0 and i + 1 < parts.size() else ""

# Best-effort killer attribution: enemy bullets carry a bespoke BulletResource
# authored under the enemy's folder, so its path names the enemy. Anything else
# (a DamageZone blast has no attribution yet) reports empty.
func _source_enemy_id(source: Node) -> String:
	if source is BaseBullet and source.data != null:
		return _enemy_id_in_path(source.data.resource_path)
	return ""
