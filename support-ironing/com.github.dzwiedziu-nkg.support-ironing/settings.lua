-- Settings for the support interface ironing plugin.
--
-- Edit and slice again; there is no restart and no Plugins -> Rescan. This file is loaded
-- inside a pcall, so a syntax error in it is reported NOWHERE: the file is ignored and the
-- defaults below apply. That is the first thing to suspect when a setting does nothing.

return {
    -- Distance between two ironing lines, in mm. The same quantity as the profile's
    -- `ironing_spacing`, whose default is 0.1, and the plugin does not read that setting -
    -- the hook hands over a surface, not the print profile.
    --
    -- Closer lines melt the ridges down more evenly and cost proportionally more time.
    spacing = 0.1,

    -- Fraction of a full layer of material the pass lays down, 0.0 to 1.0.
    --
    -- The same quantity as the profile's `ironing_flowrate`, whose default is 15 %. It is
    -- not zero because a nozzle dragging over a surface with no pressure behind it picks
    -- material up rather than leaving it; it is not large because everything the pass puts
    -- down is on top of a layer that is already the right height.
    flow_ratio = 0.15,

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
