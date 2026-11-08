#!/usr/bin/env python3
"""Static check of top-level script-relative requires in server modules: every path resolves, and there are no cycles.
The offline specs load modules one at a time, so they cannot catch either. Run from the repo root."""
import os, re, sys

ROOT = "ServerScriptService/Script"
REQUIRE = re.compile(r"^(?:local \w+ = )?require\(script((?:\.\w+)+)\)", re.M)

mods = {}
for folder, _, files in os.walk(ROOT):
    for name in files:
        if name.endswith(".luau") and name != "init.server.luau":
            path = os.path.join(folder, name)
            mod = path[len(ROOT) + 1 : -5]
            mods[mod[:-5] if mod.endswith("/init") else mod] = path

folders = {os.path.relpath(f, ROOT) for f, _, _ in os.walk(ROOT)}
errors, graph = [], {}
for mod, path in mods.items():
    graph[mod] = []
    for chain in REQUIRE.findall(open(path).read()):
        node = mod.split("/")
        escaped = False
        for part in chain[1:].split("."):
            if part == "Parent":
                if not node:
                    escaped = True
                    break
                node = node[:-1]
            else:
                node = node + [part]
        target = "/".join(node)
        if escaped or (target not in mods and target not in folders):
            errors.append(f"{mod}: script{chain} does not resolve")
        elif target in mods:
            graph[mod].append(target)

state, stack, cycles = {}, [], set()
def visit(mod):
    state[mod] = 1
    stack.append(mod)
    for dep in graph[mod]:
        if state.get(dep, 0) == 0:
            visit(dep)
        elif state[dep] == 1:
            cycle = stack[stack.index(dep):]
            start = cycle.index(min(cycle))
            cycles.add(" -> ".join(cycle[start:] + cycle[:start] + [cycle[start]]))
    stack.pop()
    state[mod] = 2

sys.setrecursionlimit(5000)
for mod in mods:
    if state.get(mod, 0) == 0:
        visit(mod)
for line in errors + [f"cycle: {c}" for c in sorted(cycles)]:
    print(line)
print(f"{len(mods)} modules, {len(errors)} bad paths, {len(cycles)} cycles")
sys.exit(1 if errors or cycles else 0)
