local commons = require("scripts.commons")
local tools = require("scripts.tools")

local locallib = {}

local prefix = commons.prefix
local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

local BELT_SPEED_FOR_60_PER_SECOND = 60 / 60 / 8


locallib.BELT_SPEED_FOR_60_PER_SECOND = BELT_SPEED_FOR_60_PER_SECOND

locallib.belt_types = {
	"transport-belt",
	"underground-belt",
	"splitter",
	"linked-belt"
}

locallib.container_types = {
	"container",
	"infinity-container",
	"linked-container",
	"logistic-container"
}

locallib.input_positions = {
	{ { { 0, -1 }, { -0.25, 0 } }, { { 0, -1 }, { 0.25, 0 } } },
	{ { { 0, -2 }, { -0.25, 0 } }, { { 0, -2 }, { 0.25, 0 } } },
	{ { { 0, -3 }, { -0.25, 0 } }, { { 0, -3 }, { 0.25, 0 } } }
}

locallib.output_positions = {
	{ { { -0.25, 0.0 }, { 0, 1 } }, { { 0.25, 0.0 }, { 0, 1 } } },
	{ { { -0.25, 0.0 }, { 0, 2 } }, { { 0.25, 0.0 }, { 0, 2 } } },
	{ { { -0.25, 0.0 }, { 0, 3 } }, { { 0.25, 0.0 }, { 0, 3 } } }
}

---@param master any
---@param loader_name any
---@return unknown
function locallib.create_loader(master, loader_name)
	local loader = master.surface.create_entity {
		name = loader_name,
		position = master.position,
		force = master.force,
		direction = tools.get_opposite_direction(master.direction),
		create_build_effect_smoke = false
	}
	loader.loader_type = "output"
	return loader
end

---@param master LuaEntity
---@return LuaEntity?
function locallib.find_loader(master)
	local entities = master.surface.find_entities_filtered { name = commons.device_loader_name, position = master.position }
	if #entities == 1 then return entities[1] end
	return nil
end

function locallib.clear_entities(device, entity_names)
	if not entity_names then
		entity_names = commons.entities_to_clear
	end
	local entities = device.surface.find_entities_filtered { position = device.position, name = entity_names }
	for _, e in pairs(entities) do
		e.destroy()
	end
end

---@param entity LuaEntity
---@param direction defines.direction
---@param positions MapPosition[][]
---@param count integer
---@param name string
---@return LuaEntity[]
function locallib.create_inserters(entity, direction, positions, count, name)
	local position = entity.position
	local surface = entity.surface
	local inserters = {}
	for _, pick_drop in pairs(positions) do
		for i = 1, count do
			local inserter = surface.create_entity {
				name = name,
				position = entity.position,
				force = entity.force,
				direction = direction,
				create_build_effect_smoke = false
			}
			if inserter then
				local pick = tools.get_local_disp(direction, pick_drop[1])
				inserter.pickup_position = { pick.x + position.x, pick.y + position.y }
				local drop = tools.get_local_disp(direction, pick_drop[2])
				inserter.drop_position = { drop.x + position.x, drop.y + position.y }
				inserter.operable = false
				inserter.destructible = false
				inserter.inserter_stack_size_override = 1

				cdebug(commons.trace_inserter,
					"create new: " .. inserter.name .. " direction=" .. direction .. ",stack=" .. inserter.inserter_stack_size_override)
				cdebug(commons.trace_inserter, "position: " ..
					strip(position) .. " pickup=" .. strip(inserter.pickup_position) .. " drop=" .. strip(inserter.drop_position))
				table.insert(inserters, inserter)
			end
		end
	end
	return inserters
end

---@param device LuaEntity
---@param name string
---@return LuaEntity
function locallib.create_combinator(device, name)
	local combinator = device.surface.create_entity {
		name = prefix .. "-" .. name,
		position = device.position,
		force = device.force,
		create_build_effect_smoke = false
	}
	return combinator
end

---@param belt_speed number
---@return integer
function locallib.get_inserter_count_from_speed(belt_speed)
	return math.ceil(belt_speed / BELT_SPEED_FOR_60_PER_SECOND)
end

---@param entity LuaEntity
---@return integer
function locallib.get_inserter_count(entity)
	return locallib.get_inserter_count_from_speed(entity.prototype.belt_speed)
end

---@param entity LuaEntity
function locallib.save_unit_number_in_circuit(entity)
	local cb = entity.get_or_create_control_behavior()
	cb.circuit_condition = {
		condition = {
			comparator = "=",
			first_signal = { type = "virtual", name = "signal-A" },
			constant = entity.unit_number
		}
	}
end

function locallib.restore_saved_parameters(entity, parameters)
	local cb = entity.get_or_create_control_behavior()
	local found = false
	local condition = cb.circuit_condition
	if condition then
		local old_id = condition.condition.constant
		if old_id then
			if storage.saved_parameters then
				local p = storage.saved_parameters[old_id]
				if p then
					debug("Found saved parameters")
					parameters = p
					storage.parameters[entity.unit_number] = p
					found = true
					storage.saved_parameters[old_id] = nil
				end
			end
		end
	end

	locallib.save_unit_number_in_circuit(entity)
	return parameters
end

function locallib.add_title(frame, caption, width)
	local titlebar = frame.add { type = "flow", direction = "horizontal" }
	local title = titlebar.add {
		type = "label",
		style = "caption_label",
		caption = { caption }
	}
	local handle = titlebar.add {
		type = "empty-widget",
		style = "draggable_space"
	}
	handle.style.horizontally_stretchable = true
	handle.style.top_margin = 4
	handle.style.height = 26
	handle.style.width = width

	local flow_buttonbar = titlebar.add {
		type = "flow",
		direction = "horizontal"
	}
	flow_buttonbar.style.top_margin = 0
	local closeButton = flow_buttonbar.add {
		type = "sprite-button",
		name = prefix .. "_close_button",
		style = "frame_action_button",
		sprite = "utility/close_white",
		mouse_button_filter = { "left" }
	}
end

function locallib.close_ui(player)
	local frame = player.gui.left[commons.device_panel_name]
	if frame then
		frame.destroy()
		return
	end
	frame = player.gui.left[commons.sushi_panel_name]
	if frame then
		frame.destroy()
		return
	end
end

function locallib.on_gui_closed(event)
	local player = game.players[event.player_index]
	locallib.close_ui(player)
end

function locallib.get_parameters(master, create)
	local all = storage.parameters
	if not all then
		all = {}
		storage.parameters = all
	end
	local parameters = all[master.unit_number]
	if not parameters and create then
		parameters = {}
		all[master.unit_number] = parameters
	end
	return parameters
end

function locallib.add_monitored_device(device)
	if not storage.monitored_devices then
		storage.monitored_devices = {}
	end
	storage.monitored_devices[device.unit_number] = device
	debug("ADD Monitored device: " .. tools.strip(device.position))
	storage.monitoring = true
	storage.structure_changed = true
end

function locallib.recompute_device(container)
	local cbox = container.prototype.collision_box
	if cbox then
		local pos = container.position
		local search_box = { { pos.x + cbox.left_top.x - 1, pos.y + cbox.left_top.y - 1 },
			{ pos.x + cbox.right_bottom.x + 1, pos.y + cbox.right_bottom.y + 1 } }
		local devices = container.surface.find_entities_filtered { name = commons.device_name, area = search_box }
		for _, d in ipairs(devices) do
			locallib.add_monitored_device(d)
		end
	end
end

return locallib
