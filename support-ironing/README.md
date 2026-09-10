# Support interface ironing

A slicing plugin for PrusaSlicer that runs an **ironing pass over the top of a support
interface**, so the underside of the overhang printed on it comes out smooth.

The underside of an overhang is an imprint of whatever it was printed on. A support interface
is a set of parallel extrusions with ridges between them, and the object's first layer copies
those ridges. Ironing the interface first — the nozzle passing back over it at the same
height, at low flow and low speed, melting the ridges level — gives the object a flat surface
to be printed against instead.

Bambu Studio added this in 2.5.0 as **Support Interface Ironing**; OrcaSlicer has the same
thing as `support_ironing`, with `support_ironing_pattern`, `support_ironing_flow` and
`support_ironing_spacing`. **PrusaSlicer has no equivalent** — it irons top surfaces only
(`ironing_type`), and supports not at all.

> **Status: it slices; it has not been printed.** The hook, the plugin and the tests are in
> place and both test models come out with an ironing pass over the support contact layer.
> Everything below about print quality is the argument for doing it, not a result.

## Why this and not the overhang planner

This repository's sibling, `wave-overhang-plugin`, attacks the same problem — a good-looking
horizontal underside — from the other end, by printing the overhang with no support at all.
It is parked (see `STATUS.md` 6.31). The two are not competitors so much as opposite trades:
waves cost print time and reliability and give up supports; ironing keeps the supports and
spends a little time making their top flat. The second is the far safer bet and is what
several other slicers already ship.

## The hook it needs

PrusaSlicer generates support toolpaths in `generate_support_toolpaths()`
(`Support/SupportCommon.cpp`), which both the normal and the tree support generators call, so
one extension point serves both.

The hook is deliberately **not** "iron a support interface". That would be the one-trick pony
the upstream maintainer warned about. It is:

> given an area the slicer has just covered, and what covered it, plan an **extra pass** over
> it.

which also serves ordinary top-surface ironing with a pattern the slicer does not have,
a polishing pass over a bridge, and the interlocked first layer over a wave field that came
out of the overhang experiment. Support interface ironing is one caller of it.

Paths come back with role `Ironing`, so the pass prints at `ironing_speed` and is coloured
as ironing in the preview without the plugin having to ask for either. Getting that to hold
inside a support layer took three small engine changes, written up in `STATUS.md` 6.32.

## Settings, and what they cost

`settings.lua` carries the defaults: `spacing = 0.1`, `flow_ratio = nil` (worked out),
`min_flow = 0.2`, `max_run_time = 60`, `purge_volume = 30`. **They pair with
`ironing_speed = 60` in the print profile** — see below.

What the pass costs the extruder is a rate, not a quantity:

```
mm3/s = flow_ratio x layer_height x spacing x ironing_speed
```

At the defaults above with a 0.3 mm support contact layer that is 0.216 mm3/s. Leave
`ironing_speed` at its own default of 15 and the same settings give 0.054 — a hundredth of
ordinary printing, held four times as long, which is how an ironing pass clogs a nozzle. Two
of those four terms are not the plugin's to set, so `min_flow` guards the product: the lines
widen until the rate clears it, which costs line density and nothing else, because deposit per
unit area is `flow_ratio x layer_height` whatever the spacing is.

**`flow_ratio` is worked out rather than guessed.** The pass is meant to fill the valleys
between the interface lines, and the interface is fully described by what the hook hands over.
A solid slab one layer high over one line spacing is `spacing x h`; the lines themselves are
`width x h - h^2 (1 - pi/4)`; the difference is the valleys. Deposit over the area is
`flow_ratio x h` whatever the pass's own spacing, so:

```
flow_ratio = 1 - (width x h - h^2 (1 - pi/4)) / (spacing x h)
```

Checked against G-code: predicted bead cross-section 0.1007 mm2 against 0.1007 measured, and
0.3975 where filling the valleys by hand needed 0.40. Set a number to pin it — lower irons
without filling, and higher builds rather than irons, until the deposit closes
`support_material_contact_distance` and welds the support to the object.

