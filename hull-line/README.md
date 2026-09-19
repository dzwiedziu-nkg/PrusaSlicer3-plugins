# Hull line — a PrusaSlicer slicing plugin

Two plugins in one bundle, and between them both halves of Prusa's own experiment against the
Benchy hull line:

| file | hook | what it does |
|---|---|---|
| `hull_line.lua` | `slicing.fill_planner` | lowers the flow of the solid infill that is not a top surface, and can give it its own speed |
| `hull_line_order.lua` | `slicing.layer_planner` | **prints the deck before the wall that runs past it**, where a part turns from sparse infill into solid layers |

> **This is Prusa's own experiment, and they were not sure it was what helped.** Their write-up
> of the Benchy hull line lists four things they tried by hand in the G-code; two of them are
> here. The README says what the other two would need, and what the numbers here actually look
> like, because one of these levers is small and the other one costs nothing.

## The problem

The Benchy hull line is a ridge round the hull at the height where the deck starts. Prusa trace
it to the transition itself: a run of layers carrying a 15 % lattice is followed by layers that
are nearly solid, so the material and the time per layer jump, and the wall running through that
height cools differently above and below it.

Measured on `benchy_hullline_test_block4.STL` at 0.20 mm on a 0.4 nozzle, filament per layer:

| Z | 6.60 | 6.80 | 7.00 | 7.20 | 7.40 | 7.60 | 7.80 | 8.00 | 8.20 |
|---|---|---|---|---|---|---|---|---|---|
| mm | 5.53 | 5.82 | **9.41** | 6.83 | 7.46 | 7.61 | 7.63 | 6.39 | 5.57 |

Up 70 % in one layer, back down seven layers later, with the wall at 106.7 mm throughout.

## Which regime you are in, and why it decides everything

**Check this before attacking a hull line, because the two regimes want different answers.**

That test block, sliced with an ordinary Prusa profile, has `slowdown_below_layer_time = 8`, and
the part is small enough that *every* layer is under eight seconds. So the slicer has already
flattened the layer time: every extruding move in the file runs at 25 mm/s and every layer takes
about 7.8 seconds, whether it carries 163 mm of path or 345 mm.

| the same block | plain layer | transition layer |
|---|---|---|
| layer time as sliced, `slowdown_below_layer_time = 8` | 7.8 s | 7.8 s |
| layer time with that turned off | 1.07 s | **2.52 s** |

So on a small part **the step is not in the time, it is in the throughput**: the nozzle pushes
9.4 mm of filament in the same eight seconds where it pushed 5.5, which is 70 % more hot plastic
per second going into the part. On a part big enough for its layers to clear the minimum time —
a real Benchy at 150 g — the time is free to step instead, and that is the case Prusa describe.

The settings map onto the two regimes: `flow_ratio` takes material out of the throughput, and
`speed` is for the other regime. **`speed` does nothing while the cooling slowdown is pinning
the layer time**, because the cooling logic rescales every feedrate in the layer afterwards.
The reordering half is about neither: it changes *when* in the layer the wall is laid.

## The flow half, and what it is worth

Prusa's words are "slightly lower the flow of solid infill, except for the very top layer". So:
solid infill, not top solid infill, and not the small patches that are solid for other reasons.

Measured on the same block at the default `flow_ratio = 0.95`:

| Z | filament without | with | change |
|---|---|---|---|
| 7.20 | 6.831 | 6.757 | −1.08 % |
| 7.40 | 7.460 | 7.348 | −1.51 % |
| 7.60 | 7.606 | 7.486 | −1.58 % |

The solid infill itself is down exactly 5 % on those layers and every other role is untouched to
the microlitre. Over the whole part it is −0.32 %.

**That is a small lever against a 70 % step, and this README would rather say so than sell it.**
It is worth printing precisely because Prusa could not tell whether it helped; the measurement
above is the slicing half of that question, and the printer has the other half.

## The order half, and what it costs

Prusa's second experiment was to print *deck perimeters, deck infill, then the rest of the
layer*, so that the hull's wall is not laid straight after the mass of solid beside it. That is
an ordering decision, and `slicing.layer_planner` is the hook for it: a layer falls into groups —
the walls of one island, and each run of its fill — and a plugin answers with the order to print
them in.

It is a **layer** planner rather than a fill planner because it has to know *which* layer the
deck starts on. This hook is reached from the serialized G-code stage, one layer at a time and in
order, so the plugin can carry a running picture of the part from one layer to the next and
notice where it changes. A fill planner is asked about every layer at once and can never know.

