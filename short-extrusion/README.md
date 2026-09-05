# Short extrusion filter — a PrusaSlicer slicing plugin

A `slicing.extrusion_filter` plugin for PrusaSlicer 3.x. It drops extrusions too short to
be worth the travel that reaches them.

## The problem

A fill pattern clipped against a contour leaves stubs behind. In a corner where the grid
meets the wall at a shallow angle, an infill line survives for about a millimetre. An
internal perimeter squeezed between two features comes out as a sliver.

The stub itself contributes nothing. What it costs is a travel to reach it, a retraction,
the extrusion, another retraction and a travel away — and on a tall part with four such
corners, that repeats on every single layer.

On the test model, 1704 of 1769 internal infill runs were shorter than 2 mm. Together they
laid down 2.2 m of material and caused 76 m of head movement.

![Two corners of a garage, each holding a short internal infill run](doc/small_extrusion.png)

The two dark stubs in the corners are what internal infill amounts to on a part like this
one — the legend puts the whole of it at 2.7 % of the print time for 0.28 m of filament.
They are there because the grid meets the wall at a shallow angle, and they come back on
every layer of the wall.

## What this does

The slicer asks the plugin about every perimeter and infill path *before* travels and
seams are decided, so a rejected path disappears together with the movement that would
have reached it — and the paths that remain get routed as if it had never existed. That
second part matters: most of the saving comes not from skipping the detour but from the
infill traversal being re-optimised once the stubs are gone.

![The same two corners with the stubs dropped](doc/removed_small_extrusions.png)

Same corners, same walls, no stubs. The slicer's own estimate for that model drops from
1 h 26 m to 1 h 22 m 30 s — a different garage from the one measured below, and a smaller
saving than the table shows, which is what a shorter and simpler part looks like.

Roles are handled by an **allowlist**. Only `Perimeter` (internal perimeters),
`InternalInfill` and `SolidInfill` are ever considered; everything else is kept by
construction, so the external perimeter, the top surface, bridges, gap fill, supports and
the skirt are out of reach and stay out of reach when a future slicer version adds a role.

## Measurements

Test model: a garage, Prusa Core One 0.4 nozzle, 0.2 mm layers, 15 % grid infill, 2
perimeters. Threshold 2 mm, first layer protected.

| | baseline | filtered | |
|---|---|---|---|
| travel | 84 748 mm | 8 666 mm | **−89.8 %** |
| retractions | 1 917 | 221 | **−88.5 %** |
| extrusion | 408 443 mm | 406 254 mm | −0.5 % |
| print time | 137.6 min | 126.9 min | **−7.8 %** |

1 720 of 4 161 extrusions dropped, for 0.5 % less material.

Per role, so it is clear what was and was not touched:

| role | baseline runs / mm | filtered runs / mm |
|---|---|---|
| External perimeter | 889 / 173 110 | 889 / 173 110 |
| Perimeter | 889 / 172 727 | 889 / 172 727 |
| Top solid infill | 425 / 5 862 | 425 / 5 862 |
| Bridge infill | 2 / 9 064 | 2 / 9 064 |
| Internal infill | 1 769 / 7 175 | 65 / 5 002 |
| Solid infill | 182 / 40 461 | 171 / 40 445 |

Top solid infill holds nine runs under 2 mm of its own; they survived, which is the
allowlist doing its job.

## Settings

**There is no user interface for this — the file is the interface.** PrusaSlicer's
_Plugins_ menu, and the parameter dialog behind it, only ever list plugins of type
`project.plugin`, the ones you invoke yourself. A slicing plugin is not invoked; it hooks
into the slicing itself, so it never appears there and has nothing to click. Everything it
can be told is in `settings.lua`.

The file lives inside the plugin's bundle directory, next to the plugin's own `.lua`:

```
~/.config/PrusaSlicer3-dev/lua/com.github.dzwiedziu-nkg.short-extrusion/settings.lua
```

If you installed the plugin by symlinking your checkout — which is the sane way — that
path is the symlink and editing the file in the checkout is the same thing.

It is a Lua file that returns one table, so an entry is `key = value,` with the comma, and
`--` starts a comment. Strings take quotes, booleans are `true` / `false`, and a value in
`{ }` is a table of its own. Comment a line out and the plugin's built-in default applies:

```lua
return {
    min_length = 3.0,   -- the rest keep their defaults
}
```

**Save it and slice again — that is all.** No restart, no _Rescan_: the plugin directories
are read afresh for every slice.

