-- Settings for the bridge-counterbore-hole plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- Set to false to turn the plugin off without removing it.
    enabled = true,

    -- The largest opening that may be closed, in mm, measured as the largest disc that fits
    -- inside it.
    --
    -- **This is the whole of the safety and 0 does not mean "no limit" here**, unlike the other
    -- plugins on this extension point - it means the same as everywhere else, no limit, and
    -- that is the wrong thing to ask for. A sacrificial layer across a 30 mm bore is a disc
    -- somebody has to cut out of the middle of a part.
    --
    -- 10 mm covers a screw counterbore, which is what this is for. A hole wider than this is
    -- left to the slicer, which bridges the ring round it and prints its wall in mid-air, as it
    -- always did.
    max_hole = 10.0,

    -- How far a hole's rim has to hang over air before the hole is closed, as an angle.
    --
    -- PrusaSlicer's convention, the one `support_material_threshold` uses: 90 is vertical and
    -- the number is the most horizontal slope printable without support. The rim is measured
    -- `layer_height / tan(angle)` wide - 0.286 mm at 35 degrees and 0.2 mm layers - and most of
    -- that band has to be over air for the hole to count.
    --
    -- This is what keeps an ordinary hole alone: a hole going straight down has a rim resting
    -- on the layer below, and so does a bore that tapers gently. Lower the angle to catch
    -- gentler steps, raise it to catch only the sharp ones.
    angle = 35,

    -- Leave everything below this height alone, in mm. 0 acts everywhere.
    min_z = 0.0
}
