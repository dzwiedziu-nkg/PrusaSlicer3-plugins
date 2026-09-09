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

`settings.lua` carries the defaults. The two that matter are `spacing` (0.2 mm) and
`flow_ratio` (0.15, the same as the slicer's own `ironing_flowrate`).

**Read `STATUS.md` 6.33 before lowering `spacing`.** What a pass extrudes per second is
`flow_ratio x layer_height x spacing x ironing_speed`, and at the slicer's own ironing
defaults that is 0.068 mm3/s — a ninetieth of the flow that laid down the surface being
ironed, held without a break for as long as the pass lasts. That is how an ironing pass clogs
a nozzle. `spacing = 0.2` with `ironing_speed = 30` in the print profile gives 0.270 mm3/s and
cuts the pass to a quarter of the time, depositing exactly the same amount of plastic.

Sliced on a CORE One, plain 0.4 nozzle, 0.20 mm SPEED, supports on everywhere,
`ironing_speed = 30`:

| model | interface | ironing added | unbroken | filament | estimated time |
|---|---|---|---|---|---|
| `wave_overhang.stl` | 20 x 20 mm | 1 882 mm over 96 lines | 1.0 min | 1 521.2 -> 1 528.3 mm | 11m45s -> 12m48s |
| `wave_overhang_shapes.stl` | 60 x 20 mm, notched | 6 762 mm over 316 lines | 3.8 min | 3 836.6 -> 3 861.9 mm | 21m46s -> 25m35s |

Nothing else in either file changed: every other extrusion role comes out at exactly the same
length and move count. The pass is purely additive, and it costs 20 mm of travel on the square
and 146 mm on the notched model.

Prefer a standard nozzle to a high flow one for this. A high flow nozzle earns its name with a
longer melt zone, and at the flow rate an ironing pass runs at, longer melt zone means longer
cooking.

## Running it

Symlink the bundle into the slicer's datadir, by the name in `manifest.json`:

```bash
ln -sfn "$PWD/com.github.dzwiedziu-nkg.support-ironing" \
    ~/.config/PrusaSlicer3-dev/lua/
```

Then slice anything with supports on. `settings.lua` is re-read on every slice.

## License

AGPL-3.0-only, the same licence as PrusaSlicer itself. The full text is in `LICENSE`.
