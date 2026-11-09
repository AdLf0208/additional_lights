# Licence notice — Additional Lights

This port carries the original mod's assets and data, and rewrites its behaviour
in Rust (or, for a data-tier port, declares its blocks from the same data). The
original licence and copyright notices are reproduced verbatim in
[LICENSE](LICENSE).

## Where the licence was read

- The pack jar `additional_lights-neoforge-1.21-2.1.10.jar` (kept at
  `licence-cache/`) declares `license="MIT License"` in
  `META-INF/neoforge.mods.toml` and carries no licence file.
- The full MIT text and the copyright line `Copyright (c) 2021 mgen256` come
  from the upstream repository's `LICENSE.txt`
  (<https://github.com/mgen256/AdditionalLights>), read for this port.

## The port

- Original: Additional Lights 3.1.4 by mgen256 — MIT.
- Licence: **MIT**
- Port to Horizon by AdLf0208: the Rust runtime, the Horizon declarations and the
  build/verification tooling in this repository.
- No Mojang file is included. The carried files are the mod's own assets and
  data; `data/minecraft/tags/…` files only add this mod's ids to vanilla tags.
