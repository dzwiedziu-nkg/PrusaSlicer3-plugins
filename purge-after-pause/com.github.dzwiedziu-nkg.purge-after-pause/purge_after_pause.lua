-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Purges into the layer's own infill after a pause or a colour change.
--
-- While a print is stopped the nozzle is hot and still, and it drips. What comes back is a
-- melt of unknown temperature, unknown pressure and unknown volume, and the slicer's answer
-- to that is the prime in `color_change_gcode`: 0.3 mm of filament, 0.72 mm3, against a melt
-- zone of fifteen to forty.
--
-- Two things follow on the print. The first extrusions come out starved, which shows on a
-- small object because the external perimeter is reached before the flow has settled. And
-- whatever dripped lands on the first thing the nozzle touches - which, since the slicer
-- emits the interruption at the first extrusion point, is a wall.
--
-- This asks the slicer for a purge in the room the layer's own sparse infill leaves, printed
-- before anything else on the layer. The printer then comes back from the pause onto the
-- purge patch rather than onto a perimeter: the drip lands between infill lines where nobody
-- will see it, the purge drives out what was left in the melt, and only then does the real
-- work start.
--
-- What it costs is filament, and not even that in the usual sense: the purge stays inside the
-- object as extra material. It needs no wipe tower, no room on the bed and nothing printed
-- from the first layer up.

info = {
    id = "purge_after_pause",
    type = "slicing.resume_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local volume = settings.volume == nil and 25.0 or settings.volume
local kinds = settings.kinds or {Pause = true, ColorChange = true, ToolChange = true}
local min_spare_volume = settings.min_spare_volume == nil and 5.0 or settings.min_spare_volume

--- Decides what to put through the nozzle before the layer's own work resumes.
-- @param resume table with kind, layer_id, print_z, extruder_id, layer_height,
--               nozzle_diameter, spare_area and spare_volume.
-- @return number of mm3 to purge, or nil to resume the way the slicer would.
function plan_resume(resume)
    if not kinds[resume.kind] then
        -- Not an interruption this plugin cares about.
        return nil
    end

    -- A layer that is solid throughout has nowhere to put a purge, and a layer with barely
    -- any room is not worth the travel to reach it: the drip would land on the way there and
    -- the purge would be too small to replace what is in the melt anyway.
    if resume.spare_volume < min_spare_volume then
        return nil
    end

    -- Asking for more than fits gets what fits, so the cap is only to keep the plugin honest
    -- about what it is asking for.
    return math.min(volume, resume.spare_volume)
end
