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
| [`radial-bridge/`](radial-bridge/) | `slicing.fill_planner` | Bridges an annular gap with spokes from the inner island to the surrounding wall, instead of parallel lines across the whole opening. |
| [`support-ironing/`](support-ironing/) | `slicing.pass_planner` | Irons the top of a support interface, so the underside of the overhang cast against it comes out smooth. |
| [`wipe-tower-cancel/`](wipe-tower-cancel/) | `slicing.object_labels` | Puts the wipe tower on the list of objects the printer can cancel mid-print. |

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
