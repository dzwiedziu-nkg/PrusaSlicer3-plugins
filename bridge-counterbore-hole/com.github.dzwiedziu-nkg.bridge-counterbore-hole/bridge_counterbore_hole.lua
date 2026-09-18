-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Closes a hole for the one layer where the opening under it narrows.
--
-- This is the `sacrificial` half of the bundle and it is off unless `settings.lua` selects it;
-- the default is `partial`, in the other file, which needs nothing drilled out afterwards.
--
-- A counterbore is a wide recess for a screw head with a narrower hole running on through it.
-- Printed with the recess at the bottom, the layer where the opening narrows is a ring of
-- material over open air - and the slicer draws the narrow hole's own wall in mid-air with it,
-- two loops of it, going round nothing. PrusaSlicer bridges the ring and prints those loops
-- anyway; there is no setting for it, because there is no decision: it is what the surface
-- classifier does.
--
-- This closes the hole on that one layer instead. The whole opening is then bridged in one
-- span, nothing is suspended in it, and the layer above keeps its hole because the layer under
-- it is now solid. **The disc has to be drilled or pushed out afterwards.** That is the trade
-- and it is why this plugin is nobody's default.
--
-- The idea is OrcaSlicer's: it is their `counterbore_hole_bridging` in `sacrificiallayer`
-- mode. Their other mode, `partiallybridge`, is not reproduced - see the README for what it
-- does differently and why this hook cannot reach it.
--
-- Install this **instead of** overhang-chamfer, make-overhang-printable and overhang-by-size,
-- not alongside them: the slicer loads one plugin of each type.

info = {
    id = "bridge_counterbore_hole",
    type = "slicing.slice_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local enabled = settings.enabled ~= false
local mode = settings.mode or "partial"
local max_hole = settings.max_hole == nil and 10.0 or settings.max_hole
local angle = settings.angle == nil and 35 or settings.angle
local min_z = settings.min_z == nil and 0.0 or settings.min_z

-- tan(90 degrees) is not representable, and at 90 the answer is exactly zero anyway.
local reach_per_mm = nil
if angle > 0 and angle < 90 then
    reach_per_mm = 1.0 / math.tan(math.rad(angle))
elseif angle >= 90 then
    reach_per_mm = 0.0
end

--- Asks for every layer's unsupported holes to be closed.
--
-- The slicer does the finding: it is the one that knows which holes have a rim hanging over
-- air, and a plugin handed nothing but scalars could not work it out. What the plugin decides
-- is how far a rim has to hang before it counts, and how big an opening may be closed.
--
-- @param layer table with layer_id, print_z, slice_z, layer_height, object_height, area
--              and islands.
-- @return a table naming max_overhang, max_overhang_width and the remedy, or nil.
function plan_slice(layer)
    if not enabled or mode ~= "sacrificial" or reach_per_mm == nil then
        return nil
    end
    if layer.print_z < min_z then
        return nil
    end

    return {
        max_overhang = layer.layer_height * reach_per_mm,
        max_overhang_width = max_hole,
        remedy = "cap"
    }
end
