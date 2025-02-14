local commons = require("scripts.commons")
local tools = require("scripts.tools")

local prefix = commons.prefix
local png = commons.png


local tech_effects = {
	{ type = 'unlock-recipe', recipe = prefix .. '-device' },
	{ type = 'unlock-recipe', recipe = prefix .. '-sushi' }
}

local use_router = true

if use_router then
	table.insert(tech_effects, { type = 'unlock-recipe', recipe = prefix .. '-router' })
end

data:extend {

	-- Item
	{
		type = 'item',
		name = prefix .. '-device',
		icon_size = 64,
		icon = png('item/device'),
		subgroup = 'belt',
		order = '[logistic]-b[elt]',
		place_result = prefix .. '-device',
		stack_size = 50
	},

	{
		type = 'item',
		name = prefix .. '-sushi',
		icon_size = 64,
		icon = png('item/sushi'),
		subgroup = 'belt',
		order = '[logistic]-s[sushi]',
		place_result = prefix .. '-sushi',
		stack_size = 50
	},

	-- Recipe
	{ type = 'recipe',
		name = prefix .. '-device',
		enabled = false,
		ingredients = {
			{ type = 'item', name = 'electronic-circuit', amount = 10 },
			{ type = 'item', name = 'iron-plate',         amount = 30 },
			{ type = 'item', name = 'iron-gear-wheel',    amount = 20 }
		},
		results = { { type = 'item', name = prefix .. '-device', amount = 1 } }
	},
	{ type = 'recipe',
		name = prefix .. '-sushi',
		enabled = false,
		ingredients = {
			{ type = 'item', name = 'electronic-circuit', amount = 2 },
			{ type = 'item', name = 'iron-plate',         amount = 10 },
			{ type = 'item', name = 'iron-gear-wheel',    amount = 5 }
		},
		results = { { type = 'item', name = prefix .. '-sushi', amount = 1 } }
	},

	-- Technology
	{ type = 'technology',
		name = prefix .. '-tech',
		icon_size = 128,
		icon = png('tech'),
		effects = tech_effects,
		prerequisites = { 'logistics' },
		unit = {
			count = 100,
			ingredients = {
				{ 'automation-science-pack', 1 }
			},
			time = 15
		},
		order = 'a-d-d-z'
	},
	{
		type = "sprite",
		name = prefix .. "-chain",
		filename = png("chain"),
		width = 64,
		height = 64
	}


}