The rule is the signature Prusa describe and this repository measured: real solid infill where
the layers below carried almost none, with a wall running through. The run then **follows the
deck** — it goes on while the layer is still carrying at least `min_solid` of solid infill, and
ends on the first layer after that, with `depth` as a floor for a deck only a layer or two thick.
A fixed count would hand the wall back to its old place in the middle of a deck, which is
precisely where the reordering is wanted.

Measured on the test block, 11 of 104 layer slices are reordered, in two runs:

| | layers | why |
|---|---|---|
| the deck | Z7.00 … 7.80 | the transition the hull line is named after; the solid infill there runs 10.2, 3.9, 5.6, 5.8, 0.7 mm³ |
| the top shell | Z19.60 … 20.60 | the same change of regime, at the top of the part |

and on each of them the order changes like this:

```
stock    ;TYPE:Perimeter > External perimeter > Internal infill > Solid infill
planned  ;TYPE:Internal infill > Solid infill > Perimeter > External perimeter
```

**Nothing else changes, and that is the point.** Extruded length per role, before and after:

| role | stock | planned |
|---|---|---|
| External perimeter | 5838.281 | 5838.281 |
| Perimeter | 5494.261 | 5494.261 |
| Internal infill | 4401.878 | 4401.878 |
| Solid infill | 1338.638 | 1338.638 |
| Bridge infill | 461.550 | 461.550 |
| Top solid infill | 378.606 | 378.606 |
| filament, mm | 637.7800 | 637.7800 |
| travel, mm | 2106.38 | 2112.19 |

Same paths, same material, same estimated print time. The travel is 5.8 mm longer, 0.3 % of it
and about a hundredth of a second, because the head leaves the deck at the far end from where the
wall starts. On the counterbore plate below the same reordering saves 20 mm instead, so **treat
the travel as a wash** rather than as a cost or a saving.

**One honest caveat, measured on a different part.** On a plate of two counterbore test objects
the rule fires on 38 of 75 layer slices — a bridged hole is a sparse-to-solid transition too, and
above the bore those parts stay solid, so the run stays on — and there the fill is not quite
untouched: internal infill comes out 2.6 mm longer over 7432 mm, which is +0.035 %, one extruded
segment fewer out of 11 481, and the same filament total and estimated time. A run entered from
somewhere else is chained and cut up slightly differently. Nothing is lost or added; if you need
the fill byte for byte, this half is not for you.

On a part that turns solid and stays solid, the run therefore covers everything above the
transition, which is what `infill_first` does for a whole object anyway. `min_solid` is the knob
at both ends: on the test block it decides where the deck starts and stops being one.

| `min_solid` | reordered | the deck run |
|---|---|---|
| `1.0`, the default | 11 of 104 | Z7.00 … 7.80 — from the layer that carries 10.2 mm³ to the one that carries 0.7 |
| `0.5` | 15 of 104 | Z6.80 … 8.00 — one layer earlier, where the first 0.7 mm³ sliver of deck appears, and one later |

## What reordering does besides reorder, and the print that tells you whether it matters

**The first print of this was a regression**, on a Core One with the Gen 2 hotend: the block's
wall is perfect without the plugin and shows a faint difference with it, on exactly the layers
that were reordered. Nothing in the G-code explains that at first look — speed, flow, direction,
seam position, retraction count and fan are identical, checked move by move. Two things do
change, and neither is visible as a number in the file:

**1. When the wall is laid, relative to the wall below it.** Moving the wall to the end of a
layer shifts its phase, and a run of reordered layers therefore has two steps in it — one where
the run starts and one where it ends. Measured at the seam of the test block, the time from
laying a piece of wall to laying the piece on top of it:

| Z | 6.80 | **7.00** | 7.20 | 7.40 | 7.60 | 7.80 | **8.00** | 8.20 |
|---|---|---|---|---|---|---|---|---|
| stock | 7.55 s | 7.49 | 7.01 | 7.17 | 7.63 | 7.82 | 10.75 | 8.89 |
| reordered run | 7.55 s | **10.88** | 8.13 | 8.07 | 7.88 | 7.89 | **4.97** | 8.89 |
| `always = true` | 7.97 s | 8.00 | 8.13 | 8.07 | 7.88 | 7.89 | 8.44 | 7.37 |

The wall waits half again as long entering the run and half as long leaving it. **That is the
same kind of thermal step the hull line is blamed on**, put back at the same height by the fix.

**2. The layer now ends on the outside wall.** Its last extrusion is the external perimeter
closing at the seam, and the wipe and the layer-change travel start there instead of somewhere
inside the part.

`always = true` is in `settings.lua` for exactly this question. It reorders every layer, so the
wall is laid last from bottom to top and the run has no boundaries — the third row above, flat
all the way. Print the block three times, without the plugin, with the ordinary run and with
`always`, and the wall says which of the two mechanisms marks it:

