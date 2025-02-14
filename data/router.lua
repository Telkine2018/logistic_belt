local commons = require("scripts.commons")
local tools = require("scripts.tools")

local prefix = commons.prefix
local png = commons.png

local empty_sprite = {
	filename = png('invisible'),
	width = 1,
	height = 1,
	frame_count = 1
}

local use_router = mods["space-exploration"] == nil or mods["qoltools"]

data:extend {

	-- Item
	{
		type = 'item',
		name = commons.router_name,
		icon_size = 64,
		icon = png('item/router'),
		subgroup = 'belt',
		order = 'z-a',
		place_result = prefix .. '-router',
		stack_size = 50
	}
}

if use_router then
	data:extend {

		-- Recipe
		{ type = 'recipe',
			name = prefix .. '-router',
			enabled = false,
			ingredients = {
				{ type = 'item', name = 'electronic-circuit', amount = 20 },
				{ type = 'item', name = 'iron-plate',      amount = 30 },
				{ type = 'item', name = 'iron-gear-wheel', amount = 10 }
			},
			results = { { type = 'item', name = prefix .. '-router', amount = 1 } }
		}
	}
end

-----------------------------------------------

local commons_attr = {

	flags = { "hide-alt-info", "not-on-map", "not-blueprintable", "not-deconstructable", "not-upgradable",
		"placeable-off-grid" },
	collision_box = { { -0.05, -0.05 }, { 0.05, 0.05 } },
	selection_box = { { -0.05, -0.05 }, { 0.05, 0.05 } },
	collision_mask = nil,
	selectable_in_game = commons.debug_mode
}

local chest = table.deepcopy(data.raw["container"]["steel-chest"])
chest.name = commons.chest_name
chest.picture = empty_sprite
chest.inventory_size = 4
chest = tools.table_merge({ chest, commons_attr })
data:extend { chest }

-----------------------------------------------

local router = table.deepcopy(data.raw["linked-container"]["linked-chest"])

router.name = commons.router_name
router.picture.layers[1].filename = png("entity/hr-router")
router.picture.layers[2].filename = png("entity/hr-router-shadow")
router.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
router.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
router.inventory_size = settings.startup["logistic_belt-router_inventory_size"].value
router.circuit_connector_sprites = chest.circuit_connector_sprites
router.circuit_wire_connection_point = chest.circuit_wire_connection_point
router.circuit_wire_max_distance = chest.circuit_wire_max_distance
router.inventory_type = "with_filters_and_bar"
router.gui_mode = "none"
router.fast_replaceable_group = "logistic_belt-router"
router.minable = { mining_time = 0.5, result = commons.router_name }
data:extend { router }

-- log(serpent.block(router))

-------------------------è----------------------
