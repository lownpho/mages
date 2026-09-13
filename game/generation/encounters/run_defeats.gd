class_name RunDefeats
extends RefCounted
## The Run's in-memory record of generated enemies that died, by member key. Fixed-encounter members
## (Rares, Minibosses, Bosses and their escorts) stay defeated for the Run. An ordinary member keeps
## the play time it died at; once the respawn delay has passed it returns the next time its chunk
## streams in, which clears the entry. Play time only advances while the World runs, so a paused
## panel or time away from the game never brings anyone back.

## Seconds of play in this Run.
var play_time := 0.0
## Fixed-encounter member keys.
var defeated: Dictionary[String, bool] = {}
## Ordinary member key -> play time of its death.
var deaths: Dictionary[String, float] = {}


func record_death(member: EncounterMember) -> void:
	if member.fixed:
		defeated[member.key] = true
	else:
		deaths[member.key] = play_time


## Whether a member may spawn now. Only a chunk streaming in (streamed_in) can bring back an
## ordinary member whose delay has passed, and doing so forgets its death.
func admit(member: EncounterMember, respawn_delay: float, streamed_in: bool) -> bool:
	if defeated.has(member.key):
		return false
	if not deaths.has(member.key):
		return true
	if not streamed_in or play_time - deaths[member.key] < respawn_delay:
		return false
	deaths.erase(member.key)
	return true
