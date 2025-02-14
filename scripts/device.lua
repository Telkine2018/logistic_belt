local migration = require("__flib__.migration")

local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"
local sushilib = require "scripts.sushilib"
local routerlib = require "scripts.routerlib"
local containerlib = require "scripts.containerlib"
local inspectlib = require "scripts.inspect"
local update = require "scripts.update"

local prefix = commons.prefix
local trace_scan = false
local SAVED_SCAVENGE_DELAY = 120 * 60

local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

-----------------------------------------------------

local NTICK_COUNT = 60

local device_name = commons.device_name
local inserter_name = commons.inserter_name
local filter_name = commons.filter_name
local device_loader_name = commons.device_loader_name
local slow_filter_name = commons.slow_filter_name
local sushi_name = commons.sushi_name
local sushi_loader_name = commons.sushi_loader_name

local link_to_output_chest_name = prefix .. "-link_to_output_chest"
local is_input_filtered_name = prefix .. "-is_input_filtered"
local request_count_name = prefix .. "-request_count"

local container_types_map = tools.table_map(locallib.container_types, function(key, value) return value, true end)
local entities_to_clear = commons.entities_to_clear
local entities_to_destroy = tools.table_copy(entities_to_clear) or {}
table.insert(entities_to_destroy, device_loader_name)
table.insert(entities_to_destroy, sushi_loader_name)

local device_panel_name = commons.device_panel_name
local sushi_panel_name = commons.sushi_panel_name

local get_front = tools.get_front
local get_back = tools.get_back
local get_opposite_direction = tools.get_opposite_direction


local create_loader = locallib.create_loader
local find_loader = locallib.find_loader
local create_inserters = locallib.create_inserters
local clear_entities = locallib.clear_entities

local function find_cc_request(device)
	local entities = device.surface.find_entities_filtered { name = prefix .. "-cc2", position = device.position,
		radius = 0.4 }
	if #entities == 1 then return entities[1] end
	return nil
end

