# Additional Lights — a Horizon port

**Additional Lights** is a Minecraft mod. This repository is a **port of it to [Horizon](https://github.com/horizon-rust/horizon)**, the Rust engine for Minecraft Java 26.3. It carries the complete source of the port plus the content files it ships, and installs as a single `.hmod` package.

Upstream: [mgen256/AdditionalLights](https://github.com/mgen256/AdditionalLights) — licence **MIT**.

| | |
|---|---|
| Upstream mod | Additional Lights ([source](https://github.com/mgen256/AdditionalLights)) |
| Ported to | Horizon 0b14f8a, Minecraft Java 26.3, mod API `0.2` |
| Package | `additional_lights.hmod` (install it with the Horizon launcher) |
| Licence | **MIT** — the upstream mod's licence; see [Licence and credit](#licence-and-credit) |

## What this port implements

- **Lamp**: `end_rod` gives `facing` (6) and the support rule (the block
- **Floor torch**: `torch` gives the vanilla support rule and the exact
- **Wall torch**: `wall_torch` gives `facing` (4), the wall support rule and
- **Drops**: lamps and floor torches drop themselves; a wall torch drops its
- **Recipes**: lamps are glowstone over the material → 4; torches are four
- **Tag**: floor and wall torches join
- **Creative tab**: `itemGroup.additional_lights`, icon
- **Lang**: every upstream locale, the 52 named block keys plus the tab title.

## Not yet ported

- **Per-state light is not expressible in a content block.**
- **Declared `waterlogged` on a lamp has no fluid behaviour.** The end rod
- **Lamp collision.** `shapes` replaces outline and collision
- **The floor-torch item does not place the wall form.** Upstream uses
- **Torch particles do not follow `firetype`.** The template's client
- **Deferred: standing torches (24 S + 24 L), fire pits (24 S + 24 L), fire
- **`#minecraft:mineable/pickaxe` and the tool tiers are not added.** Upstream
- **`/recipe give` does not list mod recipes** (pin `RecipeIndex` reads only

## Installing

1. Install the [Horizon launcher](https://github.com/horizon-rust/horizon/releases) (0.2.70 or newer).
2. Add `additional_lights.hmod` to the instance's mods.
3. The package is pinned to a specific Horizon build; the launcher checks that pin.

## Licence and credit

Additional Lights was created by its upstream authors; the code, models and assets in the original mod
remain theirs and are used here under **MIT**. The Rust in this repository is a clean-room
rewrite for Horizon, not a translation of the original source.

- `LICENSE` — the upstream licence text.
- `LICENSE-NOTICE.md` — what this port carries and where it came from.
- The upstream project: https://github.com/mgen256/AdditionalLights

## Technical details

```
horizon-mod.toml   package manifest (id, version, api, [native] pin)
Cargo.toml         the crate; depends on `horizon-mod-api` from the fetched SDK
src/               lib.rs (the one `impl Hooks`), runtime.rs (pure logic + tests), glue
assets/ data/      the content the package ships
tools/             content generators and the e2e scenario
```

- Build: `cargo horizon-mod build` (packages; it does not compile against the game).
- Test: `cargo test`, `cargo clippy --all-targets -- -D warnings`.
- In-game: `ports/tools/launcher-game.sh run additional_lights` in the campaign tree, or install the
  `.hmod` and play; the harness scenario is `tools/e2e.sh`.

This repository is generated from the campaign's port at `ports/additional_lights/`; the port's own
`notes.md` is the full record (decisions, traps, evidence).
