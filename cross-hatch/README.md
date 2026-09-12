# Cross Hatch infill — a PrusaSlicer slicing plugin

A `slicing.fill_planner` plugin for PrusaSlicer 3.x. It lays sparse infill as **one family of
lines that holds its direction for a few millimetres and then turns ninety degrees**, so the
infill is stiff without welding itself into one continuous wall.

> **This is OrcaSlicer's pattern.** Cross Hatch is theirs, and this is a reimplementation of it
> for PrusaSlicer, which has no equivalent. Every number in `settings.lua` was measured off
> their own output rather than guessed. Credit for the pattern belongs to OrcaSlicer.

## The problem

PrusaSlicer's two ordinary sparse patterns sit at opposite extremes:

- **`grid`** lays both families of lines on every layer. The infill fuses into two continuous
  walls running the whole height of the part — stiff, and a plane for the part to come apart
  along, which is the same seam `alternate-extra-wall` exists to break up.
- **`rectilinear`** lays one family and turns it 90° every layer. There is no wall at all, but
  consecutive layers cross at right angles and touch each other at points rather than along
  lines.

Cross Hatch is the middle. One family of lines holds its direction for long enough that several
layers fuse into something stiff, and then turns 90° over a few more layers, so the wall never
runs the height of the part.

## What OrcaSlicer actually does

Read off `orca_alternate_extra_wall.gcode`, which was sliced with `sparse_infill_pattern =
crosshatch`, layer by layer:

| Z | dominant line angle | |
|---|---|---|
| 1.00 – 2.20 | 45° | holds, 7 layers |
| 2.40 – 3.40 | 52° … 127° | turning, 6 layers |
| 3.60 – 5.00 | 135° | holds, 8 layers |
| 5.20 – 6.20 | turning | 6 layers |
| 6.40 – 7.60 | 45° | holds |

A full cycle — 45° back to 45° — is **5.4 mm**, so a half period is 2.7 mm, of which about
**44 %** is spent turning. Those are the defaults here, and they are measurements, not guesses.

## Measured

A 20 × 20 × 16 mm block at 15 % `rectilinear`, with and without the plugin:

| | stock `rectilinear` | cross-hatch |
|---|---|---|
| line spacing | 2.714 mm | **2.714 mm** |
| lines per layer | 10 | **10** |
| infill path | 152.3 mm/layer | 126.5 mm/layer |
| infill filament | 893.0 mm³ | **740.0 mm³** (−17 %) |

**The lattice is the same lattice** — same spacing, same count. The 17 % is not lower density,
it is the *links*: the stock filler joins its lines with extruded arcs along the boundary, and
a planner's paths are separate lines with a travel between them. Less material and more travel,
which is the trade this hook makes on every plugin that uses it.

Line angle layer by layer, against OrcaSlicer's own file:

| Z | ours | OrcaSlicer |
|---|---|---|
| 1.00 – 2.20 | 45° | 45° |
| 2.40 | 52° | turning |
| 3.00 | 97° | turning |
| 3.40 | 127° | turning |
| 3.60 – 5.00 | 135° | 135° |
| 6.40 – 7.60 | 45° | 45° |
| 9.00 – 10.40 | 135° | 135° |

17 of the 18 layers checked agree. The one that does not is Z = 6.20, where OrcaSlicer is still
turning and this has arrived — their half period alternates between 13 and 14 layers where this
uses a constant 2.7 mm, so the two drift by a layer at the boundary and re-synchronise.

## Settings

`settings.lua` next to the Lua source. Edit and slice again; no restart, no rescan. It is read
inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and the
defaults apply.

| setting | default | what it does |
|---|---|---|
| `angle` | `45` | Direction of the lines in the first run, in degrees. |
| `half_period` | `2.7` | How far the pattern climbs before it has turned a full 90°, in mm. Shorter is more lattice-like, longer is stiffer with taller continuous faces. `0` turns the plugin off. |
| `transition` | `0.4444` | How much of each half period is spent turning rather than holding, 0 to 1. `0` turns over in one layer, which is what `rectilinear` does and what this pattern exists to avoid. |
| `z_offset` | `4.6` | Shifts the whole pattern up, in mm. Makes no difference to what the infill does; it exists so the output can be lined up with OrcaSlicer's. |
| `roles` | `InternalInfill` | Which surfaces to take over. Sparse infill only — solid, top and bridge surfaces have their own reasons for the pattern they use. |
| `skip_first_layers` | `0` | Leave this many layers at the bed alone. |

## Use it with `rectilinear`, not `grid`

Set `fill_pattern = rectilinear` (or `line`). Those lay **one** family of lines per layer, which
is what this pattern does, so the density you asked for is the density you get. Under `grid` the
slicer works its spacing out for two families crossing on every layer, and one family at that
spacing comes out at half the density.

## The hook it needs

`slicing.fill_planner`, which is not "cross hatch" but:

> given a surface the slicer is about to fill, lay the paths for it.

Requires the fork: <https://github.com/dzwiedziu-nkg/PrusaSlicer> at `529aba88b2` or later,
with the hook at API 1.2.0 — that is the version which tells a planner the **density**, without
which it cannot know how far apart a sparse pattern's lines belong.

## Running it

Symlink the bundle into the slicer's datadir, by the name in `manifest.json`:

```bash
ln -sfn "$PWD/com.github.dzwiedziu-nkg.cross-hatch" \
    ~/.config/PrusaSlicer3-dev/lua/
```

## License

AGPL-3.0-only. See `LICENSE`.
