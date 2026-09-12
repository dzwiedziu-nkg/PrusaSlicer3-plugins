-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Cross Hatch sparse infill.
--
-- `grid` lays both families of lines on every layer, so the infill welds itself into two
-- continuous walls running the whole height of the part - stiff, and a plane for it to come
-- apart along. `rectilinear` lays one family and turns it 90 degrees every layer, so there is
-- no wall at all, but consecutive layers cross at right angles and touch each other at points
-- rather than along lines.
--
-- Cross Hatch is the middle: one family of lines that holds its direction for a few
-- millimetres - long enough for the layers to fuse into something stiff - and then turns 90
-- degrees over a few more, so the wall never runs the height of the part.
--
-- The algorithm is OrcaSlicer's, not ours; this is a reimplementation of their Cross Hatch
-- pattern for PrusaSlicer, which has no equivalent. The numbers in settings.lua were measured
-- off their own output rather than guessed.
--
-- Use it with `fill_pattern = rectilinear` or `line`. Those lay one family of lines per layer,
-- which is what this pattern does, so the density you asked for is the density you get. Under
-- `grid` the slicer's spacing is worked out for two families crossing on every layer, and one
-- family at that spacing comes out at half the density.

info = {
    id = "cross_hatch",
    type = "slicing.fill_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local angle = settings.angle == nil and 45 or settings.angle
local half_period = settings.half_period == nil and 2.7 or settings.half_period
local transition = settings.transition == nil and 0.4444 or settings.transition
local z_offset = settings.z_offset == nil and 4.6 or settings.z_offset
local roles = settings.roles == nil and {InternalInfill = true} or settings.roles
local skip_first_layers = settings.skip_first_layers == nil and 0 or settings.skip_first_layers

--- Direction of the lines at this height, in radians.
-- Within each half period the lines hold their direction for the first part and turn a
-- quarter turn over the rest, so the next half period starts where this one left off.
local function direction_at(z)
    local cycles = (z + z_offset) / half_period
    local whole = math.floor(cycles)
    local t = cycles - whole
    local turned
    if transition <= 0.0 then
        turned = 0.0
    elseif t <= 1.0 - transition then
        turned = 0.0
    else
        turned = (t - (1.0 - transition)) / transition
    end
    return math.rad(angle) + (whole + turned) * math.pi / 2.0
end

--- Bounding box of a contour, as minx, miny, maxx, maxy.
local function bounds(points)
    local minx, miny = math.huge, math.huge
    local maxx, maxy = -math.huge, -math.huge
    for _, p in ipairs(points) do
        if p.x < minx then minx = p.x end
        if p.x > maxx then maxx = p.x end
        if p.y < miny then miny = p.y end
        if p.y > maxy then maxy = p.y end
    end
    return minx, miny, maxx, maxy
end

--- Lays parallel lines across the whole bounding box; the slicer clips them to the surface.
-- The line positions are measured from the plate origin rather than from this surface, so two
-- regions of the same layer - and the same region on the next layer, while the direction
-- holds - land on the same lines instead of each starting its own grid.
local function hatch(points, theta, spacing)
    local minx, miny, maxx, maxy = bounds(points)
    if minx > maxx then
        return nil
    end
    local dx, dy = math.cos(theta), math.sin(theta)
    local nx, ny = -dy, dx                       -- across the lines
    -- How far along the normal the corners of the box reach, and how far along the direction,
    -- so the lines are drawn long enough to cross it whatever the angle.
    local lo, hi = math.huge, -math.huge
    local along = 0.0
    for _, c in ipairs({{minx, miny}, {maxx, miny}, {maxx, maxy}, {minx, maxy}}) do
        local d = c[1] * nx + c[2] * ny
        if d < lo then lo = d end
        if d > hi then hi = d end
        along = math.max(along, math.abs(c[1] * dx + c[2] * dy))
    end
    local cx, cy = (minx + maxx) / 2.0, (miny + maxy) / 2.0
    local mid = cx * dx + cy * dy
    local reach = along + math.abs(mid) + spacing

    local paths = {}
    local first = math.ceil(lo / spacing)
    local last = math.floor(hi / spacing)
    for k = first, last do
        local d = k * spacing
        -- A point on this line, and the line itself drawn well past the box in both
        -- directions. Alternating the ends keeps the head from flying back every line.
        local px, py = d * nx, d * ny
        local a, b = mid - reach, mid + reach
        if k % 2 ~= 0 then a, b = b, a end
        paths[#paths + 1] = {
            {x = px + a * dx, y = py + a * dy},
            {x = px + b * dx, y = py + b * dy}
        }
    end
    if #paths == 0 then
        return nil
    end
    return paths
end

--- Lays out one surface.
-- @param surface table with role, layer_id, print_z, extruder_id, spacing, bridge_angle,
--                contour and holes.
-- @return a table of paths, or nil to keep the slicer's own pattern.
function plan_fill(surface)
    if half_period <= 0.0 then
        return nil
    end
    if not roles[surface.role] then
        return nil
    end
    if surface.layer_id < skip_first_layers then
        return nil
    end
    if surface.spacing <= 0.0 then
        return nil
    end

    -- `spacing` is the width of the bead, not the gap between the pattern's lines. On sparse
    -- infill the gap is that divided by the density - at 15 % it is nearly seven times wider,
    -- and laying lines a bead apart would fill the part solid.
    local density = surface.density
    if density == nil or density <= 0.0 or density > 1.0 then
        density = 1.0
    end

    return hatch(surface.contour, direction_at(surface.print_z), surface.spacing / density)
end
