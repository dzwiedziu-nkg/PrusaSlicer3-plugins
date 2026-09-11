-- Settings for the make-overhang-printable plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- The steepest underside the model is allowed to keep, in degrees.
    --
    -- PrusaSlicer's convention, the one `support_material_threshold` uses: 90 is vertical and
    -- the number is the most horizontal slope printable without support. Anything shallower
    -- than this gets a cone of new material under it, sloping at exactly this angle, built
    -- down until it reaches the part or the bed.
    --
    -- OrcaSlicer's `make_overhang_printable_angle` is the same quantity measured from the
    -- other side - it defaults to 55, which is 90 - 55 = 35 here. Measured on OrcaSlicer's own
    -- output the cone advances 0.2855 mm per 0.2 mm layer, and `0.2 / tan(35 deg)` is 0.2856.
    -- So 35 here and 55 there are the same setting, and this is that default.
    --
    -- Lower is gentler and costs more material: at 0.2 mm layers the cone spreads 1.134 mm a
    -- layer at 10 degrees, 0.286 at 35, 0.200 at 45. 90 turns the plugin into a vertical
    -- extrusion of every overhang all the way to the bed, which is almost never what you want.
    angle = 35,

    -- The most material the cone may add, in mm, measured as the largest disc that fits inside
    -- the piece about to be added. An overhang too big to fit under it is left alone and the
    -- support generator deals with it as it always did.
    --
    -- 0 means no limit, and 0 is the ordinary setting here - the whole point is usually to
    -- carry an overhang of any size, and unlike a chamfer a cone cannot run away, because it
    -- terminates where it meets the part or the bed.
    max_width = 0,

    -- Leave everything below this height alone, in mm. 0 acts everywhere.
    min_z = 0.0
}
