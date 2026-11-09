# Additional Lights — Horizon port

A port of [Additional Lights](https://github.com/mgen256/AdditionalLights) by
mgen256 for Horizon. This slice carries the 80 plain decorative light blocks —
24 lamps (light 15), 28 floor torches (light 14) and 28 wall torches (light 14)
— with their materials, shapes, recipes and drops, 1,548 block states in all.

- Place lamps and torches like their vanilla templates; they keep the upstream
  light levels, including the soul variants' dimmer light.
- Every block drops itself and is craftable from the mod's own recipes.

The standing-torch and fire-pit pedestals, the fire blocks and the two wands are
later slices. MIT — original copyright and licence notices are kept in the port
repository; see LICENSE and LICENSE-NOTICE.md there.

**Original:** [Additional Lights](https://github.com/mgen256/AdditionalLights) 3.1.4 (26.3 branch) by
mgen256, **MIT**. The original
copyright and licence notices are kept in [LICENSE](LICENSE), and
[LICENSE-NOTICE.md](LICENSE-NOTICE.md) records where each was read from.

**Horizon:** a port for [Horizon](https://github.com/horizon-rust/horizon), Minecraft:
Java Edition 26.3 rewritten in Rust. The exact Horizon and horizon-mixins
revisions this port builds against are pinned in `compatibility.json`.

## Install

1. Take `additional_lights.hmod` from this repository (or build it below).
2. Put it in the game folder's `horizon-mods` folder — the game folder is the one
   holding `options.txt`.
3. Mods are off by default: enable this one in the game's mod list.

To try it without installing, start the game with
`--dev-mod additional_lights.hmod`.

## Build

This is a content-only mod: `content/horizon-mod.toml` plus `assets/` and
`data/`.

```sh
cd content && cargo horizon-mod build    # packs content/ into the .hmod and checks it
```

`cargo-horizon-mod` comes from the Horizon repository
(`cargo install --git https://github.com/horizon-rust/horizon cargo-horizon-mod`).
`tools/e2e.sh` is the in-game harness and expects a campaign checkout
(`$CAMPAIGN_ROOT`) with the prepared 26.3 resources (`$HORIZON_RES`, default
`.local/horizon-client/26.3`).

## Layout

`content/` is the shipped `.hmod` and its sources; `mixins/additional_lights/` holds the declarations; `tools/` generates the content and runs the harness.

This is an unofficial port: Horizon is not affiliated with the original author.
The licence above is the original's and travels with every copy; see
[LICENSE](LICENSE) and [LICENSE-NOTICE.md](LICENSE-NOTICE.md).
