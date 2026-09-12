# Overhang by size — a PrusaSlicer slicing plugin

A `slicing.slice_planner` plugin for PrusaSlicer 3.x. It **chamfers small overhangs off and
carries big ones on a cone**, choosing between the two by how big each overhang is.

## The problem it solves is ours, not the slicer's

There are two ways to stop the printer laying a bead onto air: take the overhang off, or put
something under it. This repository already had one plugin for each —
[`overhang-chamfer`](../overhang-chamfer/) and
[`make-overhang-printable`](../make-overhang-printable/) — and they could not both be installed,
because the slicer loads one plugin of each type and both are slice planners.

So you had to pick one for the whole print. That is the wrong granularity: **a 1 mm ledge is
cheaper to lose than to hold up**, and a 10 mm shelf is the other way round — chamfering it would
reshape the part and *still* leave an overhang needing support.

This plugin asks the size first.

## What it does

It asks for both passes at once and lets their size bounds do the choosing:

- the **clip** is told to leave alone anything wider than `cut_below`, so on the way up it takes
  only the small ledges;
- the **fill** then carries whatever the clip left, on the way down.

A part with a 1 mm ledge and a 10 mm shelf gets the cheap answer on the ledge and the honest one
on the shelf, in one print. Nothing gets both remedies: the clip runs first and the fill only
sees what is still overhanging.

Both halves are OrcaSlicer's ideas — the carry is their `make_overhang_printable`, and the angle
convention mirrors their `make_overhang_printable_angle`, so their default of 55 is this
plugin's 35.

## Measured

A tower with 1 mm, 2 mm and 4 mm ledges — one below `cut_below`, one on the line, one well
above — sliced four ways:

| | support | overhang perimeter | bridge infill | material | time |
|---|---|---|---|---|---|
| no plugin | 2174.0 mm³ | 51.7 mm³ | 445.5 mm³ | 6.64 cm³ | 19m 45s |
| `overhang-chamfer` alone | 2196.5 | 21.6 | 387.3 | 6.61 | 19m 35s |
| `make-overhang-printable` alone | 2082.3 | **0.00** | 294.3 | 6.64 | 21m 05s |
| **`overhang-by-size`** | 2085.5 | **0.00** | 294.3 | **6.58** | 21m 52s |

**Every 90° overhang gone, for less material than either single-remedy plugin** — because the
small ledges are cut rather than carried, and cutting a 1 mm ledge is cheaper than building a
cone under it. It is the slowest of the four by 47 s, which is the cut ledges changing the
toolpaths above them.

Layer by layer, the two remedies land where they should:

| Z | no plugin | chamfer alone | by-size |
|---|---|---|---|
| 4.20 (1 mm ledge) | 10.775 | **10.061** | **10.061** — cut |
| 11.00 | 12.775 | 12.775 | **15.061** — cone starting |
| 12.00 | 12.775 | 12.775 | **16.489** — cone arriving |
| 12.20 (4 mm ledge) | 16.775 | 16.775 | 16.775 |

The chamfer leaves the 4 mm ledge alone because it is wider than `cut_below`; `overhang-by-size`
picks it up on the way back down and builds the cone. On this part the slicer reports
`clipped 10 and widened 21 of the 80 layers`.

> **A note on these figures.** They were re-measured after a bug in the measuring script: it
> summed every `E > 0`, which counts **deretractions** — the filament pushed back after a travel
> — as material on the part. That inflates any pattern with more travel than the stock one, so
> the numbers below are lower than the ones this page carried at first. The conclusions did not
> move; the arithmetic did.

## Settings

`settings.lua` next to the Lua source. Edit and slice again; no restart, no rescan. It is read
inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and the
defaults apply.

| setting | default | what it does |
|---|---|---|
| `angle` | `35` | The slope both remedies aim for, in degrees from horizontal; 90 is vertical. `0` turns the plugin off. |
| `cut_below` | `2.0` | Overhangs up to this wide, in mm, are cut off; wider ones are carried. `0` never cuts, which is `make-overhang-printable` exactly. |
| `carry_max` | `0` | The most the cone may add, in mm. `0` is no limit and the ordinary setting — a cone terminates where it meets the part or the bed. |
| `min_z` | `0.0` | Leave everything below this height alone. |

Note that 35° stops the printer laying beads onto air but does **not** stop the support
generator, which wants a margin of `atan(tan(threshold + 1) × √2)` — 46° for a threshold of 35.
The [`overhang-chamfer` README](../overhang-chamfer/) works that out and measures it.

## Install this *instead of* the other two

All three are `slicing.slice_planner`, and the slicer loads one plugin of each type. This one is
a superset: `cut_below = 0` makes it `make-overhang-printable`, and a very large `cut_below`
with `angle` matched makes it `overhang-chamfer`.

## The hook it needs

`slicing.slice_planner`, which is:

> given a layer as it comes off the mesh, decide how far its outline may reach past the layer
> below — and, where it reaches too far, whether to cut it off or to hold it up.

Answering with a **list** of plans, one per remedy, is what makes this plugin possible; that
arrived in API 1.2.0.

Requires the fork: <https://github.com/dzwiedziu-nkg/PrusaSlicer> at `529aba88b2` or later, with
the hook at API 1.2.0.

## Running it

```bash
ln -sfn "$PWD/com.github.dzwiedziu-nkg.overhang-by-size" \
    ~/.config/PrusaSlicer3-dev/lua/
```

## License

AGPL-3.0-only. See `LICENSE`.
