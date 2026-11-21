# Impeccable design skill

Claude sessions on this repo load the Impeccable skill from `.claude/skills/impeccable/`
(invoke with `/impeccable <command>`, e.g. `/impeccable critique lobby`). It is built for web
frontends, and Big Business is a Godot game, so only part of it applies.

Useful here:
- The design guidance: `critique`, `polish`, `typeset`, `colorize`, `layout`, `bolder`/`quieter`,
  `clarify` (copy), `onboard`, `delight`, `animate`, and `craft-floor.md` (quality floor).
- The native references: `reference/ios.md`, `reference/android.md`, `audit.native.md`,
  `adapt.native.md` (touch targets, safe areas, platform conventions). Treat the game as a
  native mobile app when the skill asks for a platform.
- `init` / `document`: write PRODUCT.md and DESIGN.md for the game's visual direction.

Does not apply (web-only): `live`, `generate`, `shot`, the `detect` HTML/CSS detector and the
`hooks` edit hook (it scans .tsx/.css/.html etc., never .gd/.tscn). Don't turn hooks on.

The `scripts/impeccable` launcher downloads a pinned, checksum-verified engine binary from
the project's GitHub releases on first run into `~/.impeccable/`. If that fails, the skill
falls back to reading PRODUCT.md/DESIGN.md directly. Verify visuals with Godot screenshots
(simulator/emulator) instead of the web screenshot tool.
