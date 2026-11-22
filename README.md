# 🌕 Moon Mapgen for Luanti

**Walk the real Moon in Luanti.** Generate an entire playable lunar world sculpted from authentic **NASA LOLA** spacecraft elevation data and shaded with **NASA LROC** albedo imagery — complete with 1/6th Earth gravity, an Earthrise skybox, and instant teleportation to **8,996 named craters, maria, and Apollo landing sites**.

![Luanti 5.2 – 5.18+](https://img.shields.io/badge/Luanti-5.2%20--%205.18%2B-blue)
![Game Independent](https://img.shields.io/badge/Games-Any%20Luanti%20Game-brightgreen)
![Sandbox Safe](https://img.shields.io/badge/Mod%20Security-Sandbox%20Safe-success)
![Code License: MIT](https://img.shields.io/badge/Code%20License-MIT-lightgrey)

> **Modernized Luanti Fork** — This repository is a modernized fork of [arpruss/moon-mapgen-minetest](https://github.com/arpruss/moon-mapgen-minetest), originally created by **Alexander R. Pruss**. It has been updated from the original 2015 Minetest 0.4 codebase to run smoothly out-of-the-box on **modern Luanti (including 5.18.0+)** with full mod-security compliance, GUI settings support, and zero game dependencies.

---

## ✨ Highlights

- **Real NASA Lunar Terrain** — Built from NASA Lunar Orbiter Laser Altimeter (LOLA) height data and Lunar Reconnaissance Orbiter Camera (LROC) albedo maps, dithered across 58 custom moonstone shades for natural surface contrast.
- **Nearside, Farside, or Full 3D Sphere** — Explore two high-precision lunar discs (nearside above, farside deep below) with seamless edge-to-edge teleportation between hemispheres, or switch to **Sphere Mode** to build on a giant 3D voxel Moon.
- **8,996 Built-In Lunar Landmarks** — Jump straight to historic sites like **Apollo 11**, **Copernicus**, **Tycho**, or **Mare Tranquillitatis** with instant prefix search.
- **Authentic Lunar Atmosphere** — Experience true lunar gravity (`0.165g`), automatic flight privileges for orbital sightseeing, and a starry SpaceEngine skybox featuring Earth overhead (or pure black space).
- **Works With Any Luanti Game** — No hard dependency on Minetest Game (`default` is optional). Runs cleanly in Minetest Game, VoxeLibre, Mineclonia, Devtest, or standalone minimal worlds.
- **100% Sandbox-Safe** — Runs cleanly under Luanti 5.18's strict mod security with no `secure.trusted_mods` or `--insecure-no-sandbox` workarounds required.

---

## 🚀 Quick Start

1. **Install the mod** into your Luanti `mods` directory:
   ```bash
   git clone https://github.com/ronrob-lu/moon-mapgen-minetest.git moon_mapgen
   ```
   *(Thanks to `mod.conf`, cloning directly as `moon-mapgen-minetest` also works without renaming.)*
2. **Create a new world** in Luanti (any game).
3. Open **Select Mods**, enable **Moon Mapgen** (`moon_mapgen`), and launch!
   - The mod automatically configures `singlenode` mapgen and spawns you directly on the lunar surface at `0° N, 0° E`.

---

## 🧭 Explore the Moon

Moon Mapgen adds two built-in navigation commands:

### `/goto <feature>` or `/goto <latitude> <longitude>`
Teleport anywhere on the lunar surface by landmark name or coordinates (negative latitude = south, negative longitude = west):

```text
/goto apollo 11            # Visit the Sea of Tranquility landing site
/goto copernicus           # Jump to Copernicus crater
/goto maretr               # Prefix match (spaces & punctuation optional) -> Mare Tranquillitatis
/goto -43.31 -11.36        # Jump directly to Tycho by coordinates
```

### `/where`
Displays your current lunar **latitude** and **longitude** in degrees.

---

## ⚙️ Configuration

Configure the mod either through **Luanti's Settings menu** (*Settings -> All Settings -> Mods -> moon_mapgen*) or by editing [`settings.conf`](settings.conf) before generating a world.

| Setting (`settings.conf` / UI) | Default | Description |
| --- | --- | --- |
| `land_node_meters` / `moon_mapgen_land_node_meters` | `150` | Horizontal scale in meters per node *(locked per world)* |
| `height_multiplier` / `moon_mapgen_height_multiplier` | `1` | Vertical terrain exaggeration factor *(locked per world)* |
| `projection` / `moon_mapgen_projection` | `equaldistance` | `equaldistance` (best accuracy), `orthographic` (fastest), or `sphere` *(locked per world)* |
| `albedo` / `moon_mapgen_albedo` | `true` | Shade surface brightness using NASA LROC albedo data *(locked per world)* |
| `teleport` / `moon_mapgen_teleport` | `true` | Automatically cross between nearside & farside discs at the edge *(locked per world)* |
| `gravity` / `moon_mapgen_gravity` | `0.165` | Player gravity relative to Earth *(changeable anytime)* |
| `sky` / `moon_mapgen_sky` | `fancy` | `fancy` (SpaceEngine skybox), `black` (plain black space), or `blue` *(changeable anytime)* |

> **Note:** Geometry settings are saved to `<world>/moon-mapgen-settings.conf` on first launch so existing worlds never suffer mismatched terrain seams. Gravity and sky can be changed anytime.

---

## 🛠️ What's New in This Modernized Fork

Updated from the original 2015 release by Alexander R. Pruss for modern **Luanti 5.2 – 5.18+**:

- Added [`mod.conf`](mod.conf) (`name = moon_mapgen`) to resolve disallowed-character activation errors and declare `default` as an optional dependency.
- Added [`settingtypes.txt`](settingtypes.txt) for native Luanti Settings UI integration.
- Eliminated `request_insecure_environment()` by preloading terrain chunks, albedo data, and the feature catalog cleanly at init time inside the sandbox.
- Updated deprecated APIs to modern `core.*` equivalents (`set_mapgen_setting`, table-based `set_sky` + `set_sun`/`set_moon`/`set_stars`, `get_pos`/`set_pos`, strict `vector.new` compliance, and `"deflate"` zlib decompression).
- Fixed multiple original bugs including `albedo = false` shadowing, disc-edge `NaN` / teleportation loops, respawn placement, and `default:stone` crashes in non-Minetest-Game worlds.

---

## 📜 Credits & License

- **Original Author:** [Alexander R. Pruss (`arpruss`)](https://github.com/arpruss/moon-mapgen-minetest) — original code copyright (c) 2015, licensed under the **MIT License**.
- **Lunar Datasets:** NASA LOLA elevation data and NASA LROC albedo data.
- **Sky Textures:** Generated with SpaceEngine (copyright Vladimir Romanyuk) and licensed for **personal, educational, and non-commercial use only** — see [`LICENSE`](LICENSE) for full terms. For a 100% open-source setup, remove `textures/sky_*.png` and set `sky = black`.
