# Reverse on even — a PrusaSlicer slicing plugin

A `slicing.loop_direction` plugin for PrusaSlicer 3.x. It walks the wall loops of every other
layer **the other way round**, so a wall laid over air is dragged in alternating directions as
it cools instead of always the same way.

> **This is OrcaSlicer's feature.** `overhang_reverse` is theirs; this is a reimplementation of
> it for PrusaSlicer, which has no equivalent. Where the two differ, this README says so.

## What it does

A perimeter is a closed loop and the nozzle has to go round it one way or the other. PrusaSlicer
always picks the same way — counter clockwise seen from above, or clockwise for the whole print
if the printer profile says `prefer_clockwise_movements`. There is no other control over it.

That matters on a wall that leans out over air. A bead cools and contracts along its own
direction of travel, and if every layer travels the same way the pull adds up: the overhang
curls towards the nozzle, and a tall wall in a shrinking material bows. Print every other layer
in the opposite direction and consecutive layers pull against each other instead.

**Nothing is added, removed or moved.** The same loops are printed with the same material, in
the opposite order of points. Extruded length is identical to the millimetre, which is the first
thing the measurement below checks.

## What it is not

It is not a fix for an overhang the printer cannot hold up at all. It makes a steep overhang
come out better; it does not make an unsupported one printable. For that, see
[`overhang-chamfer`](../overhang-chamfer/) and
[`make-overhang-printable`](../make-overhang-printable/) in this repository, which change the
geometry rather than the direction of travel.

## Requirements

**No official PrusaSlicer release has this extension point.** It needs the fork:

**<https://github.com/dzwiedziu-nkg/PrusaSlicer>**, branch `main`.

The plugin also needs **Detect bridging perimeters** (`overhangs`) enabled in the print settings,
which is what makes the slicer mark the parts of a wall that hang over air. With it off nothing
is ever marked and the plugin never fires — unless you set `require_overhang = false`, which
alternates every layer regardless and is the setting for warping rather than for overhangs.

## Installing

```bash
ln -sfn "$PWD/reverse-on-even/com.github.dzwiedziu-nkg.reverse-on-even" \
        ~/.config/PrusaSlicer3-dev/lua/
```

It shares its extension point with nothing else in this repository, so it can be installed
alongside any of the other plugins.

## Settings

`settings.lua`, next to the Lua source. Edit and slice again: no restart, no rescan. The file is
read inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and
the defaults apply.

| setting | default | what it does |
|---|---|---|
| `enabled` | `true` | `false` turns the plugin off without removing it |
| `phase` | `1` | which layers are turned, as `layer_id % 2`. 1 is every other layer starting with the second, which is what OrcaSlicer does |
| `require_overhang` | `true` | only turn a layer whose wall is laid over air. `false` alternates every layer, which is OrcaSlicer's `overhang_reverse_threshold = 0` |
| `min_overhang_length` | `0.0` | how much wall over air an island needs, in mm. 0 is "any at all" |
| `internal_only` | `false` | leave the wall that shows alone. OrcaSlicer's `overhang_reverse_internal_only` |
| `skip_first_layers` | `1` | leave this many layers at the bottom alone |

### The one setting that is not theirs

`min_overhang_length` is **not** OrcaSlicer's `overhang_reverse_threshold`, and converting
between them is not possible in general.

Theirs is a **depth**: they offset the layer below by `threshold − ½ line width` and ask whether
any part of the wall falls outside it, so it answers "how far past the layer below does this
wall reach". Ours is a **length**: the extension point is reached after the perimeter generator
has already split each loop where it left the layer below, so what is available is how *much*
of the wall hangs, not how far out.

At OrcaSlicer's default of 50 % of the line width the depth works out to exactly zero — any part
of the wall outside the layer below counts — and our default of `0.0` means the same thing, so
the two agree where it matters. Away from the default they diverge, and this README would rather
say so than pretend a conversion exists.

## Measured against OrcaSlicer

`reverse_on_even.stl` is the test part: a prism whose underside slopes 3 mm up over 5 mm of run,
so at 0.2 mm layers every layer above the anchored block steps 0.333 mm out over air. The
reference is `orca_reverse_on_even.gcode`, sliced by OrcaSlicer at `overhang_reverse = 1`,
threshold 50 %, `overhang_reverse_internal_only = 0`.

Walk direction of the outer wall, layer by layer, with the plugin at its defaults:

| Z | 0.20 | 0.40 | 0.60 | 0.80 | 1.00 | 1.20 | … | 3.00 | 3.20 | 3.40 | 3.60 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| stock PrusaSlicer | CCW | CCW | CCW | CCW | CCW | CCW | CCW | CCW | CCW | CCW | CCW |
| OrcaSlicer | CCW | CW | CCW | CW | CCW | CW | … | CCW | CCW | CCW | CCW |
| this plugin | CCW | CW | CCW | CW | CCW | CW | … | CCW | CCW | CCW | CCW |

**All 18 layers agree, outer wall and inner wall both.** Including the last three, where neither
slicer reverses: above Z 3.20 the part tapers inward, no wall is outside the layer below any
more, and both stop. The agreement is not just layer parity — the overhang test agrees too.

Nothing else moved:

| | plugin off | plugin on |
|---|---|---|
| external perimeter | 442.77 mm | 442.77 mm |
| internal perimeter | 339.87 mm | 339.87 mm |
| solid infill | 317.58 mm | 317.58 mm |
| top solid infill | 108.68 mm | 108.68 mm |
| filament | 40.9316 mm | 40.9316 mm |
| travel | 271.57 mm | 271.26 mm |
| estimated time | 1m 19s | 1m 19s |

The 0.31 mm of travel is the loop starting at a slightly different point once it is walked the
other way. Every extrusion role is identical, which is the invariant worth checking: a plugin
that reorders and nothing else must not move a milligram of plastic.

### The null case

| | differing lines | of which motion or command |
|---|---|---|
| no plugin installed, against G-code sliced before the extension point existed | 6 | **0** |
| plugin installed, `enabled = false` | 6 | **0** |
| plugin installed at its defaults, on a part with no overhang | 6 | **0** |

The six are the timestamp, the run time and the run UUID, on both sides. File sizes match.

The third row is the one worth reading twice: a plain box is left alone because no wall of it is
outside the layer below — not because the plugin failed to load. Set `require_overhang = false`
and the same box comes back with **80 of its 160 wall loops turned round**, alternating layer by
layer, at 1198.872 mm of filament against 1198.872 mm without.

## Licence

AGPL-3.0-only, see [LICENSE](LICENSE).
