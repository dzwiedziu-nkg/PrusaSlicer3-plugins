-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Spaces bridge lines by the bead the nozzle actually lays.
--
-- A bridge line extruded into mid-air is a cylinder of roughly the nozzle diameter. It is not
-- the flattened discorectangle a line printed onto solid plastic becomes, because there is
-- nothing under it to flatten against. The slicer knows this - `Flow::mm3_per_mm()` uses the
-- area of a circle for a bridge - but it then spaces the lines by
--
--     Flow::bridge_extrusion_spacing(d) = d + BRIDGE_EXTRA_SPACING      -- 0.05 mm
--
-- so consecutive strands are laid an eighth of a bead apart at a 0.4 nozzle and never touch.
-- Measured on a stock slice: bead 0.402 mm, line spacing 0.453 mm, gap 0.051 mm. Each strand
-- spans the gap alone, and a strand alone sags.
--
-- This lays them at the bead diameter instead, or closer, so they touch along their length and
-- hold each other up. Two knobs, the same two OrcaSlicer has: `density` sets how far apart the
-- strands go as a fraction of their own width, and `flow_ratio` sets how fat they are. Measured
-- on OrcaSlicer's own output, its `bridge_density` changes only the spacing and its
-- `bridge_flow` only the strand, exactly as these two do.
--
-- The direction is the slicer's own `bridge_angle`. That choice is made from the shape of the
-- opening and the anchors available, and it is not this plugin's business to second-guess it.
--
-- It can also give them their own speed. PrusaSlicer has one `bridge_speed` for both kinds of
-- bridge because both are the same extrusion role to it, so raising it for the internal ones
-- speeds up the external ones too. Setting `speed` here separates them.
--
-- Only the **external** bridges - the ones cast over open air. PrusaSlicer gives a bridge over
-- sparse infill the same extrusion role and the same `bridge_speed`, so the two cannot be told
-- apart from the role; `external` on the surface is what separates them. OrcaSlicer keeps them
-- apart as `bridge_density` and `internal_bridge_density` and defaults the internal one to
-- 100 %, which is the same judgement.

