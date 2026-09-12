-- Settings for the overhang-by-size plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- The slope both remedies aim for, in degrees.
    --
    -- PrusaSlicer's convention, the one `support_material_threshold` uses: 90 is vertical and
    -- the number is the most horizontal slope printable without support. 35 is what that
    -- setting is set to in the stock profiles. `0` turns the plugin off.
    --
    -- Note that 35 stops the printer laying beads onto air but does not stop the support
    -- generator, which wants a margin: `atan(tan(threshold + 1) * sqrt(2))`, or 46 degrees for
    -- a threshold of 35. See the overhang-chamfer README for why.
    angle = 0,

    -- Overhangs up to this wide, in mm, are cut off. Wider ones are carried on a cone.
    --
    -- This is the whole point of the plugin. A small ledge is cheaper to lose than to hold up:
    -- cutting it costs a sliver of the model and nothing to clean off. A big one is the other
    -- way round - chamfering it would reshape the part and still leave an overhang - so it
    -- gets the cone instead.
    --
    -- Measured as the largest disc that fits inside the piece in question, which is the same
    -- measure both remedies use.
    cut_below = 2.0,

    -- The most material the cone may add, in mm, once the plugin has decided to carry rather
    -- than cut. 0 is no limit, which is what OrcaSlicer does and the ordinary setting - a cone
    -- cannot run away, it terminates where it meets the part or the bed.
    carry_max = 0,

    -- Leave everything below this height alone, in mm. 0 acts everywhere.
    min_z = 0.0
}
