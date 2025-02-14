local routerlib = {}

local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"

local prefix = commons.prefix

local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

local changed_clusters = {}

local function get_key(position)

    return tostring(math.floor(position.x)) .. "/" .. math.floor(position.y)
end

local disp = {
    { direction = defines.direction.east, x = 1, y = 0 },
    { direction = defines.direction.west, x = -1, y = 0 },
    { direction = defines.direction.south, x = 0, y = 1 },
    { direction = defines.direction.north, x = 0, y = -1 }
}

function routerlib.compute_cluster(start_router, exception)

    local position = start_router.position
    local map = {}
    local to_process = {}
    local surface = start_router.surface
    local force = start_router.force

    local router_list = {}
    local devices = {}

    to_process[start_router.unit_number] = start_router
    map[get_key(start_router.position)] = true

    while (true) do

        local _, router = next(to_process)
        if not router then break end

        to_process[router.unit_number] = nil
        table.insert(router_list, router)

        local position = router.position
        for _, d in ipairs(disp) do

            local test_pos = { x = position.x + d.x, y = position.y + d.y }
            local key = get_key(test_pos)
            if not map[key] then

                map[key] = true
                local routers = surface.find_entities_filtered { name = commons.router_name, position = test_pos,
                    force = force }
                if #routers > 0 then
                    local found = routers[1]
                    if not exception or exception.unit_number ~= found.unit_number then
                        to_process[found.unit_number] = found
                    end
                else
                    local found_devices = surface.find_entities_filtered { name = commons.device_name,
                        position = test_pos,
                        force = force }
                    if #found_devices > 0 then
                        local device = found_devices[1]
                        if device.direction == d.direction or device.direction == tools.opposite_directions[d.direction] then
                            devices[device.unit_number] = device
                        else
                            map[key] = false
                        end
                    end
                end
            end
        end
    end
    return router_list, devices
end

function routerlib.remove_from_cluster(router)
    local link_id = router.link_id
    local cluster = storage.clusters[link_id]
    if cluster then
        cluster.routers[router.unit_number] = nil
        changed_clusters[link_id] = cluster
        if next(cluster.routers) == nil then
            -- remove cluster
            storage.clusters[link_id] = nil
            return true
        end
    end
    return false
end

function routerlib.get_or_create_cluster(link_id)
    local cluster = storage.clusters[link_id]
    if cluster then return cluster end
    cluster = { routers = {} }
    storage.clusters[link_id] = cluster
    cluster.link_id = link_id
    changed_clusters[link_id] = cluster
    return cluster
end

local EMPTY_FILTERS = {}

function routerlib.get_filters(inv)

    if inv.get_filter(1) == nil then
        return EMPTY_FILTERS
    end
    local filters = {}
    for i = 1, #inv do
        local item = inv.get_filter(i)
        if item then
            local count = filters[item]
            if count then
                filters[item] = count + 1
            else
                filters[item] = 1
            end
        else
            return filters
        end
    end
    return filters
end

function routerlib.merge_filters(merge_filters, inv)

    local filters = routerlib.get_filters(inv)
    for item, count in pairs(filters) do
        local org_count = merge_filters[item]
        if org_count then
            merge_filters[item] = math.max(count, org_count)
        else
            merge_filters[item] = count
        end
    end
end

function routerlib.apply_filters(inv, filters)

    local index = 1
    local size = #inv
    for item, count in pairs(filters) do

        for i = 1, count do 
            if index > size then goto end_loop end
            inv.set_filter(index, item)
            index = index + 1
        end
    end
    ::end_loop::
    return index
end

function routerlib.set_routers_in_cluster(entity, routers, link_id, filters)

    local base_inv = nil
    local done = {}
    local cluster = routerlib.get_or_create_cluster(link_id)
    local merge_filters = {}
    if filters then 
        merge_filters = filters
    end

    for _, router in pairs(routers) do
        local org_link_id = router.link_id
        if org_link_id ~= link_id then

            routerlib.remove_from_cluster(router)
            cluster.routers[router.unit_number] = router
            changed_clusters[link_id] = cluster
            if org_link_id ~= 0 then
                if not done[org_link_id] then
                    local inv = router.get_inventory(defines.inventory.chest)
                    local contents = inv.get_contents()
                    routerlib.merge_filters(merge_filters, inv)
                    if base_inv == nil then
                        router.link_id = link_id
                        base_inv = router.get_inventory(defines.inventory.chest)
                        routerlib.merge_filters(merge_filters, base_inv)
                        base_inv.set_bar()
                        for i = 1, #inv do
                            base_inv.set_filter(i, nil);
                        end
                    end
                    for name, count in pairs(contents) do
                        base_inv.insert({ name = name, count = count })
                    end
                    done[org_link_id] = true

                    inv = router.force.get_linked_inventory(router.name, org_link_id)
                    inv.clear()
                end
            end
            router.link_id = link_id
        end
    end

    if next(merge_filters) then
        
        if not base_inv then
            base_inv = entity.force.get_linked_inventory(entity.name, link_id)
            routerlib.merge_filters(merge_filters, base_inv)
            base_inv.set_bar()
        end

        local contents = base_inv.get_contents()
        base_inv.clear()

        local index = routerlib.apply_filters(base_inv, merge_filters)
        for name, count in pairs(contents) do
            base_inv.insert({ name = name, count = count })
        end
        if index < #base_inv then
            base_inv.set_bar(index)
        end
    end
    return cluster
end