local function adjust_direction(device)

	local direction = device.direction
	local position = device.position
	local front_pos = get_front(direction, position)

	-- device.direction => belt
	local entities = device.surface.find_entities_filtered { position = front_pos, type = locallib.belt_types }
	if (#entities > 0) then
		debug("no change direction")
		return true, false
	end

	local opposite     = get_opposite_direction(direction)
	local opposite_pos = get_front(opposite, position)
	entities           = device.surface.find_entities_filtered { position = opposite_pos, type = locallib.belt_types }
	if (#entities > 0) then
		debug("invert direction:" .. opposite)
		device.direction = opposite
		return true, true
	end

	entities = device.surface.find_entities_filtered { position = front_pos, type = locallib.container_types }
	if (#entities > 0) then
		debug("invert direction (container):" .. opposite)
		device.direction = opposite
		return true, true
	end

	entities = device.surface.find_entities_filtered { position = opposite_pos, type = locallib.container_types }
	if (#entities > 0) then
		debug("no change direction")
		return true, false
	end

	debug("no entities found")
	return false
end

--[[
local output_positions = {
	{ { -0.25, -0.6 }, { 0, 1 } },
	{ { 0.25, -0.6 }, { 0, 1 } }
}
local input_positions = {
	{ { 0, -1 }, { -0.25, 0.6 } },
	{ { 0, -1 }, { 0.25, 0.6 } }
}
]] --

local function get_entity_parameters(device, create)
	local all = storage.parameters
	if not all then
		all = {}
		storage.parameters = all
	end
	local parameters = all[device.unit_number]
	if not parameters and create then
		parameters = {
			is_link_to_output_chest = settings.storage[link_to_output_chest_name].value,
			is_input_filtered = settings.storage[is_input_filtered_name].value,
			is_overflow = false,
			is_requested_disconnected = false,
			is_slow = false
		}
		all[device.unit_number] = parameters
	end
	return parameters
end

local function scan_network(device)

	local position = get_front(device.direction, device.position)
	local entities = device.surface.find_entities_filtered { position = position, type = locallib.belt_types }

	if #entities == 0 then return end

	local belt = entities[1]

	debug("device: " .. strip(device.position))

	local to_scan = { [belt.unit_number] = belt }
	local scanned = {}

	local loaders = {}

	local function add_to_scan(b, output)

		if b.name == device_loader_name then
			debug("Scan loader: " .. strip(b.position) .. ",direction=" .. b.direction)
			loaders[b.unit_number] = { loader = b, output = output }
			return false
		end
		if not scanned[b.unit_number] then
			to_scan[b.unit_number] = b
		end
		return true
	end

	local content = {}
	while true do

		local id, belt = next(to_scan)
		if id == nil then
			break
		end
		to_scan[id] = nil
		scanned[id] = belt
		---@cast belt -nil
		local neightbours = belt.belt_neighbours
		local has_input = false
		local has_output = false

		cdebug(trace_scan, "Scan: " ..
			belt.name ..
			",pos=" ..
			strip(belt.position) ..
			",direction=" .. belt.direction .. ",#inputs=" .. #neightbours.inputs .. ",#outputs" .. #neightbours.outputs)

		if neightbours.inputs and #neightbours.inputs == 0 then
			local back_pos = get_back(belt.direction, belt.position);
			local loaderlist = belt.surface.find_entities_filtered { name = device_loader_name, position = back_pos }
			if #loaderlist == 1 then
				add_to_scan(loaderlist[1], false)
				loaderlist[1].loader_type = "output"
			end
		else
			for _, child in ipairs(neightbours.inputs) do
				if add_to_scan(child, false) then
					has_input = true
				end
			end
		end

		if #neightbours.outputs == 0 then
			local front_pos = get_front(belt.direction, belt.position);
			local loaderlist = belt.surface.find_entities_filtered { name = device_loader_name, position = front_pos }
			if #loaderlist == 1 then
				add_to_scan(loaderlist[1], true)
				loaderlist[1].loader_type = "input"
			end
		else
			for _, child in ipairs(neightbours.outputs) do
				if add_to_scan(child, true) then
					has_output = true
				end
			end
		end
		if belt.type == "underground-belt" then
			neightbours = belt.neighbours
			if neightbours then
				add_to_scan(neightbours)
				if has_input then
					has_output = true
				elseif has_output then
					has_input = true
				end
			end
		elseif belt.type == "linked-belt" then
			local n = belt.linked_belt_neighbour
			if n then
				add_to_scan(n)
			end
		end

		if belt.name == "entity-ghost" then
			return nil, nil, nil, true
		end

		local t_count = belt.get_max_transport_line_index()
		for i = 1, t_count do
			local t = belt.get_transport_line(i)
			if t then
				local t_content = t.get_contents()
				for item, count in pairs(t_content) do
					content[item] = (content[item] or 0) - count
				end
			end
		end
	end

	return loaders, scanned, content, false
end

local function build_device_list(loaders, player)

	local devices = {}
	local has_input = false
	local has_output = false
	for _, l in pairs(loaders) do
		local loader = l.loader
		local position = loader.position

		debug("==> End: " .. loader.name .. ",pos=" .. strip(position))

		local device_list = loader.surface.find_entities_filtered { position = position, name = device_name }
		if #device_list > 0 then
			local device = device_list[1]
			local search_pos = get_front(device.direction, device.position)
			debug("SearchPOS:" .. strip(search_pos))
			debug("Device: " ..
				device.name ..
				",pos=" .. strip(device.position) .. ",direction=" .. device.direction .. ",output=" .. tostring(l.output))

			local belts = loader.surface.find_entities_filtered { type = locallib.belt_types, position = search_pos }
			if #belts == 0 then
				debug("Cannot find belt")
				return nil
			end

			local belt = belts[1]
			table.insert(devices,
				{ device = device, output = l.output, direction = device.direction, belt = belt, loader = loader })

			if l.output then
				has_output = true
			else
				has_input = true
			end
		end
	end

	if not has_input then
		debug("missing input")
		if player then
			player.print({ "message.missing_input" })
		end
		return nil
	end

	if not has_output then
		debug("missing output")
		if player then
			player.print({ "message.missing_output" })
		end
		return nil
	end

	return devices
end

local function clear_device_list(devices)
	for _, d in ipairs(devices) do
		local device = d.device
		clear_entities(device)
	end
end

local function stop_network(device)
	local loaders = scan_network(device)
	if not loaders then return end

	local devices = build_device_list(loaders)
	if not devices then return end

	for _, d in ipairs(devices) do
		local device = d.device
		if not d.output then
			clear_entities(device)
		end
	end
end

local function is_output(device)
	local entities = device.surface.find_entities_filtered { position = device.position, name = inserter_name }
	return #entities >= 1
end

local function copy_request_to_filter(device, request_table)
	local filter_count = device.prototype.filter_count
	if request_table then
		for i = 1, filter_count do
			local req = request_table[i]
			device.set_filter(i, req and req.item or nil)
		end
	else
		for i = 1, filter_count do
			device.set_filter(i, nil)
		end
	end
end

local function install_requests(request_table, cc2)

	if not request_table then return end

	local cb = cc2.get_or_create_control_behavior()
	cb.parameters = nil
	local signals = {}
	for index, req in pairs(request_table) do
		table.insert(signals, { signal = { type = "item", name = req.item }, count = req.count, index = index })
	end
	cb.parameters = signals

	debug("FILTER:" .. strip(signals))
end

local function rebuild_network(device, player)

	local loaders, _, content, is_ghost = scan_network(device)
	if not loaders then return false, is_ghost end

	local devices = build_device_list(loaders, player)
	if not devices then return false end

	clear_device_list(devices)

	local master = devices[1].device

	--------------------
	local tick_inverser = locallib.create_combinator(master, "ac")
	local cb_counter = tick_inverser.get_or_create_control_behavior()
	local p = cb_counter.parameters
	p.operation = "-"
	p.first_signal = nil
	p.first_constant = 0
	p.second_signal = { type = "virtual", name = "signal-each" }
	p.output_signal = { type = "virtual", name = "signal-each" }
	cb_counter.parameters = p


	--------------------
	local counter = locallib.create_combinator(master, "dc")
	cb_counter = counter.get_or_create_control_behavior()
	p = cb_counter.parameters
	p.first_signal = { type = "virtual", name = "signal-A" }
	p.constant = 0
	p.comparator = "="
	p.output_signal = { type = "virtual", name = "signal-everything" }
	p.copy_count_from_input = true
	cb_counter.parameters = p


	--------------------
	local in_inverser = locallib.create_combinator(master, "ac")
	cb_counter = in_inverser.get_or_create_control_behavior()
	p = cb_counter.parameters
	p.operation = "-"
	p.first_signal = nil
	p.first_constant = 0
	p.second_signal = { type = "virtual", name = "signal-each" }
	p.output_signal = { type = "virtual", name = "signal-each" }
	cb_counter.parameters = p

	tick_inverser.connect_neighbour({
		wire = defines.wire_type.green,
		source_circuit_id = defines.circuit_connector_id.combinator_output,
		target_circuit_id = defines.circuit_connector_id.combinator_input,
		target_entity = counter
	})
	counter.connect_neighbour({
		wire = defines.wire_type.green,
		source_circuit_id = defines.circuit_connector_id.combinator_output,
		target_circuit_id = defines.circuit_connector_id.combinator_input,
		target_entity = counter
	})
	in_inverser.connect_neighbour({
		wire = defines.wire_type.red,
		source_circuit_id = defines.circuit_connector_id.combinator_output,
		target_circuit_id = defines.circuit_connector_id.combinator_output,
		target_entity = counter
	})

	-- Anything in belts ?
	if content and next(content) ~= nil then
		local cc_stock = locallib.create_combinator(device, "cc")

		cc_stock.connect_neighbour({
			wire = defines.wire_type.red,
			target_circuit_id = defines.circuit_connector_id.combinator_output,
			target_entity = counter
		})

		local cb_stock = cc_stock.get_or_create_control_behavior()
		local signals = {}
		local index = 1
		for item, count in pairs(content) do
			table.insert(signals, { signal = { type = "item", name = item }, count = count, index = index })
			index = index + 1
		end
		cb_stock.parameters = signals
	end


	local container_set = {}
	for _, d in ipairs(devices) do
		local device = d.device
		local inserter_count = locallib.get_inserter_count(d.belt)
		local parameters = get_entity_parameters(device, true)

		if storage.monitored_devices ~= nil then
			storage.monitored_devices[device.unit_number] = nil
			if device.unit_number == storage.monitored_devices_key then
				storage.monitored_devices_key = nil
			end
		end

		if not parameters.is_overflow then

			if parameters.request_table then
				local cc_request = locallib.create_combinator(device, "cc2")
				cc_request.connect_neighbour({
					wire = defines.wire_type.red,
					target_circuit_id = defines.circuit_connector_id.combinator_output,
					target_entity = counter
				})
				install_requests(parameters.request_table, cc_request)
			end

			copy_request_to_filter(device, parameters.request_table)
		end

		-- output
		debug("rebuild_network: " .. strip(device.position))

		if d.output then

			local loader = d.loader
			loader.loader_type = "input"

			local output_position = get_back(d.direction, device.position)
			local containers
			local disp = 1
			while disp <= 3 do
				containers = device.surface.find_entities_filtered { position = output_position, type = locallib.container_types }
				if #containers > 0 then break end
				disp = disp + 1
				output_position = get_back(d.direction, output_position)
			end
			if disp > 3 then disp = 1 end
			debug("search output container: #=" ..
				#containers ..
				"," ..
				strip(output_position) ..
				",direction=" .. tools.get_constant_name(d.direction, defines.direction) .. ",disp=" .. disp)


			local positions = locallib.output_positions[disp]
			local inserters = create_inserters(device, d.direction, positions, disp * inserter_count,
				inserter_name)

			-- Output of the belt
			local cc = locallib.create_combinator(device, "cc")
			local cb

			-- Input existing stock
			cc.connect_neighbour({
				wire = defines.wire_type.green,
				target_entity = device
			})

			-- Invert stock
			cc.connect_neighbour({
				wire = defines.wire_type.green,
				target_circuit_id = defines.circuit_connector_id.combinator_input,
				target_entity = in_inverser
			})

			-- CC red is counter output
			cc.connect_neighbour({
				wire = defines.wire_type.red,
				target_circuit_id = defines.circuit_connector_id.combinator_input,
				target_entity = counter
			})


			for _, inserter in ipairs(inserters) do
				local cb                      = inserter.get_or_create_control_behavior()
				cb.circuit_mode_of_operation  = defines.control_behavior.inserter.circuit_mode_of_operation.none
				cb.circuit_read_hand_contents = true
				cb.circuit_hand_read_mode     = defines.control_behavior.inserter.hand_read_mode.pulse
				inserter.connect_neighbour({
					wire = defines.wire_type.red,
					source_circuit_id = defines.circuit_connector_id.inserter,
					target_entity = cc
				})
			end

			local is_container_connected = false
			if #containers > 0 then

				local container = containers[1]
				if container.name ~= commons.router_name then
					if not container_set[container.unit_number] then
						if parameters.is_link_to_output_chest then
							container.connect_neighbour({
								wire = defines.wire_type.green,
								target_entity = cc
							})
						end
						container_set[container.unit_number] = true
						containerlib.connect_to_pole(device, container)
					else
						is_container_connected = true
						containerlib.disconnect_from_pole(device, container)
					end
				else
					local pole = routerlib.get_or_create_pole_from_router(container)
					if pole and pole.valid then
						if not container_set[pole.unit_number] then
							container_set[pole.unit_number] = true
							routerlib.connect_to_output_chest(container, cc)
							routerlib.connect_device(container, device)
						else
							is_container_connected = true
							routerlib.disconnect_device(container, device)
						end
					end
				end
			else
				output_position = get_back(d.direction, device.position)
				local machines = device.surface.find_entities_filtered { position = output_position,
					type = { "assembling-machine" } }
				if #machines == 0 then
					tools.print("Not output containers, position=" ..
						strip(output_position) .. ",direction=" .. tools.get_constant_name(d.direction, defines.direction)
						.. ",surface=" .. device.surface.name)
					clear_entities(device, entities_to_clear)
					return false
				end
			end

			-- Input to add request
			if not parameters.is_requested_disconnected and not is_container_connected then
				local request_buf       = locallib.create_combinator(device, "dc")
				cb                      = request_buf.get_or_create_control_behavior()
				p                       = cb.parameters
				p.first_signal          = { type = "virtual", name = "signal-each" }
				p.constant              = 0
				p.comparator            = ">"
				p.output_signal         = { type = "virtual", name = "signal-each" }
				p.copy_count_from_input = true
				cb.parameters           = p

				device.connect_neighbour({
					wire = defines.wire_type.red,
					target_circuit_id = defines.circuit_connector_id.combinator_input,
					target_entity = request_buf
				})

				request_buf.connect_neighbour({
					wire = defines.wire_type.red,
					source_circuit_id = defines.circuit_connector_id.combinator_output,
					target_circuit_id = defines.circuit_connector_id.combinator_output,
					target_entity = counter
				})
			end

			-- Input of the belt
		else

			local loader = d.loader
			loader.loader_type = "output"

			local container_position = get_back(d.direction, device.position)
			local disp = 1
			local containers
			while disp <= 3 do
				containers = device.surface.find_entities_filtered { position = container_position, type = locallib.container_types }
				if #containers > 0 then break end
				disp = disp + 1
				container_position = get_back(d.direction, container_position)
			end
			if disp > 3 then disp = 1 end

			-- Create main combinator for input
			local cc = locallib.create_combinator(device, "cc")
			local filter_combi = cc
			local target_filter_combi = defines.circuit_connector_id.constant_combinator

			cc.connect_neighbour({
				wire = defines.wire_type.red,
				target_circuit_id = defines.circuit_connector_id.combinator_output,
				target_entity = counter
			})

			if not parameters.is_overflow then

				local positions = locallib.input_positions
				local inserters
				if parameters.slow then
					inserters = create_inserters(device, get_opposite_direction(d.direction), { positions[disp][1] }, 1,
						slow_filter_name)
				else
					inserters = create_inserters(device, get_opposite_direction(d.direction), positions[disp], disp * inserter_count,
						filter_name)
				end

				if not parameters.is_input_filtered then
					filter_combi = cc
				else
					if #containers > 0 then
						local container = containers[1]

						-- compute final filter
						local filter_ac = locallib.create_combinator(device, "ac")
						local cb = filter_ac.get_or_create_control_behavior()
						p = cb.parameters
						p.operation = "-"
						p.first_signal = { type = "virtual", name = "signal-each" }
						p.second_signal = nil
						p.second_constant = 100000000
						p.output_signal = { type = "virtual", name = "signal-each" }
						cb.parameters = p

						-----
						local multiplier_ac = locallib.create_combinator(device, "ac")
						cb = multiplier_ac.get_or_create_control_behavior()
						p = cb.parameters
						p.operation = "*"
						p.first_signal = { type = "virtual", name = "signal-each" }
						p.second_signal = nil
						p.second_constant = 100000000
						p.output_signal = { type = "virtual", name = "signal-each" }
						cb.parameters = p

						-----
						local filter_dc = locallib.create_combinator(device, "dc")
						cb = filter_dc.get_or_create_control_behavior()
						p = cb.parameters
						p.first_signal = { type = "virtual", name = "signal-everything" }
						p.constant = 0
						p.comparator = ">"
						p.output_signal = { type = "virtual", name = "signal-everything" }
						p.copy_count_from_input = false
						cb.parameters = p

						cc.connect_neighbour({
							wire = defines.wire_type.red,
							target_circuit_id = defines.circuit_connector_id.combinator_input,
							target_entity = filter_ac
						})

						filter_combi = filter_ac
						target_filter_combi = defines.circuit_connector_id.combinator_output

						container.connect_neighbour({
							wire = defines.wire_type.red,
							target_circuit_id = defines.circuit_connector_id.combinator_input,
							target_entity = filter_dc
						})
						filter_dc.connect_neighbour({
							wire = defines.wire_type.red,
							source_circuit_id = defines.circuit_connector_id.combinator_output,
							target_entity = multiplier_ac,
							target_circuit_id = defines.circuit_connector_id.combinator_input
						})
						multiplier_ac.connect_neighbour({
							wire = defines.wire_type.green,
							source_circuit_id = defines.circuit_connector_id.combinator_output,
							target_entity = filter_ac,
							target_circuit_id = defines.circuit_connector_id.combinator_input
						})

						--[[
					device.connect_neighbour({
						wire = defines.wire_type.green,
						target_entity = filter_ac,
						target_circuit_id = defines.circuit_connector_id.combinator_output
					})
					]] --
					end
				end

				local is_container_connected = false
				if #containers > 0 then
					local container = containers[1]
					if container.name == commons.router_name then
						local pole = routerlib.get_or_create_pole_from_router(container)
						---@cast pole -nil
						is_container_connected = container_set[pole.unit_number]
						container_set[pole.unit_number] = true
						routerlib.connect_device(container, device)
					else
						containerlib.connect_to_pole(device, container)
						is_container_connected = container_set[container.unit_number]
						container_set[container.unit_number] = true
					end
				end

				for _, inserter in ipairs(inserters) do
					cb_counter                            = inserter.get_or_create_control_behavior()
					cb_counter.circuit_mode_of_operation  = defines.control_behavior.inserter.circuit_mode_of_operation.set_filters
					cb_counter.circuit_read_hand_contents = false

					inserter.connect_neighbour({
						wire = defines.wire_type.red,
						source_circuit_id = defines.circuit_connector_id.inserter,

						target_entity = filter_combi,
						target_circuit_id = target_filter_combi
					})
				end

				-- Ouput requested items to red
				if not parameters.is_requested_disconnected and not is_container_connected then

					local output_dc         = locallib.create_combinator(device, "dc")
					local cb                = output_dc.get_or_create_control_behavior()
					p                       = cb.parameters
					p.first_signal          = { type = "virtual", name = "signal-each" }
					p.constant              = 0
					p.comparator            = ">"
					p.output_signal         = { type = "virtual", name = "signal-each" }
					p.copy_count_from_input = true
					cb.parameters           = p

					device.connect_neighbour {
						wire = defines.wire_type.red,
						target_entity = output_dc,
						target_circuit_id = defines.circuit_connector_id.combinator_output,
					}
					counter.connect_neighbour {
						wire = defines.wire_type.red,
						source_circuit_id = defines.circuit_connector_id.combinator_output,
						target_entity = output_dc,
						target_circuit_id = defines.circuit_connector_id.combinator_input,
					}
				end

			else

				if #containers > 0 then

					local container = containers[1]
					if parameters.request_table then

						local positions = locallib.input_positions[disp]

						for _, req in pairs(parameters.request_table) do
							local inserters = create_inserters(device, get_opposite_direction(d.direction), positions, disp * inserter_count,
								filter_name)

							for _, inserter in pairs(inserters) do

								inserter.set_filter(1, req.item)
								inserter.connect_neighbour {
									wire = defines.wire_type.green,
									target_entity = container
								}

								local cb                      = inserter.get_or_create_control_behavior()
								cb.circuit_read_hand_contents = false
								cb.circuit_set_stack_size     = false
								cb.circuit_condition          = {
									condition = {
										comparator = ">=",
										first_signal = { type = "item", name = req.item },
										constant = req.count
									}
								}
								cb.circuit_mode_of_operation  = defines.control_behavior.inserter.circuit_mode_of_operation.enable_disable

							end
						end
					end
				end

			end

			-- Belt reading
			local cb_belt = d.belt.get_or_create_control_behavior()
			if not cb_belt then
				if player then
					player.print({ "message.need_a_single_transport_belt" })
				end
				debug("End with underground or splitter")
				clear_entities(device, entities_to_clear)
				return false
			end
			cb_belt.enable_disable     = false
			cb_belt.read_contents      = true
			cb_belt.read_contents_mode = defines.control_behavior.transport_belt.content_read_mode.pulse
			d.belt.connect_neighbour({
				wire = defines.wire_type.green,
				target_circuit_id = defines.circuit_connector_id.combinator_input,
				target_entity = cc
			})
			cc.connect_neighbour({
				wire = defines.wire_type.green,
				target_circuit_id = defines.circuit_connector_id.combinator_input,
				target_entity = tick_inverser
			})
		end
		debug("Inserter count:" .. inserter_count)
	end
	return true
end

local function process_monitored_object()

	if storage.saved_parameters ~= nil and next(storage.saved_parameters) then
		local tick = game.tick
		if not storage.saved_time then
			storage.saved_time = tick
		elseif storage.saved_time < tick - SAVED_SCAVENGE_DELAY then
			storage.saved_time = tick
			local removed = {}
			local limit = tick - SAVED_SCAVENGE_DELAY
			for id, parameters in pairs(storage.saved_parameters) do
				if parameters.tick < limit then
					table.insert(removed, id)
				end
			end
			if #removed > 0 then
				for _, id in pairs(removed) do
					storage.saved_parameters[id] = nil
				end
			end
		end
	end
	if not storage.monitoring then return end

	if not storage.structure_changed then
		return
	end

	storage.structure_changed = false
	local saved_tracing = tools.is_tracing()
	tools.set_tracing(false)
	local new_monitored_list = {}
	if storage.monitored_devices then

		storage.monitored_devices_key = nil
		while true do
			local key, device = next(storage.monitored_devices, storage.monitored_devices_key)
			if key == nil then
				break
			end
			storage.monitored_devices_key = key
			---@cast device -nil
			if device.valid then
				local success = rebuild_network(device)
				if not success then
					new_monitored_list[device.unit_number] = device
				end
			end
		end
	end

	if next(new_monitored_list) == nil then
		storage.monitored_devices = nil
		storage.monitored_devices_key = nil
		storage.monitoring = false
		debug("STOP MONITORING")
	else
		storage.monitored_devices = new_monitored_list
	end
	tools.set_tracing(saved_tracing)
end

local function initialize_device(device, parameters)
	device.rotatable = false
	device.active = false
	create_loader(device, device_loader_name)
	copy_request_to_filter(device, parameters.request_table)

	if not rebuild_network(device) then
		locallib.add_monitored_device(device)
	end
end

local function on_build(entity, e)
	if not entity or not entity.valid then return end

	storage.structure_changed = true
	local name = entity.name
	local tags = e.tags
	if name == device_name then

		local parameters = get_entity_parameters(entity, true)
		if tags then
			parameters.request_table = tags.request_table and helpers.json_to_table(tags.request_table)
			parameters.is_link_to_output_chest = tags.is_link_to_output_chest
			parameters.is_input_filtered = tags.is_input_filtered
			parameters.is_overflow = tags.is_overflow
			parameters.is_requested_disconnected = tags.is_requested_disconnected
			parameters.slow = tags.slow
		else
			parameters = locallib.restore_saved_parameters(entity, parameters)
		end

		entity.active = false
		if not adjust_direction(entity) then
			entity.rotatable = false
			create_loader(entity, device_loader_name)
			locallib.add_monitored_device(entity)
			return
		end
		initialize_device(entity, parameters)

	elseif name == sushi_name then
		sushilib.on_build(entity, e)
	elseif name == commons.router_name then
		routerlib.on_build(entity, e)
	else
		locallib.recompute_device(entity)
		if tags and tags.is_belt_linked then
			local player = nil
			if e.player_index then
				player = game.players[e.player_index]
			end
			containerlib.create_connection(entity, player)
		end
	end
end

local function on_robot_built(ev)
	local entity = ev.created_entity

	on_build(entity, ev)
end

local function on_script_built(ev)
	local entity = ev.entity

	on_build(entity, ev)
end

local function on_script_revive(ev)
	local entity = ev.entity

	on_build(entity, ev)
end

local function on_player_built(ev)
	local entity = ev.created_entity

	on_build(entity, ev)
end

local function on_mined(ev)

	local entity = ev.entity
	if not entity.valid then return end

	if entity.name == device_name or entity.name == sushi_name then

		if storage.parameters then
			local parameters = storage.parameters[entity.unit_number]
			if parameters then
				storage.parameters[entity.unit_number] = nil
				if not storage.saved_parameters then
					storage.saved_parameters = {}
				end
				parameters.tick = game.tick
				storage.saved_parameters[entity.unit_number] = parameters
			end
		end

		tools.close_ui(entity.unit_number, locallib.close_ui)

		-- local buffer = ev.buffer and ev.buffer.valid and ev.buffer
		clear_entities(entity, entities_to_destroy)
	elseif entity.name == commons.router_name then

		routerlib.on_mined(ev)
	else
		containerlib.on_mined(entity)
	end
end

local function on_player_mined_entity(ev)
	on_mined(ev)
end

local function on_gui_open_device_panel(event)

	local player = game.players[event.player_index]

	local entity = event.entity
	if not entity or not entity.valid or entity.name ~= device_name then
		return
	end

	locallib.on_gui_closed(event)

	player.opened = nil
	local vars = get_vars(player)
	vars.selected = entity
	vars.changed = false

	local parameters = get_entity_parameters(entity, true)

	local panel = player.gui.left.add {
		type = "frame",
		name = device_panel_name,
		direction = "vertical"
	}
	locallib.add_title(panel, "parameters_dialog.title", 300)

	local loader = find_loader(entity)
	local request_flow = panel.add { type = "table", style_mods = { margin = 10 }, column_count = 10,
		name = prefix .. "-request_table" }
	local f
	for i = 1, settings.global[request_count_name].value do
		local item_field = request_flow.add {
			type = "choose-elem-button",
			name = prefix .. "-request-" .. i,
			--tooltip = { "tooltip." .. prefix .. "-request" },
			elem_type = "item"
		}
		local count_field = request_flow.add {
			type = "textfield",
			name = prefix .. "-count-" .. i,
			tooltip = { "tooltip." .. prefix .. "-request-count" },
			numeric = true
		}
		count_field.style.width = 50
		if parameters.request_table then
			local req = parameters.request_table[i]
			if req then
				item_field.elem_value = req.item
				count_field.text = tostring(req.count)
			end
		end
	end

	if loader then
		if loader.loader_type == "input" then

			local b_is_link_to_output_chest = panel.add { type = "checkbox", state = parameters.is_link_to_output_chest or false,
				name = "is_link_to_output_chest", caption = { "parameters.is_link_to_output_chest" },
				tooltip = { "tooltip.logistic_belt-link_to_output_chest" } }
		else
			local b_is_input_filtered = panel.add { type = "checkbox", state = parameters.is_input_filtered or false,
				name = "is_input_filtered", caption = { "parameters.is_input_filtered" },
				tooltip = { "tooltip.logistic_belt-is_input_filtered" } }
			local b_is_slow = panel.add { type = "checkbox", state = parameters.slow or false,
				name = "is_slow", caption = { "parameters.is_slow" }, tooltip = { "tooltip.logistic_belt-is_slow" } }
			local b_is_overflow = panel.add { type = "checkbox", state = parameters.is_overflow or false,
				name = "is_overflow", caption = { "parameters.is_overflow" }, tooltip = { "tooltip.logistic_belt-is_overflow" } }
		end
	end
	local b_is_requested_disconnected = panel.add { type = "checkbox", state = parameters.is_requested_disconnected or false,
		name = "is_requested_disconnected", caption = { "parameters.is_requested_disconnected" },
		tooltip = { "tooltip.is_requested_disconnected" } }

	local bflow = panel.add { type = "flow", direction = "horizontal" }
	local b = bflow.add {
		type = "button",
		name = prefix .. "_save",
		caption = { "button.save" }
	}
	local bwidth = 100
	b.style.horizontally_stretchable = false
	b.style.width = bwidth
	b = bflow.add {
		type = "button",
		name = prefix .. "_rebuild",
		caption = { "button.rebuild" }
	}
	b.style.horizontally_stretchable = true
	b.style.width = bwidth

	b = bflow.add {
		type = "button",
		name = prefix .. "_stop",
		caption = { "button.stop" }
	}
	b.style.horizontally_stretchable = true
	b.style.width = bwidth

	if tools.is_tracing() then
		b = bflow.add {
			type = "button",
			name = prefix .. "_diag",
			caption = { "button.diag" }
		}
		b.style.horizontally_stretchable = true
		b.style.horizontal_align = "center"
	end

	player.opened = panel
end

local function debug_signal(name, signals)
	if signals then
		for i, signal in ipairs(signals) do
			debug("=> " .. name .. ": " .. signal.signal.name .. "=" .. signal.count)
		end
	end
end

local function save_device_parameters(player)

	local device = get_vars(player).selected
	if not device or not device.valid then return nil end

	local parameters = get_entity_parameters(device, true)
	local frame = player.gui.left[device_panel_name]
	if not frame then return end

	local f_is_overflow = tools.get_child(frame, "is_overflow")
	if f_is_overflow then
		parameters.is_overflow = f_is_overflow.state
	end

	local f_reqtable = tools.get_child(frame, prefix .. "-request_table")
	if f_reqtable ~= nil then

		local request_table = {}
		for i = 1, settings.global[request_count_name].value do
			local f_item = f_reqtable[prefix .. "-request-" .. i]
			local f_count = f_reqtable[prefix .. "-count-" .. i]
			if f_item and f_count then
				local item = f_item.elem_value
				local tcount = f_count.text
				if item and tcount and #item > 0 and #tcount > 0 and (tonumber(tcount) > 0 or parameters.is_overflow) then
					table.insert(request_table, { item = item, count = tonumber(tcount) })
				end
			end
		end
		parameters.request_table = request_table
		copy_request_to_filter(device, request_table)
	end

	local f_is_link_to_output_chest = tools.get_child(frame, "is_link_to_output_chest")
	if f_is_link_to_output_chest then
		parameters.is_link_to_output_chest = f_is_link_to_output_chest.state
	end
	local f_is_input_filtered = tools.get_child(frame, "is_input_filtered")
	if f_is_input_filtered then
		parameters.is_input_filtered = f_is_input_filtered.state
	end
	local f_is_slow = tools.get_child(frame, "is_slow")
	if f_is_slow then
		parameters.slow = f_is_slow.state
	end
	local f_is_requested_disconnected = tools.get_child(frame, "is_requested_disconnected")
	if f_is_requested_disconnected then
		parameters.is_requested_disconnected = f_is_requested_disconnected.state
	end

	return device
end

local function on_save(e)
	local player = game.players[e.player_index]

	local device = save_device_parameters(player)
	if device then
		rebuild_network(device, player)
	end
	locallib.on_gui_closed(e)
end

local function on_auto_save(e)

	if not e.element or e.element.name ~= device_panel_name then return end
	local player = game.players[e.player_index]
	local vars = get_vars(player)
	if vars.changed then
		vars.changed = false
		on_save(e)
	else
		locallib.on_gui_closed(e)
	end
end

tools.on_gui_click(prefix .. "_save", on_save)
tools.on_event(defines.events.on_gui_opened, on_gui_open_device_panel)

local function on_gui_confirmed(e)

	local player = game.players[e.player_index]

	local panel = player.gui.left[device_panel_name]
	local name = e.element.name
	if panel ~= nil and tools.get_child(panel, name) ~= nil then
		on_save(e)
	else
		panel = player.gui.left[sushi_panel_name]
		if panel ~= nil and tools.get_child(panel, name) ~= nil then
			sushilib.on_save_sushi(e)
		end
	end
end

tools.on_event(defines.events.on_gui_confirmed, on_gui_confirmed)

local function on_gui_elem_changed(e)
	local player = game.players[e.player_index]
	local name = e.element.name

	local panel = player.gui.left[device_panel_name]
	if not panel then return end

	local f_elem = tools.get_child(panel, name)
	if not f_elem then return end

	get_vars(player).changed = true

	local item = f_elem.elem_value
	if not item then return end

	local item_prefix = prefix .. "-request-"
	local index = string.sub(name, #item_prefix + 1)
	local count_name = prefix .. "-count-" .. index

	local f_count = tools.get_child(panel, count_name)
	local count = prototypes.item[item].stack_size
	f_count.text = tostring(count)
end

local function on_gui_text_changed(e)
	local player = game.players[e.player_index]
	local name = e.element.name

	local panel = player.gui.left[device_panel_name]
	if not panel then return end
	get_vars(player).changed = true
end

local function on_diag(e)

	local player = game.players[e.player_index]
	local device = get_vars(player).selected
	if not device or not device.valid then return end

	debug("----- DEVICE: position=" .. strip(device.position) .. ",direction=" .. device.direction)
	local entities = device.surface.find_entities_filtered { position = device.position, name = entities_to_destroy }
	for index, value in ipairs(entities) do
		debug("ENTITY[" .. index .. "]=" .. value.name)
		if value.type == "decider-combinator" then
			local cb = value.get_or_create_control_behavior()
			local circuit = cb.get_circuit_network(defines.wire_type.red, defines.circuit_connector_id.combinator_output)
			debug_signal("OUTPUT RED", circuit.signals)
			circuit = cb.get_circuit_network(defines.wire_type.green, defines.circuit_connector_id.combinator_output)
			debug_signal("OUTPUT GREEN", circuit.signals)
		elseif value.type == "inserter" then
			debug("  filter count=" .. value.prototype.filter_count)
		end
	end

	local cc2_list = device.surface.find_entities_filtered { position = device.position, name = prefix .. "-cc2" }
	if #cc2_list > 0 then
		local cc2 = cc2_list[1]
		local cb = cc2.get_or_create_control_behavior()
		for index, value in ipairs(cb.parameters) do
			if value.signal and value.signal.name then
				debug("REQUEST[" .. index .. "]" .. value.signal.name .. "=" .. value.count)
			end
		end
	end
end

tools.on_gui_click(prefix .. "_diag", on_diag)
tools.on_gui_click(prefix .. "_close_button", function(e) locallib.on_gui_closed(e) end)
tools.on_gui_click(prefix .. "_rebuild", function(e)
	local player = game.players[e.player_index]
	local device = get_vars(player).selected
	if not device or not device.valid then return end
	rebuild_network(device, player)
end)
tools.on_gui_click(prefix .. "_stop", function(e)
	local player = game.players[e.player_index]
	local device = get_vars(player).selected
	if not device or not device.valid then return end
	stop_network(device)
end)

local build_filter = tools.table_concat {
	{
		{ filter = 'name', name = device_name },
		{ filter = 'name', name = sushi_name },
		{ filter = 'name', name = commons.router_name },
	},
	tools.table_imap(locallib.container_types, function(v) return { filter = 'type', type = v } end),
	tools.table_imap(locallib.belt_types, function(v) return { filter = 'type', type = v } end)
}


script.on_event(defines.events.on_built_entity, on_player_built, build_filter)
script.on_event(defines.events.on_robot_built_entity, on_robot_built, build_filter)
script.on_event(defines.events.script_raised_built, on_script_built, build_filter)
script.on_event(defines.events.script_raised_revive, on_script_revive)

local mine_filter = tools.table_concat {

	{
		{ filter = 'name', name = device_name },
		{ filter = 'name', name = sushi_name },
		{ filter = 'name', name = commons.router_name }
	},
	tools.table_imap(locallib.container_types, function(v) return { filter = 'type', type = v } end)
}

script.on_event(defines.events.on_player_mined_entity, on_player_mined_entity, mine_filter)
script.on_event(defines.events.on_robot_mined_entity, on_mined, mine_filter)
script.on_event(defines.events.on_entity_died, on_mined, mine_filter)
script.on_event(defines.events.script_raised_destroy, on_mined, mine_filter)

tools.on_event(defines.events.on_gui_closed, on_auto_save)
tools.on_event(defines.events.on_gui_elem_changed, on_gui_elem_changed)
tools.on_event(defines.events.on_gui_text_changed, on_gui_text_changed)

script.on_nth_tick(NTICK_COUNT, process_monitored_object)


local function register_mapping(bp, mapping)
	local parameter_map = storage.parameters
	if not parameter_map or next(parameter_map) == nil then return end

	local linked_filters = {}
	for index = 1, bp.get_blueprint_entity_count() do
		local entity = mapping[index]
		if entity and entity.valid then
			if entity.name == device_name then
				local parameters = parameter_map[entity.unit_number]
				if parameters then
					bp.set_blueprint_entity_tags(index, {
						request_table = parameters.request_table and helpers.table_to_json(parameters.request_table),
						is_link_to_output_chest = parameters.is_link_to_output_chest,
						is_input_filtered = parameters.is_input_filtered,
						slow = parameters.slow,
						is_overflow = parameters.is_overflow,
						is_requested_disconnected = parameters.is_requested_disconnected
					})
				end
			elseif entity.name == sushi_name then
				local parameters = parameter_map[entity.unit_number]
				if parameters then
					bp.set_blueprint_entity_tags(index, {
						lane1_items = parameters.lane1_items and helpers.table_to_json(parameters.lane1_items),
						lane2_items = parameters.lane2_items and helpers.table_to_json(parameters.lane2_items),
						lane1_item_interval = parameters.lane1_item_interval,
						lane2_item_interval = parameters.lane2_item_interval,
						speed = parameters.speed,
						slow = parameters.slow
					})
				end
			elseif entity.name == commons.router_name then
				if not linked_filters[entity.link_id] then
					linked_filters[entity.link_id] = true
					local filters = routerlib.get_filters(entity.get_inventory(defines.inventory.chest))
					if next(filters) then
						bp.set_blueprint_entity_tags(index, {
							filters = helpers.table_to_json(filters)
						})
					end
				end
			elseif containerlib.is_linked(entity) then
				bp.set_blueprint_entity_tag(index, "is_belt_linked", true)
			end
		end
	end
end

tools.on_event(defines.events.on_player_setup_blueprint, function(e)
	local player = game.players[e.player_index]
	local mapping = e.mapping.get()
	if not player.is_cursor_empty() then
		local bp = player.cursor_stack
		if bp then register_mapping(bp, mapping) end
	else
		local bp = player.blueprint_to_setup
		if bp then register_mapping(bp, mapping) end
	end
end)

tools.on_event(defines.events.on_player_rotated_entity,
	function(e)
		if e.entity.name == device_name then
			e.entity.direction = e.previous_direction
		end
	end)


local function on_entity_cloned(ev)
	local source = ev.source
	local dest = ev.destination
	local src_id = source.unit_number
	local dst_id = dest.unit_number
	local source_name = source.name

	storage.structure_changed = true
	if source_name == device_name or source_name == sushi_name then
		debug("CLONE: source " .. source.name)

		local parameters = get_entity_parameters(source)
		local copy = {}
		for key, value in pairs(parameters) do
			copy[key] = value
		end

		storage.parameters[dst_id] = copy
		parameters = copy
		locallib.save_unit_number_in_circuit(dest)

		local entity = dest
		initialize_device(entity, parameters)
	else
		debug("CLONE: destroy " .. dest.name)
		dest.destroy()
	end
end

local clone_filter = tools.create_name_filter { { device_name, sushi_name }, entities_to_destroy }

script.on_event(defines.events.on_entity_cloned, on_entity_cloned, clone_filter)

local picker_dolly_blacklist = function()
	if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["add_blacklist_name"] then
		for _, name in pairs({ device_name, sushi_name }) do
			remote.call("PickerDollies", "add_blacklist_name", name)
		end
	end
end

local function on_init()
	picker_dolly_blacklist()
	storage.clusters = {}
end

local function on_load()
	picker_dolly_blacklist()
end

tools.on_init(on_init)
tools.on_load(on_load)

local function on_entity_settings_pasted(e)
	local src = e.source
	local dst = e.destination

	debug("copy src=" .. src.name .. " to " .. dst.name)
	if not src.valid or not dst.valid then return end

	if src.name == device_name and dst.name == device_name then
		local psrc = get_entity_parameters(src, true)
		local pdst = get_entity_parameters(dst, true)

		pdst.request_table = tools.table_copy(psrc.request_table)
		local cc2 = find_cc_request(dst)
		pdst.is_input_filtered = psrc.is_input_filtered
		pdst.is_overflow = psrc.is_overflow
		pdst.is_link_to_output_chest = psrc.is_link_to_output_chest
		pdst.is_requested_disconnected = psrc.is_requested_disconnected
		pdst.is_slow = psrc.is_slow
		if cc2 then
			install_requests(pdst.request_table, cc2)
			copy_request_to_filter(dst, pdst.request_table)
		end
		if not rebuild_network(dst) then
			locallib.add_monitored_device(dst)
		end
	elseif src.name == sushi_name and dst.name == sushi_name then
		sushilib.do_paste(src, dst, e)
	end
end

tools.on_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)

--------------------------------------------------------------

local function logistic_belt_repare()

	for _, surface in pairs(game.surfaces) do
		local loaders = surface.find_entities_filtered { name = device_loader_name }
		if loaders then
			for _, loader in ipairs(loaders) do
				local sushis = surface.find_entities_filtered { name = sushi_name, position = loader.position }
				if #sushis > 0 then
					local master = sushis[1]
					local loader_type = loader.loader_type

					loader.destroy()
					local new_loader = master.surface.create_entity {
						name = sushi_loader_name,
						position = master.position,
						force = master.force,
						direction = get_opposite_direction(master.direction),
						create_build_effect_smoke = false
					}
					new_loader.loader_type = loader_type
				end
			end
		end
	end
	if not storage.clusters then
		storage.clusters = {}
	end
end

commands.add_command("logistic_belt_repare", { "logistic_belt_repare_cmd" }, function(e) logistic_belt_repare() end)

commands.add_command("logistic_top_repare", { "logistic_top_repare" },
	function(e) game.players[e.player_index].gui.left.style.left_margin = 0 end)

local function logistic_belt_restart(f)

	for _, surface in pairs(game.surfaces) do
		local devices = surface.find_entities_filtered { name = device_name }
		if devices then
			for _, device in ipairs(devices) do
				if f then
					f(device)
				end
				locallib.add_monitored_device(device)
			end
		end
	end
end

local migrations_table = {

	["1.0.0"] = logistic_belt_repare,
	["1.0.2"] = function()


		local setting = settings.global[is_input_filtered_name]
		setting.value = true
		settings.global[is_input_filtered_name] = setting
		logistic_belt_restart(function(device)

			local parameters = get_entity_parameters(device)
			if parameters then
				parameters.is_input_filtered = true
			end
		end)
	end,
	["2.0.0"] = function() 
		update.update_all()
	end
}

local function on_configuration_changed(data)
	migration.on_config_changed(data, migrations_table)
end

script.on_configuration_changed(on_configuration_changed)

-----------------------------------------------

commands.add_command("logistic_belt_restart", { "logistic_belt_restart" }, function(e) logistic_belt_restart() end)

local function on_selected_entity_changed(e)
	local player = game.players[e.player_index]
	local selected = player.selected
	if selected and selected.valid and selected.name == device_name then
		inspectlib.show(player, selected)
	else
		inspectlib.clear(player)
	end
end

tools.on_event(defines.events.on_selected_entity_changed, on_selected_entity_changed)

commands.add_command("logistic_belt_trace", { "logistic_belt_trace" }, function(e)
	if tools.is_tracing() then
		tools.set_tracing(false)
		game.print("logistic belt: trace off")
	else
		tools.set_tracing(true)
		game.print("logistic belt: trace on")
	end
end)

-----------------------------------------------


local function add_filter(parameters, item)

	local request_table = parameters.request_table
	if not request_table then
		request_table = {}
		parameters.request_table = request_table
	end
	for _, r in pairs(request_table) do
		if r.item == item then return end
	end
	table.insert(request_table, { item = item, count = prototypes.item[item].stack_size })
end

local function on_shift_button1(e)
	local player = game.players[e.player_index]

	debug("click")
	local machine = player.entity_copy_source
	if machine and machine.type == "assembling-machine" then

		local selected = player.selected
		if not selected or not selected.valid then return end

		if selected.name ~= device_name then
			return
		end

		local parameters = get_entity_parameters(selected, true)
		local recipe = machine.get_recipe()
		if not recipe then return end

		for _, ingredient in pairs(recipe.ingredients) do
			if ingredient.type == "item" then
				add_filter(parameters, ingredient.name)
			end
		end
		copy_request_to_filter(selected, parameters.request_table)
		if not rebuild_network(selected) then
			locallib.add_monitored_device(selected)
		end
	end
end

script.on_event(commons.shift_button1_event, on_shift_button1)
