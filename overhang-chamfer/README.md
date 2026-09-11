# Overhang chamfer — a PrusaSlicer slicing plugin

A `slicing.slice_planner` plugin for PrusaSlicer 3.x. It **chamfers small 90° overhangs away**,
so the printer never lays a bead onto air where a chamfer would have done.

## The problem

A layer is an outline cut from the mesh at one height, and the slicer prints it whether or not
the printer can hold it up. Where the model juts sideways, the layer above starts in mid-air:
the bead curls downward, the nozzle drags through the curl on the next pass, and the underside
comes out rough.

The stock answer is support. Support has to be printed, has to be removed, costs material and
time, and leaves a mark on the face it was cast against. For a big overhang that is the right
trade. For a 1 mm ledge it is a lot of machinery for very little.

## What it does

It lets each layer's outline reach only so far past the layer below. Walked from the bed up,
that is a chamfer: the ledge is built over several layers, every one of them resting on the one
under it, and nothing is ever printed onto air.

How far "so far" is comes from an angle, in the convention `support_material_threshold` uses —
**90° is vertical, and the number is the most horizontal slope printable without support.** A
layer may then grow by `layer_height / tan(angle)`:

| angle | growth per 0.2 mm layer | a 2 mm ledge resolves in |
|---|---|---|
| 10° | 1.134 mm | 2 layers, 0.4 mm |
| 25° | 0.429 mm | 5 layers, 1.0 mm |
| **35°** | **0.286 mm** | **8 layers, 1.6 mm** |
| 45° | 0.200 mm | 10 layers, 2.0 mm |
| 90° | 0 mm | never — vertical, the outline cannot grow |

**35° is the default because that is what `support_material_threshold` is set to** in the stock
profiles. That is enough to stop the printer laying beads onto air. It is *not* enough to stop
the support generator, which wants a margin — see below, where the margin is worked out and
measured.

## What it costs

**It removes material from the model.** That is not a side effect, it is the mechanism: the
chamfer is the ledge minus its underside. The part comes off the bed a little smaller than the
mesh along every edge that was chamfered.

So the setting that matters is not the angle, it is `max_width` — the most material the chamfer
is allowed to cut away. It does two jobs:

- **It keeps the chamfer to the edges.** An overhang too big to fit under it is left alone in
  one piece and the support generator deals with it as it always did. Chamfering only the outer
  rim of a big ledge would be the worst of both: a reshaped part *and* an overhang that still
  needs support.
- **It bounds a slope shallower than the angle asked for.** A shallow cone is a 90° overhang
  nowhere and slightly too shallow everywhere. Each layer is measured against the outline the
  layer below was *left* with, so the shortfall accumulates until it no longer fits under
  `max_width`, and the layer is then handed back in full. The model is never further than
  `max_width` from what the mesh says — whatever the geometry.

`max_width = 0` means no limit. It will eat an entire table top. Do not.

Two things are never touched: the bottom layer, which has nothing under it to be measured
against, and an island with nothing at all under it — a feature that starts at that height
rather than a ledge on one already being printed, where trimming would delete geometry instead
of chamfering it.

## What it buys, measured

A tower of three 1 mm ledges — every overhang on it fits inside the default `max_width` — with
supports on and `support_material_threshold = 35`:

| | no plugin | 35° | 40° | **46°** |
|---|---|---|---|---|
| overhang perimeter | 48.6 mm³ | **0.0** | **0.0** | **0.0** |
| bridge infill | 240.4 mm³ | 171.2 | 171.2 | 171.2 |
| support material | 1006.6 mm³ | 996.8 | 370.1 | **0.0** |
| material | 4.23 cm³ | 4.20 | 3.39 | **3.28** (−22 %) |
| estimated time | 15m 38s | 14m 50s | 13m 45s | **13m 5s** (−16 %) |

**Every 90° overhang is gone at the default angle** — not reduced, zero. What did *not* happen
at 35° is the support going away, and that is worth knowing about before you set the angle.

### Matching `support_material_threshold` is not enough to lose the support

Two reasons, both in the slicer rather than in the model:

- The support generator adds a degree to the threshold to make it inclusive
  (`SupportMaterial.cpp`: `+1 makes the threshold inclusive`), so with the setting at 35 it
  actually allows `layer_height / tan(36°)`.
- It measures that **perpendicular to the wall**, and at a square corner the outline advances
  `d·√2` — so the corners are what it still finds.

Which gives the angle that clears it:

```
angle ≥ atan( tan(support_material_threshold + 1) × √2 )
```

= **45.8° for a threshold of 35**. The prediction lands exactly: support is 389 mm³ at 45° and
**0.0 mm³ at 46°**, and what is left at 40–45° is four thin columns at the corners of the part,
about 18 extrusions a layer.

So: **35° to stop printing onto air, 46° to also stop printing support.** The second costs more
of the model.

### The safety catch, measured

The same tower with 1 mm, 2 mm and **4 mm** ledges, at the default 35° and `max_width = 2.0`:

| | no plugin | with the plugin |
|---|---|---|
| overhang perimeter | 56.8 mm³ | **23.3 mm³** |

The 23.3 mm³ left is the 4 mm ledge, untouched — it does not fit under `max_width`, so it is
left whole for the support generator, exactly as intended. The 1 mm and 2 mm ledges went to
zero. Measured layer by layer, the outline steps out 0.286 mm per 0.2 mm layer over the 2 mm
ledge and takes 8 layers to arrive, which is `layer_height / tan(35°)` to three decimals.

Null case: no plugin installed, plugin installed with `angle = 0`, and the plugin at 35° on a
model with no overhang at all — all three give byte-identical G-code.

## Settings

`settings.lua` next to the Lua source. Edit and slice again; no restart, no rescan. It is read
inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and the
defaults apply.

| setting | default | what it does |
|---|---|---|
| `angle` | `35` | The shallowest slope the chamfer will produce, in degrees from horizontal; 90 is vertical. Match it to `support_material_threshold` and the chamfer lands exactly where support stops. `0` turns the plugin off. |
| `max_width` | `2.0` | The most material the chamfer may cut away, in mm, measured as the largest disc that fits inside it. The safety catch — see above. `0` means no limit. |
| `min_z` | `0.0` | Leave everything below this height alone. Worth setting when the bottom of the part has to come out dimensionally right. |

## The other way round

Taking the overhang off is one of two answers; the other is to put material under it, which is
[`make-overhang-printable`](../make-overhang-printable/) — OrcaSlicer's feature of that name.
That one loses nothing of the model and gains a cone you may have to trim; this one loses a
little of the model and gains nothing to trim. On a small ledge this is usually the better trade,
which is what this plugin is for.

**They cannot both be installed.** Both are `slicing.slice_planner` and the slicer loads one
plugin of each type, so symlink one or the other.

## The hook it needs

`slicing.slice_planner`, which is not "chamfer overhangs" but:

> given a layer as it comes off the mesh, decide how far its outline may reach past the layer
> below.

The same mechanism serves a plugin that makes only the first few millimetres self-supporting,
one that tightens the angle towards the top of a tall part where a curled overhang would be hit
by the nozzle on the way round, and one that leaves the model alone below a given Z. What it
cannot do is add material — a clip only ever removes.

Requires the fork: <https://github.com/dzwiedziu-nkg/PrusaSlicer>.

## Running it

Symlink the bundle into the slicer's datadir, by the name in `manifest.json`:

```bash
ln -sfn "$PWD/com.github.dzwiedziu-nkg.overhang-chamfer" \
    ~/.config/PrusaSlicer3-dev/lua/
```

## License

AGPL-3.0-only. See `LICENSE`.
