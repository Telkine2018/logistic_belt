local commons = require("scripts.commons")
local tools = require("scripts.tools")

local png = commons.png
local prefix = commons.prefix
local debug_mode = commons.debug_mode
local table_merge = tools.table_merge

local invisible_sprite = { filename = png('invisible'), width = 1, height = 1 }
local wire_conn = { wire = { red = { 0, 0 }, green = { 0, 0 } }, shadow = { red = { 0, 0 }, green = { 0, 0 } } }
local commons_attr = {
	flags = { 'placeable-off-grid' },
	collision_mask = {layers={}},
	minable = nil,
	selectable_in_game = debug_mode,
	circuit_wire_max_distance = 100000,
	sprites = invisible_sprite,
	activity_led_sprites = invisible_sprite,
	activity_led_light_offsets = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
	circuit_wire_connection_points = { wire_conn, wire_conn, wire_conn, wire_conn },
	draw_circuit_wires = debug_mode,
	energy_source = { type = "void" },
	collision_box = nil,
	created_smoke = nil
}

local function insert_flags(flags)

	if not debug_mode then
		table.insert(flags, "hide-alt-info")
		table.insert(flags, "not-on-map")
	end
	table.insert(flags, "not-upgradable")
	table.insert(flags, "not-deconstructable")
	table.insert(flags, "not-blueprintable")
end

---------------------------------

local constant_combinator = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
constant_combinator = table_merge({
	constant_combinator,
	commons_attr, {
		name = prefix .. '-cc',
		item_slot_count = 100
	}
})

insert_flags(constant_combinator.flags)

--------------------------------

local connector_combinator = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
connector_combinator = table_merge({
	connector_combinator,
	commons_attr, {
		name = commons.connector_name,
		item_slot_count = 1
	}
})

insert_flags(connector_combinator.flags)

--------------------------------

local cc2 = table.deepcopy(constant_combinator)
cc2.name = prefix .. "-cc2"

local arithmetic_combinator = table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
arithmetic_combinator       = table_merge({
	arithmetic_combinator,
	commons_attr, {
		name = prefix .. '-ac',
		and_symbol_sprites = invisible_sprite,
		divide_symbol_sprites = invisible_sprite,
		left_shift_symbol_sprites = invisible_sprite,
		minus_symbol_sprites = invisible_sprite,
		plus_symbol_sprites = invisible_sprite,
		multiply_symbol_sprites = invisible_sprite,
		or_symbol_sprites = invisible_sprite,
		modulo_symbol_sprites = invisible_sprite
	}
})
insert_flags(arithmetic_combinator.flags)

--------------------------

local decider_combinator = table.deepcopy(data.raw["decider-combinator"]["decider-combinator"])
decider_combinator       = table_merge({
	decider_combinator,
	commons_attr, {
		name = prefix .. '-dc',
		equal_symbol_sprites = invisible_sprite,
		greater_or_equal_symbol_sprites = invisible_sprite,
		greater_symbol_sprites = invisible_sprite,
		less_or_equal_symbol_sprites = invisible_sprite,
		less_symbol_sprites = invisible_sprite,
		not_equal_symbol_sprites = invisible_sprite
	}
})
insert_flags(decider_combinator.flags)

-----------------------------------

local pole = {

	type = "electric-pole",
	name = commons.pole_name,
	minable = nil,
	collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } },
	collision_mask = {layers={}},
	selection_box = { { -0.1, -0.1 }, { 0.1, 0.1 } },
	draw_copper_wires = debug_mode,
	draw_circuit_wires = debug_mode,
	connection_points = {
		{ wire = { red = { 0, 0 }, green = { 0, 0 } }, shadow = { red = { 0, 0 }, green = { 0, 0 } } }
	},
	selectable_in_game = debug_mode,
	pictures = {
		count = 1,
		filename = png("invisible"),
		width = 1,
		height = 1,
		direction_count = 1
	},
	maximum_wire_distance = 64,
	supply_area_distance = 0.5,
	max_health = 10,
	flags = { }
}
insert_flags(pole.flags)

------------------------------------

data:extend {
	constant_combinator,
	cc2,
	arithmetic_combinator,
	decider_combinator,
	pole,
	connector_combinator
}
