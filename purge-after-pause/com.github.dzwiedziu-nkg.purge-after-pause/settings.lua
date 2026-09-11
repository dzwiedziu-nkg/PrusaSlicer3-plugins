-- Settings for the purge-after-pause plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- How much plain plastic to put through the nozzle before the layer's own work, in mm3.
    --
    -- The quantity that matters is the melt zone, which is 15-40 mm3 on a typical hot end:
    -- below that, some of what was sitting in the nozzle through the pause is still in there
    -- when the first perimeter is printed. 25 is a middle default. A layer with less room than
    -- this gives what it has rather than refusing.
    --
    -- Measured on a 19.5 mm square with a pause at Z = 10.2: the stock resume primes 1.68 mm3
    -- and reaches the external perimeter after about 7.8 mm3 in total.
    volume = 25.0,

    -- Which interruptions to purge after. The kinds are the slicer's own:
    -- Pause, ColorChange, ToolChange, Template, Custom.
    --
    -- Template and Custom are left out by default because they are whatever the user put
    -- there, and that may not stop the print at all.
    kinds = {Pause = true, ColorChange = true, ToolChange = true},

    -- Don't bother when the layer has less than this much room, in mm3.
    --
    -- A layer that is solid throughout has nowhere to put a purge, and one with barely any
    -- room is not worth the travel: the drip lands on the way there and what fits is too
    -- small to replace what is in the melt.
    min_spare_volume = 5.0
}
