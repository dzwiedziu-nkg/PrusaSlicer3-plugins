-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Gradient sparse infill.
--
-- `fill_density` is one number for the whole object, so the slicer spreads the same lattice
-- through the middle of a part as it does just behind the wall. That is not where the material
-- earns its keep: a part in bending carries the load in the material furthest from its neutral
-- axis, and in a printed part that is the infill right behind the wall. The middle is mostly
-- holding the two halves apart.
--
-- This packs the lines closer inside a band along the wall and lets them open out towards the
-- middle. Set `edge` and `core` so they roughly cancel and the part costs about what it did,
-- with the material somewhere more useful; set only `edge` and it costs more and is stiffer.
--
-- What it measures is the distance to the edge **along the line normal** - how far this line is
-- from the first and last line of the layer - not the true distance to the wall, which would
-- mean a distance transform of the contour on every surface. Since the pattern turns 90 degrees
-- each layer, one layer packs against one pair of edges and the next against the other, so a
-- part gets a dense skirt all the way round over any two layers. On a long thin region that is
-- exactly right; on a circular one it is an approximation, and a fair one.

info = {
    id = "gradient_infill",
    type = "slicing.fill_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local band = settings.band == nil and 4.0 or settings.band
local edge = settings.edge == nil and 2.0 or settings.edge
local core = settings.core == nil and 0.5 or settings.core
local taper = settings.taper == nil and 4.0 or settings.taper
local angle = settings.angle == nil and 45 or settings.angle
local angle_step = settings.angle_step == nil and 90 or settings.angle_step
local roles = settings.roles == nil and {InternalInfill = true} or settings.roles
local skip_first_layers = settings.skip_first_layers == nil and 0 or settings.skip_first_layers

-- Never pack tighter than this many beads apart, whatever the settings say: lines closer than
-- about one bead are not infill any more, they are solid, and the flow was not computed for it.
local MIN_BEADS = 1.0

--- How many times the nominal density this line gets, from its distance to the edge.
local function factor_at(dist)
    if dist <= band then
        return edge
    end
    if taper <= 0.0 or dist >= band + taper then
        return core
    end
    local t = (dist - band) / taper
    return edge + (core - edge) * t
end

--- Where the lines go: from one edge of the region to the other, each step as wide as the
-- local density asks for. Walking it rather than solving it is what lets the step vary.
local function positions(lo, hi, nominal, bead)
    local out = {}
    local d = lo
    local guard = 0
    while d <= hi and guard < 100000 do
        out[#out + 1] = d
        local f = factor_at(math.min(d - lo, hi - d))
        local step = nominal / math.max(f, 1e-6)
        if step < bead * MIN_BEADS then
            step = bead * MIN_BEADS
        end
        d = d + step
        guard = guard + 1
    end
    return out
end

local function plan_lines(points, theta, nominal, bead)
    local dx, dy = math.cos(theta), math.sin(theta)
    local nx, ny = -dy, dx
    local lo, hi = math.huge, -math.huge
    local alo, ahi = math.huge, -math.huge
    for _, p in ipairs(points) do
        local d = p.x * nx + p.y * ny
        if d < lo then lo = d end
        if d > hi then hi = d end
        local a = p.x * dx + p.y * dy
        if a < alo then alo = a end
        if a > ahi then ahi = a end
    end
    if lo > hi then
        return nil
    end
    -- Half a step in from each edge, so the first and last line sit inside the region the way
    -- the stock pattern's do rather than on its boundary.
    local first = lo + nominal / (2.0 * math.max(edge, 1e-6))
    local paths = {}
    local ds = positions(first, hi, nominal, bead)
    for i, d in ipairs(ds) do
        local px, py = d * nx, d * ny
        local a, b = alo - nominal, ahi + nominal
        if i % 2 == 0 then a, b = b, a end
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
-- @param surface table with role, layer_id, print_z, extruder_id, spacing, density,
--                bridge_angle, contour and holes.
-- @return a table of paths, or nil to keep the slicer's own pattern.
function plan_fill(surface)
    if band <= 0.0 then
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

    -- `spacing` is the width of the bead, not the gap between the pattern's lines; the gap is
    -- that divided by the density, and on sparse infill the two are far apart.
    local density = surface.density
    if density == nil or density <= 0.0 or density > 1.0 then
        density = 1.0
    end
    local nominal = surface.spacing / density

    local theta = math.rad(angle + angle_step * surface.layer_id)
    return plan_lines(surface.contour, theta, nominal, surface.spacing)
end
