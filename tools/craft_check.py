#!/usr/bin/env python3
"""Craft the Additional Lights shaped recipes in a real crafting table.

Called by tools/e2e.sh with the open game's control socket. Uses the harness's
crafting grid (`ctl screen`: slots 100-108 row-major, result 200), gives the
ingredients, and asserts:

1. `minecraft:glowstone` above `minecraft:stone` -> four
   `additional_lights:al_lamp_stone` (upstream's 1x2 lamp recipe), and the
   crafted stack reaches the inventory;
2. `minecraft:glowstone` above `minecraft:oak_planks` -> four
   `additional_lights:al_lamp_oak_planks` (the material mapping is real);
3. a stick under the glowstone leaves the result empty;
4. four `minecraft:torch` (2x2) with `minecraft:stone` at the bottom-left of
   the 3x3 -> four `additional_lights:al_torch_stone` (upstream's torch
   recipe);
5. four torches with a stick at the bottom-left leave the result empty.

The table is replaced before every case, so a failed/untaken result cannot
leak into the next grid. Exits 1 with the observed result on the first
mismatch.
"""
import json
import subprocess
import sys

# 3x3 grid, row-major slots 100..108 (100,101,102 = top row). The lamp
# pattern is "#" over "X": glowstone at top-left, the material directly below
# it. The torch pattern is a 2x2 of torches with the material at the bottom
# of the left column.
LAMP_TOP = 100
LAMP_BOTTOM = 103
TORCH_SQUARE = [100, 101, 103, 104]
TORCH_MATERIAL = 106


def main():
    sock, ctl, x, y, z = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

    def run(*args):
        out = subprocess.run([ctl, "--socket", sock, *args], text=True, capture_output=True)
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            raise SystemExit(f"ctl {' '.join(args)}: {out.stdout}{out.stderr}")

    def wait(ticks=4):
        run("wait", str(ticks))

    def slots():
        screen = run("screen")
        if "slots" not in screen:
            raise SystemExit(f"no menu is open: {screen}")
        return screen["slots"]

    def find(item):
        for slot in slots():
            if slot.get("item") == item:
                return slot["slot"]
        raise SystemExit(f"missing ingredient {item} in the inventory")

    def result():
        stack = [s for s in slots() if s["slot"] == 200]
        if not stack or not stack[0].get("item"):
            return None
        return stack[0]

    def place(item, targets, mode="left"):
        slot = find(item)
        run("click-slot", str(slot))
        wait(1)
        for target in targets:
            if mode == "right":
                run("click-slot", str(target), "right")
            else:
                run("click-slot", str(target))
            wait(1)
        run("click-slot", str(slot))
        wait(2)

    def setup(items):
        try:
            run("close")
        except SystemExit:
            pass
        wait(5)
        run("setblock", x, y, z, "minecraft:air")
        run("setblock", x, y, z, "minecraft:crafting_table")
        wait(2)
        print("debug tp:", run("command", f"tp @s {float(x) - 0.5} {y} {float(z) + 0.5}"))
        wait(3)
        run("command", "clear @s")
        for item, count in items:
            run("give", item, str(count))
        wait(3)
        wait()
        print("debug interact:", run("interact", x, y, z))
        wait(5)

    failures = []

    def check(label, items, placements, want_item, want_count):
        setup(items)
        for item, targets, mode in placements:
            place(item, targets, mode)
        got = result()
        print(f"{label} ->", json.dumps(got))
        if not got or got.get("item") != want_item or got.get("count") != want_count:
            failures.append(f"{label}: expected {want_count} {want_item}, got {got}")
            return None
        return got

    def empty_control(label, items, placements):
        setup(items)
        for item, targets, mode in placements:
            place(item, targets, mode)
        got = result()
        print(f"{label} ->", json.dumps(got))
        if got is not None:
            failures.append(f"{label}: control crafted {got['item']}")

    # 1. Stone lamp, with the crafted stack reaching the inventory.
    got = check(
        "glowstone + stone",
        [("minecraft:glowstone", 1), ("minecraft:stone", 1)],
        [("minecraft:glowstone", [str(LAMP_TOP)], "left"),
         ("minecraft:stone", [str(LAMP_BOTTOM)], "left")],
        "additional_lights:al_lamp_stone",
        4,
    )
    if got:
        run("click-slot", "200")
        wait(5)
        run("click-slot", "9")
        wait(3)
        made = run("inventory")["counts"].get("additional_lights:al_lamp_stone", 0)
        if made < 4:
            failures.append(f"the crafted lamp reached the inventory as {made}, not 4")

    # 2. Oak lamp: the material really selects the lamp variant.
    check(
        "glowstone + oak planks",
        [("minecraft:glowstone", 1), ("minecraft:oak_planks", 1)],
        [("minecraft:glowstone", [str(LAMP_TOP)], "left"),
         ("minecraft:oak_planks", [str(LAMP_BOTTOM)], "left")],
        "additional_lights:al_lamp_oak_planks",
        4,
    )

    # 3. The lamp recipe's deliberately unmatched control.
    empty_control(
        "glowstone + stick",
        [("minecraft:glowstone", 1), ("minecraft:stick", 1)],
        [("minecraft:glowstone", [str(LAMP_TOP)], "left"),
         ("minecraft:stick", [str(LAMP_BOTTOM)], "left")],
    )

    # 4. Stone torch: four torches in a square and the material at bottom-left.
    check(
        "4 torches + stone",
        [("minecraft:torch", 4), ("minecraft:stone", 1)],
        [("minecraft:torch", [str(slot) for slot in TORCH_SQUARE], "right"),
         ("minecraft:stone", [str(TORCH_MATERIAL)], "right")],
        "additional_lights:al_torch_stone",
        4,
    )

    # 5. The torch recipe's control.
    empty_control(
        "4 torches + stick",
        [("minecraft:torch", 4), ("minecraft:stick", 1)],
        [("minecraft:torch", [str(slot) for slot in TORCH_SQUARE], "right"),
         ("minecraft:stick", [str(TORCH_MATERIAL)], "right")],
    )

    run("close")
    wait(3)
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        raise SystemExit(1)
    print("recipe PASS: the lamp and torch recipes craft 4 each, the material selects the lamp variant, and the stick controls leave the result empty")


if __name__ == "__main__":
    main()
