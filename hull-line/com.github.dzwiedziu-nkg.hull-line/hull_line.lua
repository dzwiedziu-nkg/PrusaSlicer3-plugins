-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Takes the edge off the layer where a part turns from sparse infill into solid.
--
-- The Benchy hull line is a ridge round the hull at the height where the deck starts. Prusa
-- traced it to the transition itself: a run of layers carrying a 15 % lattice is followed by
-- layers that are nearly solid, the material and the time per layer jump, and the wall running
-- through that height cools differently above and below it. Measured on their own test block,
-- the filament per layer goes 5.53, 5.82, **9.41**, 6.83 mm - up 70 % in one layer - while the
-- wall stays at 106.7 mm throughout.
--
-- Of the four things Prusa tried by hand in the G-code, this is the one a fill planner can do:
-- **lower the flow of the solid infill, except on the top surface**. They were careful to say
-- they were not sure it was what helped, and this plugin is careful to say so too. The other
-- three - a modifier mesh splitting the deck from the hull, printing the deck before the rest
-- of the layer, and two layers of wall in a row - are changes to the model or to the order
-- extrusions are printed in, and neither is reachable from this extension point.
--
-- What it does not do is find the transition. A fill planner is asked about every surface of
-- every layer at once, from the slicer's parallel infill stage, so it cannot compare a layer
-- with the one below and cannot know that this is the layer where the deck starts. What it can
-- see is the surface in front of it, so the rule here is about the surface: solid infill, not a
-- top surface, and big enough to be a deck rather than a patch over a hole.

info = {
    id = "hull_line",
    type = "slicing.fill_planner",
    title = "Hull line"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local flow_ratio = settings.flow_ratio == nil and 0.95 or settings.flow_ratio
local speed = settings.speed == nil and 0 or settings.speed
local min_area = settings.min_area == nil and 15.0 or settings.min_area
local roles = settings.roles or {SolidInfill = true}
local skip_first_layers = settings.skip_first_layers == nil and 0 or settings.skip_first_layers

--- Area of a closed contour, by the shoelace formula.
local function contour_area(points)
    local n = #points
    local a = 0.0
    for i = 1, n do
        local p, q = points[i], points[i % n + 1]
        a = a + (p.x * q.y - q.x * p.y)
    end
    return math.abs(a) / 2.0
end

--- Area of the surface handed to the planner: its contour less its holes, in mm^2.
local function surface_area(surface)
    local area = contour_area(surface.contour)
    for _, hole in ipairs(surface.holes) do
        area = area - contour_area(hole)
    end
    return area
end

--- Decides how the solid infill of one surface is printed.
-- @param surface table with role, layer_id, print_z, extruder_id, spacing, density,
--                mm3_per_mm, external, bridge_angle, contour and holes.
-- @return a table naming flow_ratio and speed, or nil to leave the surface alone.
function plan_fill(surface)
    if not roles[surface.role] then
        return nil
    end
    if surface.layer_id < skip_first_layers then
        return nil
    end
    -- A small patch of solid - the shell over a hole, the floor of a recess - is not a deck,
    -- and thinning it buys nothing while costing a seam somebody can see.
    if surface_area(surface) < min_area then
        return nil
    end
    if flow_ratio == 1.0 and speed == 0 then
        return nil
    end

    -- No paths: the slicer keeps the lines it was going to lay and only prints them
    -- differently. Laying our own would cost the links between them, which is a sixth of the
    -- material in travel, for nothing.
    return {flow_ratio = flow_ratio, speed = speed}
end
