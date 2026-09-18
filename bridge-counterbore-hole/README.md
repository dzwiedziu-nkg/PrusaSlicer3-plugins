# Bridge counterbore holes — a PrusaSlicer slicing plugin

A `slicing.slice_planner` plugin for PrusaSlicer 3.x. It closes a hole for the one layer where
the opening under it narrows, so the step is bridged in a single span instead of being walled in
mid-air. **The disc it leaves has to be drilled or pushed out afterwards.**

> **This is OrcaSlicer's feature.** `counterbore_hole_bridging` is theirs; this is a
> reimplementation of its `sacrificiallayer` mode for PrusaSlicer, which has no equivalent.
> Their other mode is not reproduced, and the section at the end says why.

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

| | bridge laid | wall printed in mid-air |
|---|---|---|
| stock PrusaSlicer | 240.4 mm over 91 moves | **42.9 mm over 64 moves** |
| with this plugin | 348.8 mm over 59 moves | **none** |
| OrcaSlicer, `sacrificiallayer` | comparable | none |

On the half-size version of the same part, Ø6 over Ø3, the wall in mid-air is 7.1 mm over 2
moves without the plugin and none with it. The effect scales with the hole, which is why a small
test part makes the problem look negligible.

## What it costs

Almost nothing, because the sacrificial layer replaces extrusions that were being laid in the
air anyway:

| | filament | estimated time |
|---|---|---|
| Ø6 over Ø3, without | 274.93 mm | 4m 0s |
| Ø6 over Ø3, with | 274.70 mm | 4m 0s |
| Ø12 over Ø6, without | 1144.67 mm | 9m 23s |
| Ø12 over Ø6, with | 1145.69 mm | 9m 21s |

The real cost is the disc. It is one layer thick and it is inside the hole, so it comes out with
a drill, a screwdriver or a push — but it does have to come out.

## What it does not touch

**An ordinary hole going straight down.** The test is the *rim*: the band just outside the hole,
`layer_height / tan(angle)` wide, has to be mostly over air before the hole is closed. A hole
going straight down has its rim resting on the layer below, and so does a bore that tapers
gently enough. Verified on a block with a plain Ø6 through-hole: **0 layers capped, and the
G-code is identical to the run with no plugin installed.**

This matters more than it sounds. A plugin that closed every hole it found would fill every
screw hole in every part.

## Requirements

**No official PrusaSlicer release has this extension point.** It needs the fork:

**<https://github.com/dzwiedziu-nkg/PrusaSlicer>**, branch `main`.

## Installing

```bash
ln -sfn "$PWD/bridge-counterbore-hole/com.github.dzwiedziu-nkg.bridge-counterbore-hole" \
        ~/.config/PrusaSlicer3-dev/lua/
```

**Install this instead of `overhang-chamfer`, `make-overhang-printable` or `overhang-by-size`,
not alongside them.** All four are `slicing.slice_planner` plugins and the slicer loads one
plugin of each type; the first by id wins and the rest are ignored with a warning in the log.

## Settings

`settings.lua`, next to the Lua source. Edit and slice again: no restart, no rescan. The file is
read inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and
the defaults apply.

| setting | default | what it does |
|---|---|---|
| `enabled` | `true` | `false` turns the plugin off without removing it |
| `max_hole` | `10.0` | the largest opening that may be closed, in mm, as the largest disc that fits inside it |
| `angle` | `35` | how far a rim has to hang before the hole counts, as a slope in `support_material_threshold`'s convention |
| `min_z` | `0.0` | leave everything below this height alone |

`max_hole` is the whole of the safety and **`0` does not mean "no limit" in a useful sense** —
it means the same as everywhere else, no limit, which here is a sacrificial layer across a bore
of any size. 10 mm covers a screw counterbore, which is what this is for.

## The mode that is not here

OrcaSlicer has a second mode, `partiallybridge`, which keeps the hole open and only stops the
wall being drawn over the unsupported part. It is not reproduced here, and the reason is worth
writing down rather than leaving as a gap.

That mode is a decision about *perimeters*: it takes the unsupported area out of the surfaces
the perimeter generator is about to run on, so no wall is generated there at all, and hands it
to the fill stage instead. This extension point runs earlier, on the outlines as they come off
the mesh, and can only change what those outlines are. Closing the hole is expressible; "keep
the hole but do not wall it" is not.

Measured at the same step layer, so the difference is on the record: their `partiallybridge`
lays 34.5 mm of bridge over 29 moves and no wall in mid-air, against stock PrusaSlicer's 67.4 mm
of bridge and 7.1 mm of wall. Note that it lays *less* bridge than PrusaSlicer already does —
the thing it removes is the wall, not the gap.

Reaching it would need a second extension point, in the perimeter stage, along the lines of
"given a layer's surfaces and what is under them, decide which areas are walled and which are
filled". That is a bigger question than this one and nobody has needed it yet.

## Licence

AGPL-3.0-only, see [LICENSE](LICENSE).
