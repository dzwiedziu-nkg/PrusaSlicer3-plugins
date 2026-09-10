-- Settings for the support interface ironing plugin.
--
-- Edit and slice again; there is no restart and no Plugins -> Rescan. This file is loaded
-- inside a pcall, so a syntax error in it is reported NOWHERE: the file is ignored and the
-- defaults below apply. That is the first thing to suspect when a setting does nothing.

return {
    -- Distance between two ironing lines, in mm.
    --
    -- 0.1 matches what a comparison against OrcaSlicer's own support ironing showed working
    -- on a real print (STATUS.md 6.35): its interface came out visibly smoother than ours at
    -- 0.2, and it irons at 0.1.
    --
    -- **This pairs with `ironing_speed = 60` in the print profile.** What the pass costs the
    -- extruder is a rate:
    --
    --     mm3/s = flow_ratio x layer_height x spacing x ironing_speed
    --
    -- At 0.12 x 0.3 x 0.1 x 60 that is 0.22 mm3/s, which is what Orca ran at and did not
    -- clog. Leave `ironing_speed` at the profile default of 15 and the same settings give
    -- 0.054 mm3/s held four times as long, which is the regime that does clog. `min_flow`
    -- below catches that, by widening the lines rather than letting the rate fall.
    spacing = 0.1,

    -- Fraction of a full layer of material the pass lays down, 0.0 to 1.0.
    --
    -- The slicer's own `ironing_flowrate` defaults to 15 %. 0.12 puts down 0.036 mm over the
    -- surface, which is what Orca deposited on the print that came out better; at 0.15 we
    -- were laying 0.045 mm, and ironing is meant to level a surface rather than build one.
    --
    -- It is not zero because a nozzle dragging over a surface with no pressure behind it
    -- picks material up rather than leaving it.
    flow_ratio = 0.12,

    -- Lowest volumetric flow the pass may run at, in mm3/s. 0 turns the guard off.
    --
    -- Two of the four terms in the rate above are not the plugin's to set: the height of the
    -- support contact layer follows the geometry, and `ironing_speed` lives in the print
    -- profile. When their product drops, the plugin widens its lines until the rate clears
    -- this floor - which costs line density and nothing else, because deposit per unit area
    -- is `flow_ratio x layer_height` whatever the spacing is. Widening stops at one nozzle
    -- width, past which the beads no longer touch and it is not ironing any more.
    --
    -- 0.2 is derived rather than measured: melt zone volume divided by flow is the time a
    -- given parcel of PLA spends at temperature, and a couple of minutes is as far as PLA
    -- should be pushed. See STATUS.md 6.33.
    min_flow = 0.2,

    -- Longest the pass may run without a break, in seconds. 0 runs it in one piece.
    --
    -- min_flow fixes the rate the extruder is held at; this fixes how long it is held
    -- there, which is the other half of the same problem and the one a large surface
    -- cannot escape: the pass takes area / (spacing x speed), so a fine spacing over a
    -- big interface is minutes whatever the flow. Measured on wave_overhang_shapes at
    -- 225 C: 226 s clogged the nozzle, while 63 s and Orca's 66 s at the same flow did
    -- not. When the pass runs longer than this the slicer breaks it up and prints one of
    -- the layer's other islands in each gap, which pulls fresh filament through the heat
    -- break and costs nothing but travel. A layer with nothing to interleave with runs
    -- the pass unbroken rather than pausing on the surface it is smoothing.
    max_run_time = 60.0,

    -- Angle between the ironing lines and the interface lines, in degrees.
    --
    -- 90 crosses every ridge head on, which flattens the most per pass and makes the nozzle
    -- climb each ridge square. 45 is what the slicer's own ironing uses over a top surface.
    -- 0 retraces the interface lines and flattens nothing.
    angle_offset = 45.0,

    -- Absolute angle for the ironing lines, in degrees, if you want to fix the direction
    -- rather than tie it to the interface. nil follows the interface via angle_offset.
    angle = nil,

    -- Iron only surfaces that something is going to be printed onto.
    --
    -- The point of the pass is the imprint left in the object, so by default it runs over
    -- the top contact layer and nowhere else. false irons every support interface,
    -- including the ones with only more support coming on top of them, which costs time and
    -- buys a tidier support tower.
    object_facing_only = true,

    -- Smallest area worth an extra pass, in mm^2. Below this the travel to reach the
    -- island costs more than the finish is worth. 0 irons everything.
    min_area = 1.0,

    -- Shortest ironing line worth extruding, in mm. Shorter spans - the corners of the
    -- area, mostly - are dropped.
    min_length = 0.5,

    -- How far in from the edge of the area the pass stops, in mm.
    --
    -- The engine already hands the plugin an area pulled in by half a nozzle, so 0 is
    -- normally right. Raise it if the pass is dragging material off the edge of the
    -- interface.
    inset = 0.0
}
