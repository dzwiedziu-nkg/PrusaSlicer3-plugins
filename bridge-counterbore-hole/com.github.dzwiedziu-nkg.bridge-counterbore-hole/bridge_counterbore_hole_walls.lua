-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Keeps the wall off the part of a layer that hangs over a hole.
--
-- The other half of this plugin closes the hole for one layer. This half leaves the hole open
-- and stops the wall being drawn round it in mid-air instead: the unsupported ring is cut out
-- of what the perimeter generator is given, together with a band of held-up material beside it,
-- and handed to the fill stage. The ring is bridged, as it always was, and the wall now runs
-- round the outside of the band, on material the layer below holds up.
--
-- Nothing has to be drilled out afterwards, which is the advantage over the sacrificial layer,
-- and the hole's wall is missing on that one layer, which is the cost.
--
-- This is OrcaSlicer's `counterbore_hole_bridging` in `partiallybridge` mode. It is a decision
-- about perimeters rather than about outlines, which is why it is a second plugin in this
-- bundle rather than another remedy on the slice planner - and why `settings.lua` picks one
-- mode for both: they are two answers to the same question and running both would close the
-- hole and then remove a wall that is no longer there.

info = {
    id = "bridge_counterbore_hole_walls",
    type = "slicing.perimeter_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local mode = settings.mode or "sacrificial"
local anchor = settings.anchor or 0.0
local min_unsupported = settings.min_unsupported or 0.0
local min_z = settings.min_z == nil and 0.0 or settings.min_z

--- Decides what happens to the part of this region that hangs over air.
-- @param region table with layer_id, print_z, layer_height, extruder_id, perimeters,
--               perimeter_width, perimeter_spacing and nozzle_diameter.
-- @return a table naming `unsupported`, or nil to wall the region as usual.
function plan_perimeters(region)
    if mode ~= "partial" then
        return nil
    end
    if region.print_z < min_z then
        return nil
    end

    -- "fill_holes" is the counterbore case: only where the unsupported material touches a hole
    -- of this region. "fill_all" would do it to every overhang in the part, which is a much
    -- bigger change of behaviour than this plugin is named after.
    return {
        unsupported = "fill_holes",
        unsupported_anchor = anchor,
        min_unsupported = min_unsupported
    }
end
