-- Settings for the island print order plugin.
-- Edit and re-slice; no restart and no rescan needed.

return {
    -- "cooling"  Keep the island order the same on every layer, so every island is
    --            revisited exactly one layer time after it was left -- the most any
    --            ordering can give it -- and walk the tour in steps of two so that no
    --            single travel spans more than two island gaps. The safe default.
    --
    -- "travel"   Shortest total travel: nearest neighbour seeded from the head
    --            position, refined by 2-opt. Reverses direction every layer, which
    --            leaves the islands at the turning point with no cooling time at all.
    --            Only for prints where cooling is not a concern -- large, well spread
    --            islands, or a slow filament.
    --
    -- "stock"    Leave the slicer's own order alone. For A/B comparisons without
    --            uninstalling the plugin.
    mode = "cooling",

    -- 2-opt is O(n^2) per pass. Above this many islands on a layer it is skipped and
    -- the greedy chain is used as is.
    max_two_opt_islands = 100,
}
