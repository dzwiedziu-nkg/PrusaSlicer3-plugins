# Hull line — a PrusaSlicer slicing plugin

Two plugins in one bundle, and between them both halves of Prusa's own experiment against the
Benchy hull line:

| file | hook | what it does |
|---|---|---|
| `hull_line.lua` | `slicing.fill_planner` | lowers the flow of the solid infill that is not a top surface, and can give it its own speed |
| `hull_line_order.lua` | `slicing.layer_planner` | **prints the deck before the wall that runs past it**, where a part turns from sparse infill into solid layers. **Off by default** — the first print of it was a regression, and the README says what to print to find out whether it is one on your printer |

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

The rule for *which* layers is the signature Prusa describe and this repository measured: real
solid infill where the layers below carried almost none, with a wall running through. The run
then **follows the deck** — it goes on while the layer is still carrying at least `min_solid` of
solid infill, and ends on the first layer after that, with `depth` as a floor for a deck only a
layer or two thick.

The rule for *what moves* is **the deck, and nothing else**: the fill groups that are mostly
solid go to the front, and every other group keeps the order the slicer gave it. On a plain part
that comes to "fill, then wall", because the deck shares its region with the sparse infill round
it and there is only one fill group to move. Split them and it comes to Prusa's order exactly —
which is the next section, and it matters more than it sounds.

## The first print was a regression, and why

On a Core One with the Gen 2 hotend, the test block's wall is perfect without the plugin and
shows a faint difference with it, **on exactly the layers that were reordered**. Nothing in the
G-code explains it at first look: speed, flow, direction, seam position, retraction count and fan
are identical, checked move by move. Two things do change, and neither is a number in the file.

**1. When the wall is laid, and so how long it waits for the wall above it.** Moving the wall to
the end of a layer shifts its phase, so a *run* of reordered layers has a step at each end.
Measured on the test block in the orientation it is printed in — where in the layer the outer
wall is laid, and the time until the wall above it lands:

| layer | 20 | **21** | 22 | 23 | 24 | 25 | **26** |
|---|---|---|---|---|---|---|---|
| stock, phase | 20 % | 13 % | 20 % | 20 % | 20 % | 19 % | 21 % |
| stock, wait | 7.7 s | 7.6 | 11.2 | 7.6 | 7.5 | 7.6 | 7.9 |
| reordered, phase | 20 % | **90 %** | 85 % | 85 % | 85 % | 86 % | 20 % |
| reordered, wait | 7.7 s | **16.1** | 7.6 | 7.5 | 7.5 | 7.9 | **2.7** |

The wall waits twice as long entering the run and **a third as long leaving it** — 2.7 s, which
is a bead laid onto a bead that has barely set. **That is the same kind of thermal step the hull
line is blamed on**, put back at the same height by the fix for it.

**2. The layer now ends on the outside wall.** Its last extrusion is the external perimeter
closing at the seam, and the wipe and the layer-change travel start there instead of somewhere
inside the part.

## The way out: split the deck off, the way Prusa did

With a modifier mesh over the deck, the deck is a region of its own, so its fill is a group of
its own — and then the plugin's rule gives **deck fill, then the hull's wall, then the hull's own
fill**. That is Prusa's order, and it puts the wall back in the middle of the layer where the
step largely disappears:

| layer | 20 | **21** | 22 | 23 | 24 | 25 | **26** |
|---|---|---|---|---|---|---|---|
| modifier + order, phase | 20 % | 51 % | 37 % | 37 % | 37 % | 42 % | 21 % |
| modifier + order, wait | 7.7 s | 12.2 | 8.7 | 7.8 | 7.8 | 8.8 | 6.9 |

Against 16.1 s and 2.7 s without the modifier: the entry step is halved and the exit step is
gone. The layer ends inside the part, on the hull's own infill.

`tools/mkdeckmodifier.py` in the fork's workspace writes such a project, and
`prusa_benchy_hullline_test_block4_deck.3mf` is the test block with one already in it — a box
over the deck, inset from the wall so the hull keeps a ring of its own fill, carrying
`perimeters = 0` so the deck gets no wall of its own. In the GUI it is: right-click the object,
*Add modifier → Box*, scale and place it over the deck, and give it `Perimeters = 0`.

**It is not free.** The region boundary gets walled, which on this block is +247 mm of external
and +258 mm of internal perimeter: **+15.0 mm of filament, +2.3 %, and 15 s** of print time. The
reordering on top of it is free — every role identical to the milligram, same filament, same
estimated time, 1.9 mm less travel.

## The print that decides

Four slices of the same block, same filament, same session, same profile. Each answers one
question, and they are worth printing in this order:

| # | what | settings |
|---|---|---|
| 1 | **reference** | no plugin installed (or `flow_ratio = 1.0` and `order = false`) |
| 2 | **the order, as it was** | `order = true` on the plain project — this is the one that came out marked |
| 3 | **the order everywhere** | `order = true`, `always = true` on the plain project |
| 4 | **Prusa's own** | `order = true` on `prusa_benchy_hullline_test_block4_deck.3mf` |

- **3 clean, 2 marked** → the marks come from *switching* order part way up the part, not from
  the order. Then 4 is the shape to use, and the `always` row of the table above is why.
- **2 and 3 marked the same** → it is the order itself: the layer ending on the outside wall.
  Then 4 is still worth printing, because it is the one that does not end there.
- **4 clean and no hull line** → Prusa's experiment reproduces, and the price is the +2.3 %
  the modifier costs.
- **4 marked too** → the reordering is not the lever on this printer, and the honest place to
  stop is `order = false` with the flow half doing what little it does.

Print 1 and 4 at least. If the hull line is invisible on 1 to begin with — as it was on the
Core One with a Gen 2 hotend — then this part cannot answer the question and the Benchy has to.

## What it cannot do

One of Prusa's four experiments is out of reach of the fork altogether, and one is out of reach
of a plugin:

- **Two layers of wall in a row before returning to the infill** reorders *across* layers. No
  hook here can express that; it needs the G-code stage to hold a layer's infill back until the
  next layer's walls are down.
- **The modifier mesh** is a change to the model, not to slicing, so the plugin cannot make one —
  it can only make good use of one, which is what the section above is about.

There is also a limit inside the layer, and it is the reason the modifier matters. A group is
moved whole, and a run of fill is one region's worth: where a deck grows inside a part with no
modifier, its solid infill and the sparse infill round it are one group and travel together. The
plugin *sees* both — a group says what every role in it contributes, which is how the deck is
detected at all — but it cannot print one before the other while they are one region. Until a
`slicing.layer_planner` group can be a role rather than a region, splitting the region is the
only way to put the wall anywhere but first or last.

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
| `order` | `false` | print the deck first on a transition layer. **Off by default**, see the print plan above |
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
