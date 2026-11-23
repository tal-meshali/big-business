class_name Leveling
## Level thresholds, for the XP bars in the lobby and on the profile.
## Must match xpForLevel in server/src/match/progression.ts: the server
## awards XP and decides the level; the client only draws the bar.


## XP at which `level` starts.
static func xp_for_level(level: int) -> int:
	var n := maxi(1, level) - 1
	return 50 * n * n


## [XP where `level` starts, XP where the next one starts].
static func span(level: int) -> Vector2i:
	return Vector2i(xp_for_level(level), xp_for_level(maxi(1, level) + 1))
