-- Drops extrusions too short to be worth the travel that reaches them.
--
-- A fill pattern clipped against a contour leaves stubs behind: an infill line that
-- survives only a millimetre in a corner, an internal perimeter reduced to a sliver.
-- The stub itself is nothing, but the head still has to travel to it, retract, extrude,
-- retract again and travel away. On a tall part with four such corners that repeats on
-- every layer and adds up to tens of metres of head movement.
--
-- The slicer asks this plugin about every perimeter and infill path before travels and
-- seams are decided, so a rejected path disappears together with the movement that
-- would have reached it.

info = {
    id = "short_extrusion",
    type = "slicing.extrusion_filter",
    title = "Drop short extrusions"
}

-- settings.lua sits next to this file; edit it and re-slice, no restart needed.
local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local min_length = settings.min_length or 2.0
local min_length_by_role = settings.min_length_by_role or {}
local first_filtered_layer = settings.first_filtered_layer or 1

-- Only these roles are ever considered. Everything else is kept, which is what keeps
-- the external perimeter, the top surface, bridges and gap fill out of reach: an
-- allowlist cannot forget a role that a future slicer version introduces.
local filtered_roles = settings.filtered_roles or {
    Perimeter = true,        -- internal perimeters; the external one has its own role
    InternalInfill = true,
    SolidInfill = true,
}

--- Entry point, called once per extrusion path.
-- @param path {role = <string>, length = <mm>, layer_id = <int>, print_z = <mm>,
--              extruder_id = <int>}
-- @return true to print the path, false to drop it
function keep_extrusion(path)
    if not filtered_roles[path.role] then
        return true
    end

    -- The first layers carry the adhesion; never thin them out.
    if path.layer_id < first_filtered_layer then
        return true
    end

    local threshold = min_length_by_role[path.role] or min_length
    return path.length >= threshold
end