info = {
    id = "bridge_density",
    type = "slicing.fill_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local density = settings.density == nil and 1.0 or settings.density
local flow_ratio = settings.flow_ratio == nil and 1.0 or settings.flow_ratio
local extra_spacing = settings.extra_spacing == nil and 0.05 or settings.extra_spacing
local match_stock_material = settings.match_stock_material == true
local roles = settings.roles == nil and {BridgeInfill = true} or settings.roles
local speed = settings.speed == nil and 0 or settings.speed
local external_only = settings.external_only ~= false
local max_lines = settings.max_lines == nil and 4000 or settings.max_lines

-- How far inside the boundary a line stops, so the turn onto the next one survives the clip the
-- slicer runs afterwards. A chord starting exactly on the boundary lands outside as often as in.
local EDGE_INSET = 0.05

--- Signed area of a closed contour, in mm2.
local function contour_area(points)
    local n = #points
    if n < 3 then
        return 0.0
    end
    local a = 0.0
    local j = n
    for i = 1, n do
        a = a + (points[j].x + points[i].x) * (points[j].y - points[i].y)
        j = i
    end
    return math.abs(a) * 0.5
end

--- Area the fill has to cover: the contour less its holes.
local function surface_area(surface)
    local a = contour_area(surface.contour)
    if surface.holes ~= nil then
        for _, hole in ipairs(surface.holes) do
            a = a - contour_area(hole)
        end
    end
    return a
end

local function polyline_length(path)
    local total = 0.0
    for i = 2, #path do
        local dx = path[i].x - path[i - 1].x
        local dy = path[i].y - path[i - 1].y
        total = total + math.sqrt(dx * dx + dy * dy)
    end
    return total
end

--- Where a line crosses the boundary, as distances along the line direction.
-- The line runs through the origin along (dx, dy); a point is on it when its component along
-- the normal equals `d`. Every edge that straddles that value contributes one crossing.
local function crossings(points, d, dx, dy, nx, ny, out)
    local n = #points
    if n < 3 then
        return
    end
    local prev = points[n]
    local pn = prev.x * nx + prev.y * ny - d
    for i = 1, n do
        local cur = points[i]
        local cn = cur.x * nx + cur.y * ny - d
        if (pn > 0) ~= (cn > 0) then
            local u = pn / (pn - cn)
            local px = prev.x + u * (cur.x - prev.x)
            local py = prev.y + u * (cur.y - prev.y)
            out[#out + 1] = px * dx + py * dy
        end
        prev, pn = cur, cn
    end
end

--- The spans of one line that lie inside the surface, as {from, to} pairs along the direction.
local function spans_of(surface, d, dx, dy, nx, ny)
    local ts = {}
    crossings(surface.contour, d, dx, dy, nx, ny, ts)
    if surface.holes ~= nil then
        for _, hole in ipairs(surface.holes) do
            crossings(hole, d, dx, dy, nx, ny, ts)
        end
    end
    table.sort(ts)
    local spans = {}
    for i = 1, #ts - 1, 2 do
        -- Pull the ends in a hair. The turn at the end of a line is a chord between two points
        -- on the boundary, and a chord that starts exactly on the boundary is a coin toss for
        -- the clipper the slicer runs afterwards - it lands outside as often as in, and the
        -- turn is dropped. Inside by a twentieth of a millimetre it survives, and the length
        -- lost is anchor that reaches past the opening anyway.
        local a, b = ts[i] + EDGE_INSET, ts[i + 1] - EDGE_INSET
        if b - a > 1e-6 then
            spans[#spans + 1] = {a, b}
        end
    end
    return spans
end

--- Parallel lines at `step` across the surface, walked as continuous paths.
--
-- Laid out from the plate origin so neighbouring surfaces of a layer share the same lines. Each
-- line is cut to the spans that lie inside the surface here rather than left to the slicer,
-- because knowing where a line ends is what makes it possible to turn round at that end and
-- come back along the next one. Separate lines mean a travel and a retraction between every
-- pair, and on a bridge they also mean every strand starts from a standstill.
local function lines_at(surface, theta, step)
    local dx, dy = math.cos(theta), math.sin(theta)
    local nx, ny = -dy, dx
    local plo, phi = math.huge, -math.huge
    for _, p in ipairs(surface.contour) do
        local q = p.x * nx + p.y * ny
        if q < plo then plo = q end
        if q > phi then phi = q end
    end
    if plo > phi then
        return nil
    end

    local first = math.ceil(plo / step)
    local last = math.floor(phi / step)
    if last - first + 1 > max_lines then
        return nil
    end

    local paths = {}
    local open = {}                  -- spans of the previous line, with the path each belongs to
    local flip = false
    for k = first, last do
        local d = k * step
        local spans = spans_of(surface, d, dx, dy, nx, ny)
        local next_open = {}
        for _, sp in ipairs(spans) do
            local a, b = sp[1], sp[2]
            -- Continue whichever path ended on a span this one overlaps, so the head turns
            -- round at the edge instead of flying back across the opening.
            local path = nil
            for i, prev in ipairs(open) do
                if prev.a < b and a < prev.b then
                    path = prev.path
                    table.remove(open, i)
                    break
                end
            end
            if path == nil then
                path = {}
                paths[#paths + 1] = path
            end
            if flip then
                path[#path + 1] = {x = b * dx + d * nx, y = b * dy + d * ny}
                path[#path + 1] = {x = a * dx + d * nx, y = a * dy + d * ny}
            else
                path[#path + 1] = {x = a * dx + d * nx, y = a * dy + d * ny}
                path[#path + 1] = {x = b * dx + d * nx, y = b * dy + d * ny}
            end
            next_open[#next_open + 1] = {a = a, b = b, path = path}
        end
        open = next_open
        flip = not flip
    end

    local kept = {}
    for _, path in ipairs(paths) do
        if #path >= 2 then
            kept[#kept + 1] = path
        end
    end
    if #kept == 0 then
        return nil
    end
    return kept
end

--- Lays out one surface.
-- @param surface table with role, layer_id, print_z, extruder_id, spacing, density,
--                bridge_angle, contour and holes.
-- @return a table of paths, or nil to keep the slicer's own pattern.
function plan_fill(surface)
    if not roles[surface.role] then
        return nil
    end
    -- Negative means the slicer did not treat this as a bridge, so there is no direction to
    -- follow and no cylinder to space by.
    if surface.bridge_angle == nil or surface.bridge_angle < 0.0 then
        return nil
    end
    -- PrusaSlicer gives both kinds of bridge the same extrusion role, so the role alone does
    -- not say whether this one is cast in mid-air or laid over sparse infill. `external` does.
    -- A bridge over infill rests on a lattice every few millimetres; it is not sagging for want
    -- of lateral contact, and packing its lines together only adds plastic inside the part.
    if external_only and surface.external ~= true then
        return nil
    end
    if surface.spacing <= 0.0 then
        return nil
    end

    -- The bead is worked out from the flow, not from the spacing. For a bridge the slicer
    -- extrudes the area of a circle, so the strand is sqrt(4*V/pi) across. Deriving it from
    -- `spacing` instead is wrong on any region the slicer had to adjust the spacing for: it
    -- fits a whole number of lines across, so a narrow opening comes back with the lines
    -- already closer than nominal, and subtracting the gap again lands short.
    local bead
    if surface.mm3_per_mm ~= nil and surface.mm3_per_mm > 0.0 then
        bead = math.sqrt(4.0 * surface.mm3_per_mm / math.pi)
    else
        bead = surface.spacing - extra_spacing
    end
    if bead <= 0.0 then
        return nil
    end
    -- More flow makes a fatter strand, and the strand is what the spacing is measured against.
    bead = bead * math.sqrt(flow_ratio)
    -- `density` is the ratio of strand to spacing: 1.0 puts them edge to edge, 1.14 gives them
    -- 14 % of overlap, 0.4 leaves a gap of one and a half strands. Deliberately not measured
    -- against the slicer's own spacing, which differs between slicers and between regions of
    -- one layer; the strand either touches its neighbour or it does not, and that is absolute.
    if density <= 0.0 then
        return nil
    end
    local step = bead / density
    if step <= 0.0 then
        return nil
    end

    local paths = lines_at(surface, surface.bridge_angle, step)
    if paths == nil then
        return nil
    end

    if not match_stock_material then
        if speed > 0 or flow_ratio ~= 1.0 then
            return {paths = paths, flow_ratio = flow_ratio,
                    speed = speed > 0 and speed or nil}
        end
        return paths
    end

    -- The stock pattern would have covered this area with lines `spacing` apart, so it lays
    -- area/spacing of line. Scaling by the ratio of the two lengths puts the same volume of
    -- plastic on the surface, spread over more strands.
    local laid = 0.0
    for _, path in ipairs(paths) do
        laid = laid + polyline_length(path)
    end
    local wanted = surface_area(surface) / surface.spacing
    if laid <= 1e-9 or wanted <= 0.0 then
        return paths
    end
    return {paths = paths, flow_ratio = flow_ratio * wanted / laid,
            speed = speed > 0 and speed or nil}
end
