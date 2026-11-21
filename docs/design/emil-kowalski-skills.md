# Emil Kowalski's design-engineering skills

Vendored from https://github.com/emilkowalski/skills (MIT, Copyright 2026 Emil Kowalski) at
commit 64eb3deb9a5fbfa041faf783e0bc3fd635872e9c, copied unmodified into `.claude/skills/<name>/`
with the LICENSE beside each. They are plain Markdown (no scripts).

Installed: `emil-design-eng` (the core philosophy), `animate`, `choreograph`, `gestures`,
`apple-design`, `review-animations`, `find-animation-opportunities`, `improve-animations`,
`remove-animations`, `animation-vocabulary`, `break-ui`, `learn-taste`.

Left out because they only apply to other stacks: `animate-expo` (React Native), `ask-sonner`
(React toasts), `write-swift`, `pick-ui-library` (npm libraries), `mobile-native` (mobile web
CSS), `animation-performance` (browser compositing), `prototype` (web picker), and `ask-emil`
(a router that mostly points at those).

## Using them in Godot

The examples are CSS / Framer Motion, but the decisions carry over: when to animate, purpose,
easing (ease-out for enters, springs for gestures), durations under ~300 ms for UI, interruption,
stagger order, and press/hover feedback. Translate into Godot with `Tween`
(`set_trans`/`set_ease`, `TRANS_CUBIC`/`EASE_OUT`, `TRANS_SPRING`/`TRANS_BACK`), `AnimationPlayer`,
and `scale`/`modulate`/`position` on Control nodes (set `pivot_offset` for scale origins).
`gestures` maps to card drags with `InputEventScreenDrag`. `break-ui` works for card names,
player names, big coin counts and long localized strings. Skip the web-only parts (CSS
properties, `will-change`, browser devtools).
