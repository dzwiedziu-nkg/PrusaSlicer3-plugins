-- Settings for the reverse-on-even plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- Set to false to turn the plugin off without removing it. Every loop then keeps the
    -- direction the slicer chose, and the G-code is the stock G-code.
    enabled = true,

    -- Which layers get turned round, as `layer_id % 2`.
    --
    -- 1 is every other layer starting with the second, which is what OrcaSlicer does and what
    -- their option is named after. 0 is the other half of the layers and is indistinguishable
    -- a few layers up; it exists so the alternation can be lined up with something else.
    phase = 1,

    -- Only turn a layer round where a wall of it is laid over air.
    --
    -- On by default, because that is what the effect is for: a wall resting on solid material
    -- is not being dragged anywhere and reversing it buys nothing. Set to false to alternate
    -- every layer of the part regardless, which is what OrcaSlicer's `overhang_reverse_threshold
    -- = 0` does, and which is the setting to use for warping rather than for overhangs.
    --
    -- Note that PrusaSlicer only marks a wall as overhanging when `overhangs` ("Detect bridging
    -- perimeters") is on in the print settings. With it off nothing is ever marked, so this
    -- plugin would never fire; turn this off as well in that case.
    require_overhang = true,

    -- How much wall over air an island needs before its layer is turned round, in mm.
    --
    -- 0 means any at all, which is what OrcaSlicer's default of 50 % of the line width works
    -- out to: their threshold is a depth, `threshold - 0.5 * line_width`, and at 50 % that is
    -- exactly zero, so any part of the wall outside the layer below counts.
    --
    -- **This number is not their number.** Theirs measures how far the wall reaches past the
    -- layer below; this measures how much of the wall does. They agree at the default and
    -- nowhere else, so read this as "ignore islands with less than this much wall in mid-air",
    -- which on a 0.4 nozzle is roughly one bead per millimetre of it.
    min_overhang_length = 0.0,

    -- Leave the wall that shows alone and turn only the walls behind it.
    --
    -- OrcaSlicer's `overhang_reverse_internal_only`. The external perimeter is the face of the
    -- part, and reversing it moves where its seam ends up on alternating layers; the walls
    -- behind it carry most of the stress and nobody sees them. Their own advice is to use this
    -- with the threshold off, for warping rather than for overhangs.
    internal_only = false,

    -- Leave this many layers at the bottom alone, counted from the bed.
    --
    -- 1 by default and mostly belt and braces: with `phase = 1` the first layer is even and is
    -- never turned anyway. It matters when `phase` is 0, where the first layer would otherwise
    -- be reversed, and the first layer is about adhesion rather than about stress.
    skip_first_layers = 1
}