**`max_run_time` guards the other half, and it is the half a large surface cannot escape.**
What starves an extruder is a low flow *held for a long time*: the melt stops turning over and
the filament above the heat break, having stopped moving, stops carrying heat away. A pass
takes `area / (spacing x ironing_speed)`, so a fine spacing over a big interface is minutes
however the flow is set. Measured at 225 °C on a 1352 mm2 interface: **226 s unbroken clogged
the nozzle; 63 s at the same flow did not.** Reaching 66 s by widening the lines alone needs a
0.347 mm spacing — the interface's own pitch, at which the pass stops doing anything — and
holding 0.1 mm while finishing in 66 s would need 205 mm/s. There is no setting that buys
both.

So the plugin says how long it dares run and the slicer breaks the pass up, printing one piece
of the layer's own work — an island's perimeters, or its infill — in each gap. On the model
above that turns one 226 s run into three of 75 s, with **19 and 23 mm3 pushed through the
nozzle in the two gaps at 11-12 mm3/s**: a full turnover of the melt zone each time, at 55x
the ironing rate. Nothing is added to the print and nothing is wasted; only the order changes.
A layer with nothing to interleave with runs the pass unbroken rather than pausing on the
surface it is smoothing.

**`purge_volume` is what makes those breaks work when the layer has little of its own to
give.** One island is one break; a pass needing seven has nowhere else to go. So the slicer
lays plain extrusion in the room the object's own sparse infill leaves on the same layer and
spends this much at each break — inside the part, at the same Z so nothing stands proud for
the next layer's nozzle, needing no wipe tower and no space on the bed. The cost is filament,
which stays in the object as extra material. A melt zone is 15-40 mm3, which is the scale at
which a break turns it over; room is finite (about 98 mm3 on the test model) and the log says
so when it finds less. Measured: three runs become four of ~56 s, the gaps grow from 1.6/2.1 s
to 4.6/5.1/2.2 s, and 90.9 mm3 goes through the nozzle across three breaks — 30.3 mm3 each
against the 30.0 asked for, at a cost of 0.11 g and 18 s. Needs engine API 1.3.0.

Prefer a standard nozzle to a high flow one for this. A high flow nozzle earns its name with a
longer melt zone, and at the flow rate an ironing pass runs at, longer melt zone means longer
cooking.

Sliced on a CORE One, plain 0.4 nozzle, 0.20 mm SPEED, supports everywhere,
`support_material_interface_spacing = 0`, `ironing_speed = 60`:

| model | interface | ironing added | unbroken | filament | estimated time |
|---|---|---|---|---|---|
| `wave_overhang.stl` | 20 x 20 mm | 3 763 mm over 192 lines | 1.0 min | 1 569.0 -> 1 574.6 mm | 12m06s -> 13m11s |
| `wave_overhang_shapes.stl` | 60 x 20 mm, notched | 13 524 mm over 632 lines | 3.8 min | 4 003.7 -> 4 023.9 mm | 22m57s -> 26m50s |

Nothing else in either file changed: every other extrusion role comes out at exactly the same
length and move count.

## Expect the supports to be harder to remove

Adhesion and finish are the same quantity seen twice. The object is cast against the interface
and binds to it exactly where the two touch, so anything that makes the mould flatter makes
the bond stronger. A comparison against OrcaSlicer's support ironing on a real print made this
plain: theirs needed a knife to prise off and left the better surface, ours came away easily
and left the worse one. Supports that need a knife are the receipt.

## Running it

Symlink the bundle into the slicer's datadir, by the name in `manifest.json`:

```bash
ln -sfn "$PWD/com.github.dzwiedziu-nkg.support-ironing" \
    ~/.config/PrusaSlicer3-dev/lua/
```

Then slice anything with supports on. `settings.lua` is re-read on every slice.

## License

AGPL-3.0-only, the same licence as PrusaSlicer itself. The full text is in `LICENSE`.
