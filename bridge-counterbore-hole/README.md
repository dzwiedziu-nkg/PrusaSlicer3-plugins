# Bridge counterbore holes — a PrusaSlicer slicing plugin

Two plugins in one bundle, for PrusaSlicer 3.x, that stop a counterbore being walled in mid-air.
They are OrcaSlicer's two modes and `settings.lua` picks one:

| `mode` | what happens at the step layer | what it costs |
|---|---|---|
| `"sacrificial"` | the hole is closed for that one layer and the whole opening is bridged | **a disc to drill out** |
| `"partial"` | the hole stays open and the wall round it is left to the fill stage | the hole's wall is missing on that layer |
| `"off"` | the stock slicer | the ring is walled in mid-air |

> **This is OrcaSlicer's feature.** `counterbore_hole_bridging` is theirs, in both of its modes;
> this is a reimplementation of it for PrusaSlicer, which has no equivalent.

## The problem, and what PrusaSlicer already does about it

A counterbore is a wide recess for a screw head with a narrower hole running on through it.
Printed recess down, the layer where the opening narrows is a ring of material over open air.

PrusaSlicer bridges that ring already, and bridges it well — **there is no setting for it,
because there is no decision.** The ring is a bottom surface with nothing under it, so the
classifier makes it a bridge and the bridge machinery fills it. Turning off *Detect bridging
perimeters* does not change that; the ring is still bridged. Nothing in the print settings
touches it.

What it also does is print **the narrow hole's own wall in mid-air**, both loops of it, going
round nothing. That is what you see in the preview as a ring hanging in space, and it is what
this plugin removes.

Measured on a 24 × 24 × 6 mm block with a Ø12 counterbore and a Ø6 hole, at the step layer:

| | bridge laid | wall in mid-air | hole at the centre |
|---|---|---|---|
| stock PrusaSlicer | 240.4 mm / 91 moves | **42.9 mm / 64 moves** | open |
| `mode = "sacrificial"` | 348.8 mm / 59 moves | **none** | closed for one layer |
| `mode = "partial"` | 240.4 mm / 90 moves | **none** | open |
| OrcaSlicer `sacrificiallayer` | closes it | none | closed for one layer |
| OrcaSlicer `partiallybridge` | 134.8 mm / 34 moves | none | open |

"Hole at the centre" is measured, not assumed: the closest any extrusion comes to the middle of
the hole is 0.00 mm with the sacrificial layer, 3.01 mm in partial mode and 3.21 mm without the
plugin, against a hole radius of 3 mm.

In partial mode the walls move outward onto held-up material - closest approach 6.60 mm against
OrcaSlicer's 6.19 - and the layer above comes back with its hole, resting on what was bridged.

On the half-size version of the same part, Ø6 over Ø3, the wall in mid-air is 7.1 mm over 2
moves without the plugin and none with it. The effect scales with the hole, which is why a small
test part makes the problem look negligible.

## What it costs

Almost nothing, because the sacrificial layer replaces extrusions that were being laid in the
air anyway:

| Ø12 over Ø6 | filament | estimated time |
|---|---|---|
| stock | 1144.67 mm | 9m 23s |
| `"sacrificial"` | 1145.69 mm | 9m 21s |
| `"partial"` | 1169.31 mm | 9m 23s |

The sacrificial layer is free because it replaces extrusions that were being laid in the air
anyway; on the half-size part it comes out *cheaper*, 274.93 mm against 274.70. Partial mode
costs 2.2 % more, which is the anchor band and the extra wall loops round it.

The real cost of the sacrificial layer is the disc. It is one layer thick and it is inside the
hole, so it comes out with a drill, a screwdriver or a push — but it does have to come out.
That is the whole of the choice between the two modes.

## What it does not touch

**An ordinary hole going straight down.** Neither mode touches one, and both are checked against
a generated block with a plain Ø6 through-hole: **G-code identical to the run with no plugin
installed**, in both modes.

The tests are different but the idea is the same in each. The sacrificial layer looks at the
*rim*: the band just outside the hole, `layer_height / tan(angle)` wide, has to be mostly over
air. Partial mode looks at the material: the part of the region that is not over the layer below
has to be wider than one perimeter spacing and has to touch a hole. A hole going straight down
fails both, and so does a bore that tapers gently.

This matters more than it sounds. A plugin that acted on every hole it found would fill or
unwall every screw hole in every part.

## Requirements

**No official PrusaSlicer release has this extension point.** It needs the fork:

**<https://github.com/dzwiedziu-nkg/PrusaSlicer>**, branch `main`.

## Installing

```bash
ln -sfn "$PWD/bridge-counterbore-hole/com.github.dzwiedziu-nkg.bridge-counterbore-hole" \
        ~/.config/PrusaSlicer3-dev/lua/
```

**Install this instead of `overhang-chamfer`, `make-overhang-printable` or `overhang-by-size`,
not alongside them** — all four use `slicing.slice_planner`, and the slicer loads one plugin of
each type; the first by id wins and the rest are ignored with a warning in the log. In
`mode = "partial"` it also takes `slicing.perimeter_planner`, so it displaces
`alternate-extra-wall` as well.

## Settings

`settings.lua`, next to the Lua source. Edit and slice again: no restart, no rescan. The file is
read inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and
the defaults apply.

| setting | default | what it does |
|---|---|---|
| `enabled` | `true` | `false` turns the plugin off without removing it |
| `mode` | `"sacrificial"` | `"sacrificial"`, `"partial"` or `"off"` — see the table at the top |
| `max_hole` | `10.0` | sacrificial only: the largest opening that may be closed, in mm, as the largest disc that fits inside it |
| `angle` | `35` | sacrificial only: how far a rim has to hang before the hole counts, as a slope in `support_material_threshold`'s convention |
| `anchor` | `0.0` | partial only: how far the fill may reach into held-up material for the bridge to rest on, in mm. 0 asks the slicer for one perimeter spacing |
| `min_unsupported` | `0.0` | partial only: ignore unsupported pieces narrower than this, in mm. 0 asks the slicer for one perimeter spacing |
| `min_z` | `0.0` | leave everything below this height alone |

The two modes are alternatives and cannot be combined: closing the hole leaves no wall for the
other mode to remove. The bundle holds a plugin for each — one on `slicing.slice_planner` and
one on `slicing.perimeter_planner` — and both read this one file, so `mode` switches both.

`max_hole` is the whole of the safety and **`0` does not mean "no limit" in a useful sense** —
it means the same as everywhere else, no limit, which here is a sacrificial layer across a bore
of any size. 10 mm covers a screw counterbore, which is what this is for.

## Why it is two plugins

The two modes act at different points in the slicer and neither can be done where the other is.

**The sacrificial layer is a change to the outline.** It closes a hole on one layer, which is
something `slicing.slice_planner` can express: it is handed each layer as it comes off the mesh
and may change what it is. That is the `"cap"` remedy, next to the chamfer and the cone.

**Partial mode is a change to what gets walled**, not to the outline: the material stays, the
wall does not. That is a decision the perimeter stage makes, so it needs
`slicing.perimeter_planner` — which already existed for the wall *count* and now also answers
what happens to the part of a region that hangs over air.

A bundle may hold several plugins, so both ship in this directory and `settings.lua` is shared.
That is also why `mode` is one setting rather than two switches: running both would close the
hole and then remove a wall that is no longer there.

## Licence

AGPL-3.0-only, see [LICENSE](LICENSE).
