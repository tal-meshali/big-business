#!/usr/bin/env python3
"""Dependency-graph conventions check, run before every push and in CI.

1. Builds the code graph with graphify (headless, no LLM) and reads
   graphify-out/graph.json.
2. Server (TypeScript, parsed by graphify): the file-level dependency graph
   must be a DAG, and the layering engine -> match -> main must hold
   (engine never depends on match or main; match never depends on main).
3. Client (GDScript, which graphify does not parse): a class_name / autoload
   / res:// reference scan must also be a DAG, and scripts/game and
   scripts/net must not depend on scripts/ui.
4. Graphify hygiene: no failed sources, and no code node whose degree
   exceeds GOD_NODE_LIMIT (a "god node" in graphify's report).

Exit code 1 on any violation. Use --no-build to reuse an existing graph.json.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAPH = os.path.join(ROOT, "graphify-out", "graph.json")
GOD_NODE_LIMIT = 60
DEP_RELATIONS = {"imports", "imports_from", "re_exports", "calls", "indirect_call", "references", "inherits", "uses", "depends_on"}
SERVER_LAYERS = [("server/src/engine/", 0), ("server/src/match/", 1), ("server/src/main.ts", 2)]
CLIENT_LAYERS = [("client/scripts/game/", 0), ("client/scripts/net/", 0), ("client/scripts/ui/", 1), ("client/tests/", 2)]

problems: list[str] = []
warnings: list[str] = []


def build_graph() -> None:
    cmd = ["graphify", "update", ".", "--no-cluster", "--force"]
    print("$ " + " ".join(cmd))
    res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    tail = (res.stdout + res.stderr).strip().splitlines()[-4:]
    for line in tail:
        print("  " + line)
    if res.returncode != 0:
        problems.append(f"graphify update failed with exit code {res.returncode}")


def find_cycles(edges: dict[str, set[str]]) -> list[list[str]]:
    """Tarjan's SCC; every SCC with >1 node (or a self-loop) is a cycle."""
    index = 0
    stack: list[str] = []
    on_stack: set[str] = set()
    indices: dict[str, int] = {}
    low: dict[str, int] = {}
    cycles: list[list[str]] = []

    def strongconnect(v: str) -> None:
        nonlocal index
        indices[v] = low[v] = index
        index += 1
        stack.append(v)
        on_stack.add(v)
        for w in edges.get(v, ()):
            if w not in indices:
                strongconnect(w)
                low[v] = min(low[v], low[w])
            elif w in on_stack:
                low[v] = min(low[v], indices[w])
        if low[v] == indices[v]:
            comp = []
            while True:
                w = stack.pop()
                on_stack.discard(w)
                comp.append(w)
                if w == v:
                    break
            if len(comp) > 1 or v in edges.get(v, ()):
                cycles.append(sorted(comp))

    sys.setrecursionlimit(10000)
    for v in list(edges):
        if v not in indices:
            strongconnect(v)
    return cycles


def layer_of(path: str, layers: list[tuple[str, int]]) -> int | None:
    for prefix, layer in layers:
        if path.startswith(prefix):
            return layer
    return None


def check_layering(edges: dict[str, set[str]], layers: list[tuple[str, int]], label: str) -> None:
    for src, targets in edges.items():
        ls = layer_of(src, layers)
        if ls is None:
            continue
        for dst in targets:
            ld = layer_of(dst, layers)
            if ld is not None and ld > ls:
                problems.append(f"{label} layering: {src} (layer {ls}) depends on {dst} (layer {ld})")


