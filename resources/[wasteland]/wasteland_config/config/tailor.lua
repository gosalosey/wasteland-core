-- Tailors: NPCs where players restyle the clothes they are wearing (other
-- colours and cuts of the same kind of piece) for cash. Nothing new is
-- added: only pieces already worn can be changed.
--   price     cash per piece changed (a top with its undershirt and arms
--             counts as one piece)
--   coords    where the tailor stands (x, y, z as /coords shows them, heading)
return {
    price = 25,
    model = 's_f_y_shop_mid',
    blip = { sprite = 73, color = 25, label = 'Tailor' },
    shops = {
        { label = 'Paleto Bay Tailor', coords = { x = -447.98, y = 6008.49, z = 31.72, heading = 316.33 } },
        { label = 'Sandy Shores Tailor', coords = { x = 1853.56, y = 3689.56, z = 34.27, heading = 90.33 } },
        { label = 'Legion Square Tailor', coords = { x = 305.29, y = -590.87, z = 43.29, heading = 36.02 } },
    },
}
