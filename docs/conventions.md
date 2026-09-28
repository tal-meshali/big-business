# Code conventions

Enforced by `tools/graph_check.py`, which runs on every push (git pre-push hook) and in CI. It builds the code graph with [graphify](https://github.com/Graphify-Labs/graphify) and checks the rules below.

## The dependency graph is a DAG

No file may depend, directly or through others, on a file that depends on it. Cycles fail the check with the files listed.

- Server (TypeScript): graphify parses imports and calls; cross-file edges under `server/src/` are checked. Test files are excluded.
- Client (GDScript, which graphify cannot parse): the checker scans `class_name` references, autoload names from `project.godot`, and `res://` script paths.

## Layers only point downward

Server: `engine` (pure rules, no Nakama) <- `match` (Nakama handler) <- `main.ts` (registration). The engine never imports from match or main; match never imports main.

Client: `scripts/game` and `scripts/net` are the bottom layer and never reference `scripts/ui`; `scripts/ui` may use both; `tests` may use anything.

## Graphify hygiene

- `.graphifyignore` keeps generated and vendored code (node_modules, Godot addons, build output, type stubs) out of the graph.
- Every source must extract cleanly (`failed_sources` empty).
- No code node with more than 60 graph edges (graphify's "god node"). Split the module before it gets there.
- `graphify-out/` is generated and git-ignored; the hook and CI rebuild it. For assistant use, run `graphify update .` after pulling.
- Explain non-obvious decisions with a `// WHY:` or `## WHY:` comment; graphify turns those into explanation nodes.

## Setup

```
pip install graphifyy            # once per machine
git config core.hooksPath .githooks   # once per clone
python3 tools/graph_check.py     # run by hand any time
```

`git push --no-verify` bypasses the hook for emergencies; CI still runs the check.
