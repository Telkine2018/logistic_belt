local routerlib = {}

local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"

local prefix = commons.prefix

local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

local prefix2 = "logistic_belt2"
local new_router_name = prefix2 .. "-router"
local new_device_name = prefix2 .. "-device"
local new_sushi_name = prefix2 .. "-sushi"
local new_overflow_name = prefix2 .. "-overflow"

---@class UpdateConnections
---@field wire_connector_id  defines.wire_connector_id
---@field target_id integer
---@field target_connector_id defines.wire_connector_id
---@field target_entity LuaEntity

---@class UpdateRouter
---@field position MapPosition
---@field contents ItemWithQualityCounts[]
---@field connectors CircuitConnectionDefinition[]
---@field connections UpdateConnections[]
---@field oldid integer
---@field new_router LuaEntity
---@field filters table<integer, string>
---@field bar integer

---@class UpdateDeviceRequest
---@field item string
---@field count integer

---@class UpdateDeviceParameters
---@field is_overflow boolean
---@field request_table UpdateDeviceRequest[]

---@class UpdateDevice
---@field position MapPosition
---@field orientation number
---@field parameters UpdateDeviceParameters

---@class UpdateSushi
---@field position MapPosition
---@field orientation number
---@field parameters table

---@class CircuitConnectionDefinition
---@field target_entity_id integer

local migration = {}

---@param force LuaForce
---@param surface LuaSurface
function migration.process_force(force, surface)
    do
        local routers = surface.find_entities_filtered { name = commons.router_name, force = force }
        ---@type table<integer, UpdateRouter>
        local router_map = {}

        for _, router in pairs(routers) do
            local inv = router.get_inventory(defines.inventory.chest)
            ---@cast inv -nil
            local contents = inv.get_contents()
            inv.clear()
            local connectors = router.get_wire_connectors(false)
            ---@type UpdateRouter
            local update = {
                position = router.position,
                contents = contents,
                oldid = router.unit_number
            }
            if connectors then
                update.connections = {}

                ---@type table<int, LuaWireConnector>
                local connectors = update.connectors
                if connectors then
                    for _, connector in pairs(connectors) do
                        for _, connection in pairs(connector.real_connections) do
                            table.insert(update.connections, {
                                wire_connector_id   = connector.wire_connector_id,
                                target_id           = connection.target.owner.unit_number,
                                target_connector_id = connection.target.wire_connector_id,
                                target_entity       = connection.target
                            })
                        end
                    end
                end
            end

            local filters = {}
            for i = 1, #inv do
                local item = inv.get_filter(i)
                if item then
                    filters[i] = item
                end
            end
            update.filters = filters
            update.bar = inv.get_bar()

            router_map[router.unit_number] = update
            router.destroy()
        end

        for _, update in pairs(router_map) do
            local new_router = surface.create_entity {
                name = new_router_name,
                position = update.position,
                force = force,
                raise_built = true }

            update.new_router = new_router
            if new_router then
                local inv = new_router.get_inventory(defines.inventory.chest)
                if inv then
                    for index, item in pairs(update.filters) do
                        if index <= #inv then
                            inv.set_filter(index, item)
                        end
                    end
                    local bar = update.bar
                    if bar then
                        if bar >= #inv + 1 then
                            bar = #inv + 1
                        end
                        inv.set_bar(bar)
                    end
                end
            end
        end
        for _, update in pairs(router_map) do
            if update.new_router then
                local inv = update.new_router.get_inventory(defines.inventory.chest)
                if inv then
                    if update.contents then
                        for _, item in pairs(update.contents) do
                            inv.insert { name = item.name, count = item.count }
                        end
                    end
                end
                if update.connections then
                    for _, connection in pairs(update.connections) do
                        local target = connection.target_entity
                        if not target.valid then
                            target = router_map[connection.target_entity_id].new_router
                        end
                        if target and target.valid then
                            update.new_router.get_wire_connector(connection.wire_connector_id, true).
                                connect_to(target.get_wire_connector(connection.target_connector_id, true))
                        end
                    end
                end
            end
        end
    end

    do
        ---@class table<integer, UpdateDevice>
        local device_map = {}
        local devices = surface.find_entities_filtered { name = commons.device_name, force = force }

        for _, device in pairs(devices) do
            ---@type UpdateDevice
            local update_device = {
                position = device.position,
                direction = tools.get_opposite_direction(device.direction),
                parameters = locallib.get_parameters(device, false)
            }
            device_map[device.unit_number] = update_device
            device.destroy { raise_destroy = true }
        end

        for _, update in pairs(device_map) do
            if not update.parameters or not update.parameters.is_overflow then
                local new_device = surface.create_entity {
                    name = new_device_name,
                    position = update.position,
                    force = force,
                    raise_built = true,
                    direction = update.direction
                }
                remote.call("logistic_belt2_update", "update_device", new_device, update.parameters)
            else
                local new_device = surface.create_entity {
                    name = new_overflow_name,
                    position = update.position,
                    force = force,
                    raise_built = true,
                    direction = update.direction
                }
                remote.call("logistic_belt2_update", "update_overflow", new_device, update.parameters)
            end
        end
    end

    do
        ---@class table<integer, UpdateSushi>
        local sushi_map = {}
        local sushis = surface.find_entities_filtered { name = commons.sushi_name, force = force }

        for _, sushi in pairs(sushis) do
            ---@type UpdateSushi
            local update_device = {
                position = sushi.position,
                direction = tools.get_opposite_direction(sushi.direction),
                parameters = locallib.get_parameters(sushi, false)
            }
            sushi_map[sushi.unit_number] = update_device
            sushi.destroy { raise_destroy = true }
        end

        for _, update in pairs(sushi_map) do
            local new_sushi = surface.create_entity {
                name = new_sushi_name,
                position = update.position,
                force = force,
                raise_built = true,
                direction = update.direction
            }
            if update.parameters then
                remote.call("logistic_belt2_update", "update_sushi", new_sushi, update.parameters)
            end
        end
    end

    do
        local objs = rendering.get_all_objects(commons.prefix)
        storage.container_poles = {}
        for _, obj in ipairs(objs) do
            obj.destroy()
        end
    end
end

function migration.update_all()
    for _, force in pairs(game.forces) do
        for _, surface in pairs(game.surfaces) do
            migration.process_force(force, surface)
        end
    end
end

return migration
