# Island print order — a PrusaSlicer slicing plugin

A `slicing.island_order` plugin for PrusaSlicer 3.x. It decides the order in which the
disjoint islands of a layer are printed, so that the print head travels less between them.

## What it does

When an object splits into several separate regions on a layer — towers above a common
base, a plate with many parts on it — the stock slicer chains those islands once, at
slicing time, before anything is known about where the head will be when the layer starts.
The head therefore tends to return to the same island at the beginning of every layer.

This plugin is asked during G-code export instead, where the head position is known. It
runs a greedy nearest neighbour chain seeded from that position, then refines it with
2-opt on the open path.

Measured on a 300 x 20 x 20 mm test model that splits into 15 islands (Original Prusa XL,
0.20 mm SPEED, 7 runs per variant):

| variant | mean travel | min | max | sd | vs stock |
|---|---|---|---|---|---|
| stock | 39 921 mm | 38 208 | 40 794 | 883 | — |
| plugin | 29 020 mm | 29 020 | 29 020 | 0.2 | **-27.3 %** |

Extruded length was 343 739.4 mm in all 14 runs: the plugin changes the order only, never
the geometry or the amount of material.

The plugin also makes the result reproducible. Stock ordering varies by about 2 % between
runs of the same input; with the plugin the spread collapses to 0.2 mm.

## Requirements

A PrusaSlicer build that provides the `slicing.island_order` plugin API. See
`doc/Plugin_API.md` in the slicer sources for the API contract.

## Installing

Symlink or copy the bundle directory into the slicer's plugin directory and restart the
slicer (or use Plugins -> Rescan):

```bash
ln -s "$PWD/com.github.dzwiedziu-nkg.island-order" ~/.config/PrusaSlicer/lua/
```

The plugin has no menu entry — it is not user invoked. It hooks into slicing, and the log
reports which island ordering plugin is in use at the start of every export:

```
[info] Island ordering plugin in use: com.github.dzwiedziu-nkg.island-order.island_order
```

To turn it off, remove the bundle from the plugin directory.

## Limitations

- Distances are measured between island centroids, not between the actual exit and entry
  points of the head, and they ignore `avoid_crossing_perimeters`, retractions and z-hop.
- 2-opt is skipped above 100 islands per layer; the greedy chain still applies.
- **Layer cooling time is not taken into account.** Shortening the travel between islands
  also shortens the time before the head returns to the same island, which is the very
  thing `slowdown_below_layer_time` exists to prevent. On small, closely spaced islands
  this plugin can therefore trade travel for overheating. Handling that is the next step.
- One object instance is ordered per call; the order between instances is decided
  elsewhere in the slicer.
