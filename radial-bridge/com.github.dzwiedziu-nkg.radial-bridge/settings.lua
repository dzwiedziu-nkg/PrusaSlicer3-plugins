-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Edit and slice again; no restart needed.
return {
    -- Roles the planner may take over. Bridges only by default: this pattern is about
    -- unsupported spans, and an ordinary solid layer has nothing to gain from it.
    filtered_roles = {BridgeInfill = true},

    -- Skip surfaces whose hole is smaller than this, in mm. Below a few millimetres the
    -- spokes crowd together at the centre and the stock pattern is the better answer.
    min_hole_radius = 1.0,

    -- How many spokes, as a multiple of the count that matches the slicer's line spacing
    -- half way out. 1.2 lays a fifth more of them a fifth closer together, 0.8 a fifth
    -- fewer and further apart.
    density = 1.0,

    -- Multiplies the extrusion of the spokes, the way bridge_flow_ratio does for the
    -- stock pattern. Lower it when strands curl up off the bridge: a fan is tighter than
    -- the nominal spacing at the inner edge, which is where too much plastic shows first.
    -- 0.85 to 0.95 is the useful range; below that the strands stop touching.
    flow_ratio = 1.0,

    -- Additionally scale the flow so the surface receives the same volume of plastic the
    -- stock pattern would have put on it. The fan lays a few percent more line than the
    -- parallel pattern it replaces, and this takes that back exactly instead of by
    -- guesswork. Off by default: it thins the outer edge, which is already the sparse one.
    match_stock_material = false,

    -- Refuse to plan a surface that would need more spokes than this.
    max_spokes = 2000,
}