function routerlib.get_pole_from_cluster(cluster)

    if cluster.link_pole and cluster.link_pole.valid then
        return cluster.link_pole
    end

    return nil
end

function routerlib.get_or_create_pole_from_cluster(cluster)

    if cluster.link_pole and cluster.link_pole.valid then
        return cluster.link_pole
    end
    local _, first_router = next(cluster.routers)
    if not first_router then return nil end

    cluster.link_pole = first_router.surface.create_entity { name = commons.connector_name,
        position = first_router.position,
        force = first_router.force }

    first_router.connect_neighbour({ wire = defines.wire_type.green, target_entity = cluster.link_pole })
    return cluster.link_pole
end

function routerlib.delete_pole(cluster)
    if cluster.link_pole then
        if cluster.link_pole.valid then
            cluster.link_pole.destroy()
        end
        cluster.link_pole = nil
    end
end

function routerlib.reconnect_changes()

    for link_id, cluster in pairs(changed_clusters) do

        routerlib.delete_pole(cluster)
        if cluster.devices then

            local pole = routerlib.get_or_create_pole_from_cluster(cluster)
            if pole then
                for _, device in pairs(cluster.devices) do
                    locallib.add_monitored_device(device)
                end
            end
        end
    end
    changed_clusters = {}
end

function routerlib.connect_device(router, device)

    local cluster = storage.clusters[router.link_id]
    if not cluster then return end

    local pole = routerlib.get_or_create_pole_from_cluster(cluster)
    if not pole then return end

    local result = device.connect_neighbour({
        wire = defines.wire_type.red,
        target_entity = pole
    })
    if not result then
        debug("cannot connect pole to device: " .. strip(device.position))
    end
end

function routerlib.disconnect_device(router, device)

    local cluster = storage.clusters[router.link_id]
    if not cluster then return end

    local pole = routerlib.get_pole_from_cluster(cluster)
    if not pole then return end

    local result = device.disconnect_neighbour({
        wire = defines.wire_type.red,
        target_entity = pole
    })
    debug("disconnect:" .. tostring(result))
end

function routerlib.on_build(entity, e)
    local player = e.player_index and game.players[e.player_index]

    entity.link_id = 0

    local tags = e.tags
    local filters 
    if tags then
        if tags.filters then
            filters = helpers.json_to_table(tags.filters)
        end
    end

    changed_clusters = {}
    local routers, devices, min_router = routerlib.compute_cluster(entity)
    if #routers == 1 then
        local link_id = tools.get_id()
        local cluster = routerlib.get_or_create_cluster(link_id)

        entity.link_id = link_id
        cluster.routers[entity.unit_number] = entity
        cluster.devices = devices
        cluster.min_router = min_router
        changed_clusters[link_id] = cluster
        if filters then
            local inv = entity.get_inventory(defines.inventory.chest)
            local index = routerlib.apply_filters(inv, filters)
            inv.set_bar(index)
        end
    else
        local cluster = routerlib.set_routers_in_cluster(entity, routers, routers[2].link_id, filters)
        cluster.devices = devices
        cluster.min_router = min_router
    end
    routerlib.reconnect_changes()
end

function routerlib.on_mined(ev)

    local entity = ev.entity
    local position = entity.position
    local surface = entity.surface
    local force = entity.force
    local processed = {}
    local current_id = entity.link_id
    changed_clusters = {}

    if routerlib.remove_from_cluster(entity) then

        local inv = entity.get_inventory(defines.inventory.chest)
        local contents = inv.get_contents()

        if ev.player_index then
            local player = game.players[ev.player_index]
            local player_inv = player.get_main_inventory()
            if player_inv then
                for name, count in pairs(contents) do
                    local count1 = player_inv.insert { name = name, count = count }
                    if count1 < count then
                        entity.surface.spill_item_stack(entity.position, { name = name, count = count1 }, true,
                            entity.force)
                    end
                end
            end
        else
            for name, count in pairs(contents) do
                entity.surface.spill_item_stack(entity.position, { name = name, count = count }, true, entity.force)
            end
        end
        return
    end

    for _, d in ipairs(disp) do

        local test_pos = { x = position.x + d.x, y = position.y + d.y }
        local key = get_key(test_pos)

        local routers = surface.find_entities_filtered { name = commons.router_name, position = test_pos,
            force = force }
        if #routers > 0 then
            local root = routers[1]

            if not processed[root.unit_number] then
                local router_list, devices = routerlib.compute_cluster(root, entity)

                for _, r in pairs(router_list) do
                    processed[r.unit_number] = r
                end
                if not current_id then
                    current_id = tools.get_id()
                end
                local cluster = routerlib.set_routers_in_cluster(root, router_list, current_id)
                changed_clusters[current_id] = cluster
                cluster.devices = devices
                current_id = nil
            end
        end
    end

    routerlib.reconnect_changes()
end

function routerlib.get_or_create_pole_from_router(router)

    local link_id = router.link_id
    local cluster = storage.clusters[link_id]
    if not cluster then return nil end

    local pole = routerlib.get_or_create_pole_from_cluster(cluster)
    return pole
end

function routerlib.connect_to_output_chest(router, combinator)

    local link_id = router.link_id
    local cluster = storage.clusters[link_id]
    if not cluster then return end

    local pole = routerlib.get_or_create_pole_from_cluster(cluster)
    if not pole then return end

    local result = pole.connect_neighbour({
        wire = defines.wire_type.green,
        target_entity = combinator
    })
    if not result then
        debug("cannot connect output device to pole")
    end
end

if not storage.clusters then
    storage.clusters = {}
end


return routerlib