- **`always` is clean and the ordinary run is not** → the marks come from *switching* order part
  way up, not from the order. Then a run has to stop costing a step, which means keeping the
  wall off the layer boundary (see below), or not switching at all.
- **both are marked the same way** → it is the order itself, and the deck being printed first is
  not worth what the wall pays for it on this part.

The way out of both, if the print says to keep going, is to put the wall **in the middle** of
the layer rather than at its end: deck infill, then the wall, then the sparse infill. The layer
then ends inside the part and the phase step halves. It needs the slicer to offer a region's
solid and sparse fill as separate groups, which it does not yet — see the limit at the end of
the next section.

## What it cannot do

Two of Prusa's four experiments are still out of reach, and one of them is out of reach of the
fork altogether:

- **A modifier mesh splitting the deck from the hull** is a change to the model, not to slicing.
  With one, this plugin gets closer to Prusa's order for free: the deck becomes its own region,
  so its walls and its fill are groups of their own and come first, which is their order exactly.
- **Two layers of wall in a row before returning to the infill** reorders *across* layers. No
  hook here can express that; it needs the G-code stage to hold a layer's infill back until the
  next layer's walls are down.

There is also a limit inside the layer. A group is moved whole, and a run of fill is one region's
worth: where a deck grows inside a part, its solid infill and the sparse infill round it are one
group and travel together. The plugin *sees* both — a group says what every role in it
contributes, which is how the deck is detected at all — but it cannot print one before the other
until they are separate regions, and a modifier mesh is what makes them separate.

## Requirements

**No official PrusaSlicer release has these extension points.** They need the fork:

**<https://github.com/dzwiedziu-nkg/PrusaSlicer>**, branch `main`.

`slicing.fill_planner` at API 1.5.0 is what lets a plugin say "your lines, printed differently"
rather than having to lay its own — and what lets it reach solid infill at all, since
PrusaSlicer fills that with a pattern whose lines carry a width per point. `slicing.layer_planner`
at 1.0.0 is the ordering hook, and it is new with this plugin.

## Installing

```bash
ln -sfn "$PWD/hull-line/com.github.dzwiedziu-nkg.hull-line" ~/.config/PrusaSlicer3-dev/lua/
```

**It shares `slicing.fill_planner` with `bridges/` and `sparse-infill/`**, and the slicer loads
one plugin of each type, so only one of the three can be installed at a time. Nothing else in
this repository uses `slicing.layer_planner` yet.

The two halves are two files, and it is the file rather than the setting that claims a hook:
`flow_ratio = 1.0` turns the flow half off but still occupies the fill planner slot. To run the
ordering half beside a different fill planner, delete `hull_line.lua` from the installed
bundle.

## Settings

`settings.lua`, next to the Lua source, shared by both halves. Edit and slice again: no restart,
no rescan. The file is read inside a `pcall`, so **a syntax error in it is reported nowhere** —
the file is ignored and the defaults apply.

The flow half:

| setting | default | what it does |
|---|---|---|
| `flow_ratio` | `0.95` | how much of the flow the solid infill keeps. 1.0 turns this half off |
| `speed` | `0` | its print speed in mm/s. 0 keeps the role's own, and see the regime section |
| `min_area` | `15.0` | ignore solid surfaces smaller than this, in mm² |
| `roles` | `{SolidInfill = true}` | what to claim. `TopSolidInfill` is deliberately not here |
| `skip_first_layers` | `0` | leave this many layers at the bottom alone |

The order half:

| setting | default | what it does |
|---|---|---|
| `order` | `true` | print the deck first on a transition layer. `false` turns this half off |
| `min_solid` | `1.0` | how much solid infill, in mm³, makes a layer a deck rather than a patch — it sets both ends of the run |
| `window` | `5` | how many layers back the "almost none below" comparison looks — and how many have to go by before anything can fire at all |
| `depth` | `3` | the shortest run, in layers; the run itself lasts as long as the deck does |
| `require_wall` | `true` | only treat a layer as a transition when a wall runs through it |
| `always` | `false` | diagnostic: reorder every layer, so the run has no boundaries — see above |

`min_area` is measured, not guessed: on the test block the solid infill of the three layers over
the deck is 19.2, 27.9 and 29.1 mm², and the patches this is meant to skip are 0.7 to 5.1. The
default sits in the gap.

`window` is also the guard at the bottom of the part. A part that starts solid on the bed is not
a transition — there is no wall below it to be marked — and with no such guard the first layers
of every print are reordered for nothing.

## Licence

AGPL-3.0-only, see [LICENSE](LICENSE).
