#!/usr/bin/env python3
"""Generate the Additional Lights content tree from the upstream checkout.

Scope: the 80 plain decorative light blocks of Additional Lights 3.1.4
(`mgen256/AdditionalLights`, branch `26.3`, MIT) — 24 lamps, 28 floor torches
and 28 wall torches. The 96 standing-torch/fire-pit pedestals, the 12 fire
blocks and the two wands are deferred (see ../notes.md).

Assets, recipes, advancements and lang are the upstream mod's own MIT files;
blockstates and block models are the upstream `tools/datagen.py` output. The
Horizon block declarations, loot tables, `washed_away_by_fluids` tag and
creative tab are generated here in the 26.3 formats the pinned loader reads.

Usage:
    python3 tools/gen_content.py --upstream ../_shared/upstream/additional_lights
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "content"
MOD = "additional_lights"

LAMP_LIGHT = 15
TORCH_LIGHT = 14  # content `properties.light` is scalar; default state is normal
FIRE_TYPES = ["normal", "soul", "light"]
LAMP_FACINGS = ["down", "up", "north", "south", "west", "east"]
WALL_FACINGS = ["north", "south", "west", "east"]

# ALLampSpec boxes in 1/16 block units, keyed by facing.
LAMP_BOXES = {
    "down": [5.0, 14.0, 5.0, 11.0, 16.0, 11.0],
    "up": [5.0, 0.0, 5.0, 11.0, 2.0, 11.0],
    "north": [6.0, 7.0, 12.0, 10.0, 13.0, 16.0],
    "south": [6.0, 7.0, 0.0, 10.0, 13.0, 4.0],
    "west": [12.0, 7.0, 6.0, 16.0, 13.0, 10.0],
    "east": [0.0, 7.0, 6.0, 4.0, 13.0, 10.0],
}

LANG_FILES = ["de_de", "en_us", "ja_jp", "ko_kr", "pt_br", "ru_ru", "zh_tw"]


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def copy(src: Path, dst: Path) -> None:
    if not src.is_file():
        raise SystemExit(f"missing upstream file: {src}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def read_scope(upstream: Path) -> tuple[list[str], list[str], list[str]]:
    rows = list(csv.DictReader((upstream / "tools/block_definitions.csv").open(encoding="utf-8")))
    lamps: list[str] = []
    floor: list[str] = []
    wall: list[str] = []
    for row in rows:
        reg = row["reg_name"]
        if reg.startswith("al_wall_torch_"):
            wall.append(reg)
        elif reg.startswith("al_torch_"):
            floor.append(reg)
        elif reg.startswith("al_lamp_"):
            lamps.append(reg)
    if len(lamps) != 24 or len(floor) != 28 or len(wall) != 28:
        raise SystemExit(f"unexpected upstream scope: {len(lamps)}/{len(floor)}/{len(wall)}")
    if [name[len("al_torch_"):] for name in floor] != [name[len("al_wall_torch_"):] for name in wall]:
        raise SystemExit("floor and wall torch materials differ")
    return lamps, floor, wall


def base(reg: str, prefix: str) -> str:
    return reg[len(prefix):]


def generate_datagen(upstream: Path, gen: Path) -> Path:
    if gen.exists():
        shutil.rmtree(gen)
    subprocess.run(
        [sys.executable, str(upstream / "tools/datagen.py"), "--gen-dir", str(gen)],
        check=True,
    )
    return gen / "resources"


def block_declaration(reg: str, kind: str) -> dict:
    if kind == "lamp":
        material = base(reg, "al_lamp_")
        return {
            "template": "minecraft:end_rod",
            "properties": {
                "hardness": 0.0,
                "explosion_resistance": 0.0,
                "light": LAMP_LIGHT,
                "requires_tool": False,
                "map_color": 0,
                "sounds": f"minecraft:{material}",
            },
            "shapes": {
                "property": "facing",
                "values": {
                    facing: [[round(v / 16.0, 6) for v in LAMP_BOXES[facing]]]
                    for facing in LAMP_FACINGS
                },
            },
            "state_properties": {"waterlogged": {"type": "boolean"}},
            "default_state": {"facing": "down", "waterlogged": "false"},
            "item": True,
        }
    material = base(reg, "al_torch_" if kind == "torch" else "al_wall_torch_")
    return {
        "template": "minecraft:torch" if kind == "torch" else "minecraft:wall_torch",
        "properties": {
            "hardness": 0.0,
            "explosion_resistance": 0.0,
            "light": TORCH_LIGHT,
            "requires_tool": False,
            "map_color": 0,
            "sounds": f"minecraft:{material}",
        },
        "state_properties": {
            "firetype": {"type": "enum", "values": FIRE_TYPES},
            "previous_firetype": {"type": "enum", "values": FIRE_TYPES},
        },
        "default_state": {"firetype": "normal", "previous_firetype": "normal"},
        "item": kind == "torch",
    }


def loot_table(item: str) -> dict:
    return {
        "type": "minecraft:block",
        "pools": [
            {
                "condition": {"type": "minecraft:survives_explosion"},
                "entries": [{"type": "minecraft:item", "name": item}],
                "rolls": 1,
            }
        ],
        "random_sequence": f"{MOD}:blocks/{item.split(':', 1)[1]}",
    }


def copy_model_with_parents(
    model_id: str,
    resources: Path,
    common: Path,
    copied: set[str],
    textures: set[str],
) -> None:
    """Copy `additional_lights:<model>` and its parents/textures."""
    if model_id in copied:
        return
    copied.add(model_id)
    rel = model_id.split(":", 1)[1]
    src = common / "assets" / MOD / "models" / f"{rel}.json"
    dst = OUT / "assets" / MOD / "models" / f"{rel}.json"
    if src.is_file():
        copy(src, dst)
    else:
        # A generated model: already copied by the caller, but still read it
        # to resolve its parent and textures.
        if not dst.is_file():
            raise SystemExit(f"missing model {model_id}")
    data = read_json(dst)
    parent = data.get("parent")
    if isinstance(parent, str) and parent.startswith(f"{MOD}:"):
        copy_model_with_parents(parent, resources, common, copied, textures)
    for value in data.get("textures", {}).values():
        if isinstance(value, str) and value.startswith(f"{MOD}:"):
            textures.add(value.split(":", 1)[1])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, default=ROOT.parent / "_shared/upstream/additional_lights")
    parser.add_argument("--gen", type=Path, default=ROOT / "content/target/datagen")
    args = parser.parse_args()
    upstream = args.upstream.resolve()
    common = upstream / "common/src/main/resources"
    lamps, floor, wall = read_scope(upstream)
    resources = generate_datagen(upstream, args.gen)

    for tree in ("assets", "data"):
        shutil.rmtree(OUT / tree, ignore_errors=True)

    all_blocks = [(reg, "lamp") for reg in lamps] + [(reg, "torch") for reg in floor] + [(reg, "wall") for reg in wall]
    items = [reg for reg in lamps + floor]

    # Block declarations and loot tables.
    for reg, kind in all_blocks:
        write_json(OUT / "data" / MOD / "horizon/block" / f"{reg}.json", block_declaration(reg, kind))
        drop = f"{MOD}:{reg}" if kind != "wall" else f"{MOD}:al_torch_{base(reg, 'al_wall_torch_')}"
        write_json(OUT / "data" / MOD / "loot_table/blocks" / f"{reg}.json", loot_table(drop))

    # Assets: blockstates and block models from the upstream datagen.
    copied_models: set[str] = set()
    textures: set[str] = set()
    for reg, _kind in all_blocks:
        copy(resources / "assets" / MOD / "blockstates" / f"{reg}.json",
             OUT / "assets" / MOD / "blockstates" / f"{reg}.json")
    for reg, kind in all_blocks:
        if kind == "lamp":
            names = [f"al_lamp/{reg}", f"al_lamp/al_wall_lamp_{base(reg, 'al_lamp_')}"]
        else:
            prefix = "al_torch_" if kind == "torch" else "al_wall_torch_"
            material = base(reg, prefix)
            names = [
                f"al_torch/{reg}",
                f"al_torch/al_soul_{'wall_' if kind == 'wall' else ''}torch_{material}",
                f"al_torch/al_light_{'wall_' if kind == 'wall' else ''}torch_{material}",
            ]
        for name in names:
            copy(resources / "assets" / MOD / "models/block" / f"{name}.json",
                 OUT / "assets" / MOD / "models/block" / f"{name}.json")
            copy_model_with_parents(f"{MOD}:block/{name}", resources, common, copied_models, textures)

    # Item models for the 24 lamps and 28 floor torches.
    for reg in items:
        copy(resources / "assets" / MOD / "items" / f"{reg}.json",
             OUT / "assets" / MOD / "items" / f"{reg}.json")

    # Mod textures referenced by the copied models (allamp, glass).
    for rel in sorted(textures):
        copy(common / "assets" / MOD / "textures" / f"{rel}.png", OUT / "assets" / MOD / "textures" / f"{rel}.png")
        meta = common / "assets" / MOD / "textures" / f"{rel}.png.mcmeta"
        if meta.is_file():
            copy(meta, OUT / "assets" / MOD / "textures" / f"{rel}.png.mcmeta")

    # Recipes and their recipe-book advancements.
    for reg in lamps:
        copy(common / "data" / MOD / "recipe/al_lamp" / f"{reg}.json",
             OUT / "data" / MOD / "recipe/al_lamp" / f"{reg}.json")
        copy(common / "data" / MOD / "advancement/recipes/materials" / base(reg, "al_lamp_") / "lamp.json",
             OUT / "data" / MOD / "advancement/recipes/materials" / base(reg, "al_lamp_") / "lamp.json")
    for reg in floor:
        copy(common / "data" / MOD / "recipe/al_torch" / f"{reg}.json",
             OUT / "data" / MOD / "recipe/al_torch" / f"{reg}.json")
        copy(common / "data" / MOD / "advancement/recipes/materials" / base(reg, "al_torch_") / "torch.json",
             OUT / "data" / MOD / "advancement/recipes/materials" / base(reg, "al_torch_") / "torch.json")

    # 26.3 physics tag: torches are washed away by fluids.
    write_json(
        OUT / "data/minecraft/tags/block/washed_away_by_fluids.json",
        {"replace": False, "values": [f"{MOD}:{reg}" for reg in floor + wall]},
    )

    # Creative tab: upstream's lamp and floor-torch block items, in registry
    # order; the wall torches have no item upstream.
    write_json(
        OUT / "data" / MOD / "horizon/creative_tab/tab.json",
        {
            "title": "Additional Lights",
            "icon": f"{MOD}:al_torch_oak_planks",
            "items": [f"{MOD}:{reg}" for reg in lamps + floor],
        },
    )

    # Lang: the ported block names and the tab title, in every upstream locale.
    # Upstream has no `block.additional_lights.al_wall_torch_*` keys (335
    # entries, none for the wall forms); the wall torch has no item and is not
    # in the tab, so its name stays the upstream raw key.
    named = lamps + floor
    wanted = {f"block.{MOD}.{reg}" for reg in named}
    wanted.add(f"itemGroup.{MOD}")
    for locale in LANG_FILES:
        src = common / "assets" / MOD / "lang" / f"{locale}.json"
        if not src.is_file():
            continue
        lang = {key: value for key, value in read_json(src).items()
                if key in wanted or key.startswith(f"block.{MOD}.al_wall_torch_")}
        if locale == "en_us":
            missing = wanted - lang.keys()
            if missing:
                raise SystemExit(f"en_us is missing {sorted(missing)[:5]}")
        write_json(OUT / "assets" / MOD / "lang" / f"{locale}.json", lang)

    # Manifest.
    (OUT / "horizon-mod.toml").write_text(
        f"""# Port-owned content mod for Additional Lights 3.1.4 (mgen256/AdditionalLights,
# branch 26.3, MIT): the 24 lamps, 28 floor torches and 28 wall torches. The
# textures, models, recipes, advancements and lang are the upstream mod's own
# MIT assets; see ../LICENSE and ../notes.md.
id = "{MOD}"
name = "Additional Lights"
version = "3.1.4"
description = "Lamps and torches made from vanilla materials"
authors = ["mgen256"]
api = "0.2"
side = "both"
capabilities = ["registries"]
""",
        encoding="utf-8",
    )

    files = sum(1 for p in OUT.rglob("*") if p.is_file())
    print(json.dumps({
        "blocks": len(all_blocks),
        "lamps": len(lamps),
        "floor_torches": len(floor),
        "wall_torches": len(wall),
        "items": len(items),
        "files": files,
        "out": str(OUT),
    }, indent=2))


if __name__ == "__main__":
    main()
