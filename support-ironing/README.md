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

> **Status: nothing here works yet.** This is the design and the repository, written before
> the code. Nothing has been sliced and nothing has been printed.

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

Paths come back with role `Ironing`, so the engine's existing `ironing_speed` and flow
handling apply without the plugin having to ask for them.

## License

AGPL-3.0-only, the same licence as PrusaSlicer itself. The full text is in `LICENSE`.
