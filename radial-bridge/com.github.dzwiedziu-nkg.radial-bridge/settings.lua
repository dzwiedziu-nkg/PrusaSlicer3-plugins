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

    -- Multiplies the spoke spacing. Above 1.0 the spokes are further apart and use less
    -- material, below 1.0 they crowd together. At 1.0 the spokes lay down as much
    -- material as the pattern they replace.
    density = 1.0,

    -- Refuse to plan a surface that would need more spokes than this.
    max_spokes = 2000,
}
