-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Print order of the disjoint islands of a layer.
--
-- The problem this solves is not "too much travel" but "one travel long enough to
-- ooze". The stock order is chained once at slicing time and reused for every layer,
-- so the head walks the whole row and then jumps all the way back to the start -- a
-- single travel across the entire print, far beyond what a normal retraction covers.
--
-- The obvious fix, reversing the order every layer, kills that jump but also destroys
-- the cooling time: the island at the turning point is the last one printed on a layer
-- and the first one on the next, so it gets no time to solidify at all.
--
-- So the default here keeps the order *stable* across layers -- which is what gives
-- every island a full layer time to cool -- and walks the tour in steps of two, out
-- and back, so no single travel spans more than two island gaps.
--
-- Coordinates arrive in millimetres in the G-code (bed) frame.

info = {
    id = "island_order",
    type = "slicing.island_order",
    title = "Island print order"
}

-- settings.lua sits next to this file; edit it and re-slice, no restart needed.
local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}
local mode = settings.mode or "cooling"

-- 2-opt is O(n^2) per pass and runs once per layer, so give it a ceiling. Above it
-- the greedy chain alone still avoids the long jump.
local MAX_TWO_OPT_ISLANDS = settings.max_two_opt_islands or 100
local MAX_PASSES = 20
local EPSILON = 1e-9

local function distance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function reverse_segment(order, from, to)
    while from < to do
        order[from], order[to] = order[to], order[from]
        from = from + 1
        to = to - 1
    end
end

--------------------------------------------------------------------------------
-- Layer stable ordering: the "cooling" mode.
--------------------------------------------------------------------------------

--- Orders the islands by geometry alone, so that the same set of islands always
--- yields the same sequence no matter what order the slicer hands them in.
-- Without this the tour below could come out differently on two layers that have
-- the same islands, and the cooling guarantee would be lost.
local function canonical_positions(islands)
    local positions = {}
    for i = 1, #islands do
        positions[i] = i
    end
    table.sort(positions, function(a, b)
        local ca, cb = islands[a].centroid, islands[b].centroid
        if ca.x ~= cb.x then return ca.x < cb.x end
        if ca.y ~= cb.y then return ca.y < cb.y end
        return a < b
    end)
    return positions
end