def check_server(graph: dict) -> None:
    nodes = {n["id"]: n for n in graph.get("nodes", [])}
    file_edges: dict[str, set[str]] = defaultdict(set)
    degree: dict[str, int] = defaultdict(int)
    for e in graph.get("links", graph.get("edges", [])):
        rel = e.get("relation") or e.get("type")
        s, t = nodes.get(e.get("source")), nodes.get(e.get("target"))
        if not s or not t:
            continue
        degree[e["source"]] += 1
        degree[e["target"]] += 1
        sf, tf = s.get("source_file"), t.get("source_file")
        if rel not in DEP_RELATIONS or not sf or not tf or sf == tf:
            continue
        if not (sf.startswith("server/src/") and tf.startswith("server/src/")):
            continue
        if sf.endswith(".test.ts"):
            continue
        file_edges[sf].add(tf)
    for f in list(file_edges):
        for t in file_edges[f]:
            file_edges.setdefault(t, set())
    print(f"server: {len(file_edges)} files, {sum(len(v) for v in file_edges.values())} cross-file dependencies")
    for cyc in find_cycles(file_edges):
        problems.append("server dependency cycle: " + " -> ".join(cyc))
    check_layering(file_edges, SERVER_LAYERS, "server")
    for nid, d in degree.items():
        n = nodes[nid]
        if n.get("source_file", "").startswith("server/src/") and d > GOD_NODE_LIMIT:
            problems.append(f"god node: {n.get('label', nid)} in {n['source_file']} has degree {d} (> {GOD_NODE_LIMIT})")
    failed = graph.get("failed_sources") or []
    if failed:
        problems.append(f"graphify failed to extract {len(failed)} source(s): {failed[:5]}")


def check_client() -> None:
    client = os.path.join(ROOT, "client")
    scripts: dict[str, str] = {}
    for base in ("scripts", "tests"):
        for dirpath, _, files in os.walk(os.path.join(client, base)):
            for f in files:
                if f.endswith(".gd"):
                    full = os.path.join(dirpath, f)
                    rel = os.path.relpath(full, ROOT)
                    with open(full, encoding="utf-8") as fh:
                        scripts[rel] = fh.read()
    class_to_file: dict[str, str] = {}
    for rel, text in scripts.items():
        m = re.search(r"^class_name\s+(\w+)", text, re.M)
        if m:
            class_to_file[m.group(1)] = rel
    # Autoload singletons from project.godot.
    with open(os.path.join(client, "project.godot"), encoding="utf-8") as fh:
        for m in re.finditer(r'^(\w+)="\*?res://([^"]+)"', fh.read(), re.M):
            path = os.path.relpath(os.path.join(client, m.group(2)), ROOT)
            if path in scripts:
                class_to_file[m.group(1)] = path
    edges: dict[str, set[str]] = {rel: set() for rel in scripts}
    for rel, text in scripts.items():
        body = re.sub(r"^class_name\s+\w+.*$", "", text, flags=re.M)
        body = re.sub(r"##.*$|#.*$", "", body, flags=re.M)
        for cls, target in class_to_file.items():
            if target != rel and re.search(rf"\b{cls}\b", body):
                edges[rel].add(target)
        for m in re.finditer(r'res://([\w/.-]+\.gd)', body):
            target = os.path.relpath(os.path.join(client, m.group(1)), ROOT)
            if target in scripts and target != rel:
                edges[rel].add(target)
    print(f"client: {len(scripts)} scripts, {sum(len(v) for v in edges.values())} references")
    for cyc in find_cycles(edges):
        problems.append("client dependency cycle: " + " -> ".join(cyc))
    check_layering(edges, CLIENT_LAYERS, "client")
    for rel in scripts:
        if "/ui/" in rel and not scripts[rel].lstrip().startswith(("class_name", "extends")):
            warnings.append(f"{rel}: should start with class_name or extends")


def main() -> int:
    if "--no-build" not in sys.argv:
        build_graph()
    if not os.path.exists(GRAPH):
        problems.append(f"missing {GRAPH}; run `graphify update . --no-cluster`")
    else:
        with open(GRAPH, encoding="utf-8") as fh:
            graph = json.load(fh)
        print(f"graph: {len(graph.get('nodes', []))} nodes, {len(graph.get('links', graph.get('edges', [])))} edges")
        check_server(graph)
    check_client()
    for w in warnings:
        print("warning: " + w)
    if problems:
        print("\nGRAPH CHECK FAILED")
        for p in problems:
            print(" - " + p)
        return 1
    print("\nGRAPH CHECK OK: dependency graphs are acyclic and layered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