One warning about how it fails. The plugin loads the file inside a `pcall`, so a **syntax
error is not reported anywhere** — the file is simply ignored and every default applies. If
a change of yours seems to do nothing at all, that is the first thing to suspect: a missing
comma, a missing brace, a stray quote.

The keys, in full:

| key | default | meaning |
|---|---|---|
| `min_length` | `2.0` | An extrusion shorter than this, in mm, is dropped. |
| `min_length_by_role` | `{}` | Per role overrides of `min_length`. |
| `filtered_roles` | `Perimeter`, `InternalInfill`, `SolidInfill` | The only roles the filter may touch. |
| `first_filtered_layer` | `1` | Layers below this index are never filtered; they carry the bed adhesion. |

Two of those take tables rather than numbers, so in full:

```lua
return {
    min_length = 2.0,
    -- Per role, overriding min_length. A role not named here uses min_length.
    min_length_by_role = {
        SolidInfill = 3.0,      -- stricter: solid regions carry load
        InternalInfill = 1.5,   -- looser: nothing depends on a stub in there
    },
    -- The allowlist. A role that is not in here is never even considered, so the
    -- external perimeter, top surfaces, bridges, gap fill, supports and the skirt
    -- are out of reach by construction. Removing a role from the list is safe;
    -- adding one is the change to think about.
    filtered_roles = {Perimeter = true, InternalInfill = true, SolidInfill = true},
    first_filtered_layer = 1,
}
```

The role names are the slicer's own, spelled as in the G-code viewer's legend:
`Perimeter`, `ExternalPerimeter`, `OverhangPerimeter`, `InternalInfill`, `SolidInfill`,
`TopSolidInfill`, `Ironing`, `BridgeInfill`, `GapFill`, `Skirt`, `SupportMaterial`,
`SupportMaterialInterface`, `WipeTower`.

## Choosing a threshold

Below roughly three or four nozzle diameters a segment adds almost nothing to the part,
while the travel and the two retractions around it cost real time. 2 mm on a 0.4 mm nozzle
is a conservative starting point. Raise it while watching the extrusion total: as long as
the material removed stays a fraction of a percent, the stubs really were noise.

Be stricter with `SolidInfill` than with `InternalInfill` — solid regions carry load and
sit under top surfaces, so removing pieces of them is more visible.

## Requirements

**This plugin does not work with an official PrusaSlicer release.** The `slicing.extrusion_filter` API does
not exist in PrusaSlicer 3.x as shipped; it is added by a fork:

- the fork, branch `main`, which carries all five hooks: https://github.com/dzwiedziu-nkg/PrusaSlicer
- how to build and run it: https://github.com/dzwiedziu-nkg/PrusaSlicer/blob/main/doc/Build_plugin_fork.md
- the API contract: `doc/Plugin_API.md` in those sources

Prusa have said they intend to expose the slicing pipeline to plugins themselves. When they
do, this plugin should be rewritten against their interface and the fork dropped.

## Installing

Symlink or copy the bundle directory into the slicer's plugin directory. The directory
name has to match the `id` in `manifest.json`.

```bash
ln -s "$PWD/com.github.dzwiedziu-nkg.short-extrusion" ~/.config/PrusaSlicer/lua/
```

The plugin has no menu entry — it is not user invoked. The log names it at the start of
every export and reports what it removed at the end:

```
[info] Extrusion filter plugin in use: com.github.dzwiedziu-nkg.short-extrusion.short_extrusion
[info] Extrusion filter plugin ... dropped 1720 of 4161 extrusions
```

To turn it off, remove the bundle from the plugin directory.

## Measuring

`tools/runs.py <gcode> [threshold]` groups a G-code file into extrusion runs — maximal
sequences of extruding moves not interrupted by a travel — and reports, per `;TYPE:`
label, how many fall below the threshold and how much material they represent. It is how
the tables above were produced, and it is model independent.

`tools/travel.py <gcode>` sums the non-extruding moves.

## Limitations

- The plugin sees one path at a time and cannot tell that two stubs it is dropping were
  the only thing anchoring a region.
- Dropping infill reduces material, so at aggressive thresholds it will eventually show up
  in part strength. The default is deliberately conservative.
- A short path is judged by its own length only; a 1.5 mm stub in the middle of dense
  infill, with nothing to travel for, is dropped just like an isolated one. It costs
  nothing to keep such a path, so a future version could weigh the travel it actually
  saves.

## License

AGPL-3.0-only, the same licence as PrusaSlicer itself. The full text is in `LICENSE`.
