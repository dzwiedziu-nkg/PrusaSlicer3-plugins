-- Shortest travel ordering of the disjoint islands of a layer.
--
-- The stock order is chained once at slicing time, before anything is known about
-- where the head will be when the layer starts. This plugin is asked during G-code
-- export instead, so it can seed the chain from the real head position: greedy
-- nearest neighbour, then 2-opt on the open path anchored at that position.
--
-- Coordinates arrive in millimetres in the G-code (bed) frame.

info = {
    id = "island_order",
    type = "slicing.island_order",
    title = "Shortest travel island order"
}

-- 2-opt is O(n^2) per pass and this runs once per layer, so give it a ceiling.
-- Above it the greedy chain alone still shortens the travel.
local MAX_TWO_OPT_ISLANDS = 100
local MAX_PASSES = 20
local EPSILON = 1e-9

local function distance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

--- Greedy nearest neighbour, seeded from where the head actually is.
-- @param islands array of islands as handed in by the slicer
-- @param head    head position, or nil before anything has been extruded
-- @return array of 1-based positions into `islands`
local function nearest_neighbour(islands, head)
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

local function reverse_segment(order, from, to)
    while from < to do
        order[from], order[to] = order[to], order[from]
        from = from + 1
        to = to - 1
    end
end

--- 2-opt refinement of an open path anchored at the head position.
-- Reversing order[i..j] only replaces the edge entering the segment and the edge
-- leaving it, so a candidate costs two distance evaluations instead of a full
-- rescan of the path.
local function two_opt(islands, order, head)
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

--- Entry point called once per layer and per object instance.
-- @param islands array of {centroid = {x, y}, bbox = {min_x, min_y, max_x, max_y}}
-- @param ctx     {layer_id, print_z, extruder_id, head = {x, y} or nil}
-- @return array of 1-based positions into `islands`, each exactly once
function order_islands(islands, ctx)
    local head = ctx.head
    return two_opt(islands, nearest_neighbour(islands, head), head)
end
