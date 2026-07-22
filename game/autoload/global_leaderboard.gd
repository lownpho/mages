extends Node

## The one place the game talks to Talo. Leaderboards are opt-in: everything here
## is a silent no-op until the player logs into an account (title screen), so an
## anonymous player never sees a network error or a login nag. The session token
## is stored by the plugin and restored at boot (`auto_start_session`).

## Talo leaderboard internal name. The score is a property of the ACCOUNT, not of a
## run or a device: the server-side per-enemy kill counts live on our own entry's
## `bestiary` prop and are fetched back on login. Each sync adds only the kills this
## device made since its last sync (see _baseline), so two devices on one account
## sum instead of fighting, and a second account on one device inherits nothing.
## Synced at the session edges: game open / login / game close. Unique mode + a
## monotonic score means resubmitting is always safe.
const LEADERBOARD_KILLS := "kills"

## Per-device sync ledger: which account first claimed the device's anonymous
## kills, and each account's local kill counts as of its last successful sync.
const SYNC_PATH := "user://leaderboard_sync.cfg"

## How long a close-time submit may hold the window open before quitting anyway.
const QUIT_SUBMIT_TIMEOUT := 2.0

var logged_in := false

# The account's server-side kill counts, fetched from our leaderboard entry on the
# first sync after login and carried forward in memory between syncs.
var _server_kills: Dictionary = {}
var _server_loaded := false
var _submitting := false

func _ready() -> void:
	# Not session_found: that fires before the async identify() completes, so the
	# identity isn't usable yet. `identified` fires once it is — on boot restore,
	# login and register alike.
	Talo.players.identified.connect(func(_alias: TaloPlayerAlias) -> void: _on_session_changed(true))
	Talo.player_auth.session_not_found.connect(_on_session_changed.bind(false))
	# In-memory override (settings.cfg is gitignored, so don't trust it): the quit
	# belongs to _quit_after_submit below, not to Talo's close handler.
	Talo.settings.handle_tree_quit = false


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
	await Talo.player_auth.logout()
	_on_session_changed(false)

## One leaderboard page (Talo caps them at 50 entries); null on failure/logged out.
func entries(page: int = 0) -> LeaderboardsAPI.EntriesPage:
	if not logged_in:
		return null
	var options := LeaderboardsAPI.GetEntriesOptions.new()
	options.page = page
	return await Talo.leaderboards.get_entries(LEADERBOARD_KILLS, options)

## The logged-in player's own entry, null when logged out or not on the board.
func my_entry() -> TaloLeaderboardEntry:
	if not logged_in or Talo.current_alias == null:
		return null
	var options := LeaderboardsAPI.GetEntriesOptions.new()
	options.alias_id = Talo.current_alias.id
	var page := await Talo.leaderboards.get_entries(LEADERBOARD_KILLS, options)
	return page.entries[0] if page != null and not page.entries.is_empty() else null

## Sync the account: fetch the server's kill counts (first time per session), add
## this device's kills since its last sync, and push the merged state — total as
## the score, per-enemy breakdown + loadout as entry props. Called on login/session
## restore and on game close, so a player who signs up after playing a while
## appears immediately with everything the device has earned.
func submit_snapshot() -> void:
	if _submitting or Talo.identity_check(false) != OK:
		return
	_submitting = true
	await _submit_merged()
	_submitting = false

func _submit_merged() -> void:
	if not _server_loaded:
		var mine := await my_entry()
		_server_kills = _parse_kills(mine.get_prop("bestiary", "{}")) if mine != null else {}
		_server_loaded = true
	var account: String = Talo.current_player.id
	var local := _local_kills()
	var baseline := _baseline(account, local)
	var merged := _server_kills.duplicate()
	for id in local:
		var delta: int = local[id] - int(baseline.get(id, 0))
		if delta > 0:
			merged[id] = int(merged.get(id, 0)) + delta
	var total := 0
	for id in merged:
		total += int(merged[id])
	var res := await Talo.leaderboards.add_entry(LEADERBOARD_KILLS, total, {
		loadout = _loadout_string(),
		bestiary = JSON.stringify(merged),
	})
	# Only a landed submit advances the ledger; a failed one leaves the delta to be
	# re-counted next sync. (An unchanged score "lands" too — unique mode just
	# doesn't move the entry.)
	if res != null:
		_server_kills = merged
		_save_baseline(account, local)

func _on_session_changed(now_logged_in: bool) -> void:
	logged_in = now_logged_in
	_server_kills = {}
	_server_loaded = false
	GlobalEvent.leaderboard_session_changed.emit(logged_in)
	if logged_in:
		submit_snapshot()

# The device's local kill counts, keyed by plain String for clean JSON round-trips.
func _local_kills() -> Dictionary:
	var out := {}
	for id in GlobalBestiary.roster():
		var kills := GlobalBestiary.kill_count(id)
		if kills > 0:
			out[String(id)] = kills
	return out

func _parse_kills(raw: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw)
	var out := {}
	if parsed is Dictionary:
		for key in parsed:
			out[String(key)] = int(parsed[key])
	return out

# What this device had already credited to `account`: its stored last-sync counts.
# First sync of an account: a virgin device's whole history goes to the claiming
# account (baseline empty); a device already claimed by another account yields
# nothing retroactively (baseline = the current counts).
func _baseline(account: String, local: Dictionary) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(SYNC_PATH)
	if cfg.has_section_key("baselines", account):
		return cfg.get_value("baselines", account)
	return local.duplicate() if cfg.get_value("sync", "claimed", false) else {}

func _save_baseline(account: String, local: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SYNC_PATH)
	cfg.set_value("sync", "claimed", true)
	cfg.set_value("baselines", account, local)
	cfg.save(SYNC_PATH)

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