--- Greedy nearest neighbour over the canonical order, from a fixed starting island.
-- Deliberately ignores the head position: the sequence has to be identical on every
-- layer, and seeding it from the head is exactly what makes it drift.
local function nearest_neighbour_tour(centroids)
    local count = #centroids
    local visited = {}
    local tour = {1}
    visited[1] = true
    local current = centroids[1]

    for _ = 2, count do
        local best = nil
        local best_distance = math.huge
        for i = 1, count do
            if not visited[i] then
                local candidate = distance(current, centroids[i])
                if candidate < best_distance then
                    best_distance = candidate
                    best = i
                end
            end
        end
        visited[best] = true
        tour[#tour + 1] = best
        current = centroids[best]
    end

    return tour
end

--- 2-opt over a closed tour.
-- Reversing tour[i..j] replaces the edge entering the segment and the edge leaving
-- it, both taken with wrap-around, so a candidate costs four distance evaluations.
local function two_opt_tour(centroids, tour)
    local count = #tour
    if count < 5 or count > MAX_TWO_OPT_ISLANDS then
        return tour
    end

    for _ = 1, MAX_PASSES do
        local improved = false

        for i = 1, count - 1 do
            for j = i + 1, count do
                -- i == 1 and j == count reverses the whole tour and changes nothing.
                if not (i == 1 and j == count) then
                    local before = centroids[tour[(i - 2) % count + 1]]
                    local segment_first = centroids[tour[i]]
                    local segment_last = centroids[tour[j]]
                    local after = centroids[tour[j % count + 1]]

                    local removed = distance(before, segment_first) + distance(segment_last, after)
                    local added = distance(before, segment_last) + distance(segment_first, after)

                    if added + EPSILON < removed then
                        reverse_segment(tour, i, j)
                        improved = true
                    end
                end
            end
        end

        if not improved then
            break
        end
    end

    return tour
end

--- Walks a closed tour in steps of two: out along one parity, back along the other.
--
-- On a row of islands 1..n this prints 1,3,5,...,n then n-1,...,4,2. Three things
-- follow, and they are the whole point of this mode:
--   * the tour's longest edge, the one that closes the loop, is never travelled;
--   * every travel spans at most two tour edges instead of the whole print;
--   * the sequence ends next to where the next layer starts, so the layer change
--     costs one short hop -- and because the sequence is the same on every layer,
--     each island is revisited exactly one layer time after it was left.
local function walk_alternating(tour)
    local count = #tour
    local order = {}

    for i = 1, count, 2 do
        order[#order + 1] = tour[i]
    end

    local last_even = count - (count % 2)
    for i = last_even, 2, -2 do
        order[#order + 1] = tour[i]
    end

    return order
end

--------------------------------------------------------------------------------
-- Shortest travel ordering: the "travel" mode.
--------------------------------------------------------------------------------

--- Greedy nearest neighbour seeded from where the head actually is.
local function nearest_neighbour_path(islands, head)
    local count = #islands
    local visited = {}
    local order = {}
    local current = head

    for _ = 1, count do
        local best = nil
        local best_distance = math.huge

        for i = 1, count do
            if not visited[i] then
                local candidate
                if current then
                    candidate = distance(current, islands[i].centroid)
                else
                    -- Without a head position, keep the stock order for the first pick.
                    candidate = i
                end
                if candidate < best_distance then
                    best_distance = candidate
                    best = i
                end
            end
        end

        visited[best] = true
        order[#order + 1] = best
        current = islands[best].centroid
    end

    return order
end

--- 2-opt refinement of an open path anchored at the head position.
local function two_opt_path(islands, order, head)
    local count = #order
    if count < 4 or count > MAX_TWO_OPT_ISLANDS then
        return order
    end

    for _ = 1, MAX_PASSES do
        local improved = false

        for i = 1, count - 1 do
            for j = i + 1, count do
                local before
                if i == 1 then
                    before = head
                else
                    before = islands[order[i - 1]].centroid
                end

                local after
                if j < count then
                    after = islands[order[j + 1]].centroid
                end

                local segment_first = islands[order[i]].centroid
                local segment_last = islands[order[j]].centroid

                local removed = 0.0
                local added = 0.0
                if before then
                    removed = removed + distance(before, segment_first)
                    added = added + distance(before, segment_last)
                end
                if after then
                    removed = removed + distance(segment_last, after)
                    added = added + distance(segment_first, after)
                end

                if added + EPSILON < removed then
                    reverse_segment(order, i, j)
                    improved = true
                end
            end
        end

        if not improved then
            break
        end
    end

    return order
end

--------------------------------------------------------------------------------

local function stock_order(islands)
    local order = {}
    for i = 1, #islands do
        order[i] = i
    end
    return order
end

local function cooling_order(islands)
    local positions = canonical_positions(islands)

    local centroids = {}
    for i = 1, #positions do
        centroids[i] = islands[positions[i]].centroid
    end

    local tour = two_opt_tour(centroids, nearest_neighbour_tour(centroids))
    local walked = walk_alternating(tour)

    -- Back from canonical positions to the positions the slicer handed in.
    local order = {}
    for i = 1, #walked do
        order[i] = positions[walked[i]]
    end
    return order
end

--- Entry point, called once per layer and per object instance.
-- @param islands array of {centroid = {x, y}, bbox = {min_x, min_y, max_x, max_y}}
-- @param ctx     {layer_id, print_z, extruder_id, head = {x, y} or nil}
-- @return array of 1-based positions into `islands`, each exactly once
function order_islands(islands, ctx)
    if mode == "stock" then
        return stock_order(islands)
    elseif mode == "travel" then
        return two_opt_path(islands, nearest_neighbour_path(islands, ctx.head), ctx.head)
    end
    return cooling_order(islands)
end
