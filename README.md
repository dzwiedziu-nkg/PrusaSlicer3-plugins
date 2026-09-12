# PrusaSlicer 3 slicing plugins

Lua plugins that change how PrusaSlicer 3 slices: what order the head visits things in, what
it lays down, and what it does over a surface it has already covered.

**They do not work on stock PrusaSlicer.** Stock 3.x runs Lua plugins, but only the
user-invoked kind — the ones under the _Plugins_ menu, which act on the model before slicing.
Every plugin here hangs off a *slicing* extension point that the stock slicer does not have,
so it needs the fork:

**<https://github.com/dzwiedziu-nkg/PrusaSlicer>**, branch `main`.

The fork adds the extension points and nothing else. Each is a place where the slicer stops
and asks a question it would otherwise answer itself, and with no plugin installed the G-code
is bit for bit the stock output — that is checked for every one of them.

## The plugins

| directory | extension point | what it does |
|---|---|---|
| [`island-order/`](island-order/) | `slicing.island_order` | Chooses which of a layer's disjoint islands to print next, so a tall thin one is not returned to while it is still soft. |
| [`sequential-islands/`](sequential-islands/) | `slicing.island_sequence` | Finishes one upper part of an object to the top before starting the other, once they have split from a common base. Experimental. |
| [`short-extrusion/`](short-extrusion/) | `slicing.extrusion_filter` | Drops extrusions too short to be worth the travel that reaches them. |
| [`cross-hatch/`](cross-hatch/) | `slicing.fill_planner` | Lays sparse infill as one family of lines that holds its direction for a few millimetres and then turns ninety degrees, so the infill is stiff without welding itself into one continuous wall. **A reimplementation of OrcaSlicer's Cross Hatch.** |
| [`gradient-infill/`](gradient-infill/) | `slicing.fill_planner` | Packs the sparse infill closer near the walls and lets it open out towards the middle, so the material goes where the part is stiffest. |
| [`radial-bridge/`](radial-bridge/) | `slicing.fill_planner` | Bridges an annular gap with spokes from the inner island to the surrounding wall, instead of parallel lines across the whole opening. |
| [`support-ironing/`](support-ironing/) | `slicing.pass_planner` | Irons the top of a support interface, so the underside of the overhang cast against it comes out smooth. |
| [`alternate-extra-wall/`](alternate-extra-wall/) | `slicing.perimeter_planner` | Adds one wall on every other layer, so the infill is wedged between walls instead of meeting the same seam all the way up. |
| [`purge-after-pause/`](purge-after-pause/) | `slicing.resume_planner` | Purges into the room the layer's own infill leaves, first thing after a pause or a colour change, so the wall comes through the pause without a gap and the drip lands inside the part. |
| [`overhang-chamfer/`](overhang-chamfer/) | `slicing.slice_planner` | Chamfers small 90° overhangs away by letting each layer's outline reach only so far past the layer below, so the printer never lays a bead onto air where a chamfer would have done. |
| [`make-overhang-printable/`](make-overhang-printable/) | `slicing.slice_planner` | Carries an overhang on a cone of new material built up from underneath, so it is printed on a slope instead of onto air. **A reimplementation of OrcaSlicer's `make_overhang_printable`.** |
| [`overhang-by-size/`](overhang-by-size/) | `slicing.slice_planner` | Chamfers small overhangs off and carries big ones on a cone, choosing by size — what the two plugins above do, in one. |
| [`wipe-tower-cancel/`](wipe-tower-cancel/) | `slicing.object_labels` | Puts the wipe tower on the list of objects the printer can cancel mid-print. |

**Several of these share a hook, and the slicer loads one plugin of each type** — so where two
rows name the same extension point, symlink one or the other, not both.

- `overhang-chamfer`, `make-overhang-printable` and `overhang-by-size` are all
  `slicing.slice_planner`. They are answers to the same question — take the overhang off, or put
  something under it — and `overhang-by-size` is the superset: it does both, choosing by size.
- `cross-hatch`, `gradient-infill` and `radial-bridge` are all `slicing.fill_planner`. Two
  infill patterns are alternatives the way `fill_pattern` is; `radial-bridge` only touches
  bridges, so it is the one you would most want alongside another, and cannot have.

## Installing one

A slicing plugin is a directory containing `manifest.json` and the Lua that implements the
extension point. It is installed by putting that directory — **named exactly as the `id` in
its `manifest.json`** — into the data directory's `lua/`:

```bash
ln -sfn "$PWD/support-ironing/com.github.dzwiedziu-nkg.support-ironing" \
        ~/.config/PrusaSlicer3-dev/lua/
```

The data directory is `~/.config/PrusaSlicer3-dev` on Linux (the `-dev` suffix comes from the
alpha version the fork tracks). Removing the symlink disables the plugin. The directories are
re-scanned for **every slice**, so editing a `.lua` file takes effect on the next slice — no
restart and no rescan.

## Configuring one

Slicing plugins have no user interface. `PluginSystem::execute_plugin()` refuses anything that
is not a `project.plugin`, so the _Plugins_ menu and its parameter dialog are reachable only by
the user-invoked kind. Every plugin here is configured through a `settings.lua` sitting next to
its Lua source, and each one documents its own settings in its README.

`settings.lua` is read inside a `pcall`, which means **a syntax error in it is reported
nowhere**: the file is ignored and the defaults apply. That is the first thing to suspect when
a setting appears to do nothing.

## Licence

Each plugin carries its own `LICENSE`.
