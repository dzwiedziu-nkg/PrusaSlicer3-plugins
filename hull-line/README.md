# Hull line — a PrusaSlicer slicing plugin

A `slicing.fill_planner` plugin for PrusaSlicer 3.x. It lowers the flow of the solid infill that
is not a top surface, and can give it its own speed, where a part turns from sparse infill into
solid layers.

> **This is Prusa's own experiment, and they were not sure it was what helped.** Their write-up
> of the Benchy hull line lists four things they tried by hand in the G-code; this is the one a
> fill planner can do. The README says what the other three would need, and what the numbers
> here actually look like, because the honest answer is that this is a small lever.

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

This plugin's two settings map onto the two regimes: `flow_ratio` takes material out of the
throughput, and `speed` is for the other regime. **`speed` does nothing while the cooling
slowdown is pinning the layer time**, because the cooling logic rescales every feedrate in the
layer afterwards.

## What it does, and what it is worth

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

## What it cannot do

Three of Prusa's four experiments are out of reach of this extension point, and two of them are
out of reach of the fork altogether:

- **A modifier mesh splitting the deck from the hull** is a change to the model, not to slicing.
- **Printing the deck before the rest of the layer** is a change to the order extrusions are
  printed in, within one layer. No extension point here can reorder them.
- **Two layers of wall in a row before returning to the infill** reorders across layers, which
  is a deeper change still.

It also cannot *find* the transition. A fill planner is asked about every surface of every layer
at once, from the slicer's parallel infill stage, so it cannot compare a layer with the one
below. What it can see is the surface in front of it, so the rule is about the surface: solid
infill, not a top surface, at least `min_area` of it.

## Requirements

**No official PrusaSlicer release has this extension point.** It needs the fork:

**<https://github.com/dzwiedziu-nkg/PrusaSlicer>**, branch `main`.

It also needs `slicing.fill_planner` at API 1.5.0, which is what lets a plugin say "your lines,
printed differently" rather than having to lay its own — and what lets it reach solid infill at
all, since PrusaSlicer fills that with a pattern whose lines carry a width per point.

## Installing

```bash
ln -sfn "$PWD/hull-line/com.github.dzwiedziu-nkg.hull-line" ~/.config/PrusaSlicer3-dev/lua/
```

**It shares `slicing.fill_planner` with `bridges/` and `sparse-infill/`**, and the slicer loads
one plugin of each type, so only one of the three can be installed at a time.

## Settings

`settings.lua`, next to the Lua source. Edit and slice again: no restart, no rescan. The file is
read inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and
the defaults apply.

| setting | default | what it does |
|---|---|---|
| `flow_ratio` | `0.95` | how much of the flow the solid infill keeps. 1.0 turns the plugin off |
| `speed` | `0` | its print speed in mm/s. 0 keeps the role's own, and see the regime section |
| `min_area` | `15.0` | ignore solid surfaces smaller than this, in mm² |
| `roles` | `{SolidInfill = true}` | what to claim. `TopSolidInfill` is deliberately not here |
| `skip_first_layers` | `0` | leave this many layers at the bottom alone |

`min_area` is measured, not guessed: on the test block the solid infill of the three layers over
the deck is 19.2, 27.9 and 29.1 mm², and the patches this is meant to skip are 0.7 to 5.1. The
default sits in the gap.

## Licence

AGPL-3.0-only, see [LICENSE](LICENSE).
