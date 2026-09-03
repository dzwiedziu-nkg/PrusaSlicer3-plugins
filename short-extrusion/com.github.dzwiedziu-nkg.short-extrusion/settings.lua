-- Settings for the short extrusion filter plugin.
-- Edit and re-slice; no restart and no rescan needed.

return {
    -- An extrusion shorter than this, in millimetres, is dropped. Roughly: below a few
    -- nozzle diameters a segment contributes almost nothing to the part, while the
    -- travel, the two retractions and the acceleration ramps around it cost real time.
    min_length = 2.0,

    -- Per role overrides, in millimetres. Solid infill carries more load than sparse
    -- infill, so it is worth being stricter about what gets removed there.
    min_length_by_role = {
        -- InternalInfill = 3.0,
        -- SolidInfill = 1.0,
        -- Perimeter = 1.5,
    },

    -- Roles the filter is allowed to touch. Anything not listed is always kept, so the
    -- external perimeter, the top surface, bridges, gap fill, supports and the skirt are
    -- out of reach by construction.
    --
    -- Available roles: Perimeter, ExternalPerimeter, OverhangPerimeter, InternalInfill,
    -- SolidInfill, TopSolidInfill, Ironing, BridgeInfill, GapFill, Skirt,
    -- SupportMaterial, SupportMaterialInterface, WipeTower, Custom.
    filtered_roles = {
        Perimeter = true,        -- internal perimeters; the external one has its own role
        InternalInfill = true,
        SolidInfill = true,
    },

    -- Layers below this index are never filtered; they carry the bed adhesion.
    -- 0 filters everything, 1 protects the first layer.
    first_filtered_layer = 1,
}
