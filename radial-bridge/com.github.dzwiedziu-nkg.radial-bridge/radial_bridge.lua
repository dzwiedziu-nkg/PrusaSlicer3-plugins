-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Lays a bridge out as spokes running from an inner island to the surrounding wall.
--
-- The stock fill patterns run straight lines in one direction. Over an annular gap that
-- makes the lines nearest the inner island long chords spanning the whole opening, while
-- the same area covered by spokes has no unsupported run longer than the width of the
-- gap. On the test model the longest unsupported line drops from 27.7 mm to about 7 mm.
--
-- The plugin only claims a surface it can actually improve: a bridge whose region has a
-- hole in it, with the ray centre inside that hole. Everything else is declined and the
-- slicer fills it as usual.
--
-- Two settings control how much plastic ends up on the bridge. `density` sets how many
-- spokes are laid, and `flow_ratio` how much each of them carries. They are separate on
-- purpose: fewer spokes leaves wider gaps, a thinner spoke stays where it is and only
-- gets smaller, and a strand that curls up wants the second one rather than the first.

info = {
    id = "radial_bridge",
    type = "slicing.fill_planner",
    title = "Radial bridges"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local filtered_roles = settings.filtered_roles or {BridgeInfill = true}
local min_hole_radius = settings.min_hole_radius or 1.0
local max_spokes = settings.max_spokes or 2000
local density = settings.density or 1.0
local flow_ratio = settings.flow_ratio or 1.0
local match_stock_material = settings.match_stock_material == true

--- Area and centroid of a closed contour, by the shoelace formula.
-- @return area (signed), cx, cy
local function centroid(points)
    local n = #points
    local a, cx, cy = 0.0, 0.0, 0.0
    for i = 1, n do
        local p, q = points[i], points[i % n + 1]
        local cross = p.x * q.y - q.x * p.y
        a = a + cross
        cx = cx + (p.x + q.x) * cross
        cy = cy + (p.y + q.y) * cross
    end
    if math.abs(a) < 1e-12 then
        return 0.0, 0.0, 0.0
    end
    return a / 2.0, cx / (3.0 * a), cy / (3.0 * a)
end

--- Total length of a polyline, in mm.
local function polyline_length(path)
    local total = 0.0
    for i = 2, #path do
        local dx, dy = path[i].x - path[i - 1].x, path[i].y - path[i - 1].y
        total = total + math.sqrt(dx * dx + dy * dy)
    end
    return total
end

--- Area of the surface handed to the planner: its contour less its holes, in mm^2.
local function surface_area(surface)
    local area = math.abs((centroid(surface.contour)))
    for _, hole in ipairs(surface.holes) do
        area = area - math.abs((centroid(hole)))
    end
    return area
end

--- Distances from (cx, cy) to every crossing of a ray with a closed contour.
-- The ray leaves (cx, cy) in direction (dx, dy); only forward crossings count.
local function ray_crossings(points, cx, cy, dx, dy, out)
    local n = #points
    for i = 1, n do
        local p, q = points[i], points[i % n + 1]
        local ex, ey = q.x - p.x, q.y - p.y
        local denom = dx * ey - dy * ex
        if math.abs(denom) > 1e-12 then
            local rx, ry = p.x - cx, p.y - cy
            -- t along the ray, u along the edge
            local t = (rx * ey - ry * ex) / denom
            local u = (rx * dy - ry * dx) / denom
            if t > 0.0 and u >= 0.0 and u < 1.0 then
                out[#out + 1] = t
            end
        end
    end
end

--- Entry point, called once per surface about to be filled.
-- @param surface {role, layer_id, print_z, extruder_id, spacing, bridge_angle,
--                 contour = {{x, y}, ...}, holes = {{{x, y}, ...}, ...}}  -- mm
-- @return a list of polylines to extrude, or nil to keep the slicer's own paths
function plan_fill(surface)
    if not filtered_roles[surface.role] then
        return nil
    end
    if #surface.holes == 0 then
        -- Nothing to run the spokes out from.
        return nil
    end

    -- The spokes radiate from the largest hole: that is the island the bridge starts on.
    local best_area, cx, cy = 0.0, nil, nil
    for _, hole in ipairs(surface.holes) do
        local area, hx, hy = centroid(hole)
        area = math.abs(area)
        if area > best_area then
            best_area, cx, cy = area, hx, hy
        end
    end
    if cx == nil then
        return nil
    end

    -- Radius of that hole, and of the surface as a whole, measured from the same centre.
    local r_hole, r_outer = math.huge, 0.0
    for _, hole in ipairs(surface.holes) do
        for _, p in ipairs(hole) do
            local r = math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
            if r < r_hole then r_hole = r end
        end
    end
    for _, p in ipairs(surface.contour) do
        local r = math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
        if r > r_outer then r_outer = r end
    end
    if r_hole < min_hole_radius or r_outer <= r_hole then
        return nil
    end

    -- How many spokes. Their gap widens with the radius, so matching the line spacing
    -- at the inner edge leaves the outer edge sparse and matching it at the outer edge
    -- crowds the inner one. Matching it half way puts the average where it belongs: the
    -- gap runs from spacing*r_in/r_mid to spacing*r_out/r_mid, and the material laid
    -- down comes out close to the pattern it replaces.
    --
    -- `density` scales that count directly, so 1.2 lays a fifth more spokes a fifth
    -- closer together and 0.8 a fifth fewer.
    local spacing = surface.spacing
    if spacing == nil or spacing <= 0.0 then
        return nil
    end
    local r_mid = 0.5 * (r_hole + r_outer)
    local spokes = math.floor(2.0 * math.pi * r_mid * density / spacing + 0.5)
    if spokes < 3 or spokes > max_spokes then
        return nil
    end

    local paths = {}
    -- Chord sag of one angular step, so a connection between two neighbouring spokes
    -- never dips out of the surface and gets clipped away.
    local sag = 1.0 - math.cos(math.pi / spokes)

    --- The stretches of one ray that lie inside the surface, as {t_enter, t_leave} pairs.
    local function spans(dx, dy)
        local crossings = {}
        ray_crossings(surface.contour, cx, cy, dx, dy, crossings)
        for _, hole in ipairs(surface.holes) do
            ray_crossings(hole, cx, cy, dx, dy, crossings)
        end
        table.sort(crossings)

        -- The ray starts inside the hole, so the crossings pair up as enter and leave.
        local out = {}
        for k = 1, #crossings - 1, 2 do
            local t0, t1 = crossings[k], crossings[k + 1]
            -- Pull both ends in by the sag of the connecting chords. The surface already
            -- covers the anchors, so a few microns off the edge still lands on solid.
            t0 = t0 + t0 * sag + 0.01
            t1 = t1 - t1 * sag - 0.01
            if t1 - t0 > 1e-6 then
                out[#out + 1] = {t0, t1}
            end
        end
        return out
    end

    -- Walk the spokes as one continuous path, out along one and back along the next, so
    -- the head never has to travel between them. Where a ray does not cross the surface
    -- exactly once the run is broken and a new one started.
    local run = {}
    local function finish()
        if #run >= 2 then
            paths[#paths + 1] = run
        end
        run = {}
    end

    for i = 0, spokes - 1 do
        local angle = 2.0 * math.pi * i / spokes
        local dx, dy = math.cos(angle), math.sin(angle)
        local found = spans(dx, dy)

        if #found ~= 1 then
            finish()
            -- Still print what is there, just not joined up.
            for _, span in ipairs(found) do
                paths[#paths + 1] = {
                    {x = cx + dx * span[1], y = cy + dy * span[1]},
                    {x = cx + dx * span[2], y = cy + dy * span[2]}
                }
            end
        else
            local t0, t1 = found[1][1], found[1][2]
            if i % 2 == 1 then
                t0, t1 = t1, t0
            end
            run[#run + 1] = {x = cx + dx * t0, y = cy + dy * t0}
            run[#run + 1] = {x = cx + dx * t1, y = cy + dy * t1}
        end
    end
    finish()

    if #paths == 0 then
        return nil
    end

    local ratio = flow_ratio
    if match_stock_material then
        -- The pattern being replaced covers this same region with parallel lines
        -- `spacing` apart, so it lays down area/spacing of line. Scaling the flow by the
        -- ratio of the two lengths puts the same volume of plastic on the surface as the
        -- slicer intended, whatever the fan happens to come out at.
        --
        -- area/spacing is an estimate of that pattern, not a measurement of it: it
        -- ignores the anchors and the ends the filler clips. On the test model it comes
        -- out at 0.9525 where the measured ratio of the two patterns is 0.9416, which
        -- leaves the surface about 1 % over the stock material instead of 6 %.
        local laid = 0.0
        for _, path in ipairs(paths) do
            laid = laid + polyline_length(path)
        end
        local wanted = surface_area(surface) / spacing
        if laid > 1e-9 and wanted > 0.0 then
            ratio = ratio * wanted / laid
        end
    end

    return {paths = paths, flow_ratio = ratio}
end
