local containerlib = {}

local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"

local prefix = commons.prefix

local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

local container_poles

function containerlib.connect_to_pole(device, container)

    local pole = container_poles[container.unit_number]
    if not pole or not pole.valid then return end
    device.connect_neighbour({ wire = defines.wire_type.red, target_entity = pole })
end

function containerlib.disconnect_from_pole(device, container)

    local pole = container_poles[container.unit_number]
    if not pole or not pole.valid then return end
    device.disconnect_neighbour({ wire = defines.wire_type.red, target_entity = pole })
end


function containerlib.create_connection(container, player)

    local pole = container_poles[container.unit_number]
    local surface = container.surface
    if not pole or not pole.valid then
        
        pole = surface.create_entity{name = commons.connector_name, position=container.position, force = container.force}
        container_poles[container.unit_number] = pole

        local decal = container.prototype.collision_box.right_bottom
        local id = rendering.draw_sprite {
            surface = surface,
            player = player,
            sprite = prefix .. "-chain",
            target = container,
            target_offset = { decal.x, decal.y },
            x_scale = 0.25,
            y_scale = 0.25
        }
        return true
    else
        local ids = rendering.get_all_ids(commons.prefix)
        local unit_number = container.unit_number
        for _, id in ipairs(ids) do
            local target = rendering.get_target(id)
            if target and target.entity and target.entity.unit_number == unit_number then
                rendering.destroy(id)
            end
        end
        container_poles[container.unit_number] = nil
        pole.destroy()
        return false
    end
end

function containerlib.on_mined(container) 

    local pole = container_poles[container.unit_number]
    if pole and pole.valid then
        container_poles[container.unit_number] = nil
        pole.destroy()
    end
end

tools.on_init(function() 

    storage.container_poles = {}
    container_poles = storage.container_poles
end)

tools.on_load(function() 
    container_poles = storage.container_poles
end)

tools.on_configuration_changed(function() 

    if not storage.container_poles then
        storage.container_poles = {}
    end
end)

tools.on_debug_init(function() 
    if not container_poles then
        container_poles = {}
        storage.container_poles = container_poles
    end
end)

local connection_button_name = prefix.."_link_connexion"

local function close_gui(player)
    local button = player.gui.left[connection_button_name]
    get_vars(player).selected_container = nil
    if button then
        button.destroy()
    end
end

local function on_gui_opened(e)
    local player = game.players[e.player_index]

    local container = e.entity
    if not container then 
        close_gui(player)
        return 
    end

    if not container or not container.valid then 
        close_gui(player)
        return
    end
    if container.type == "container" or container.type == "logistic-container" then
        if not player.gui.left[connection_button_name] then
            player.gui.left.add{type="button", name=connection_button_name}
        end
        get_vars(player).selected_container = container
        containerlib.set_button_label(container, player)
    else
        close_gui(player)
    end
end

local function on_gui_closed(e)
    local player = game.players[e.player_index]
    close_gui(player)
end

function containerlib.is_linked(container)
    return container_poles[container.unit_number]
end

function containerlib.set_button_label(container, player) 
    local button = player.gui.left[connection_button_name]

    local pole = container_poles[container.unit_number]
    if  pole and pole.valid then
        button.caption = { "message.disconnect_logistic_bels"}
    else
        button.caption = { "message.connect_logistic_bels"}
    end
end

tools.on_gui_click(connection_button_name, function(e) 
    local player = game.players[e.player_index]

    local container = get_vars(player).selected_container
    if container and container.valid then
        if containerlib.create_connection(container, player) then
            locallib.recompute_device(container)
        end
        containerlib.set_button_label(container, player)
    end
end
)

tools.on_event(defines.events.on_gui_opened, on_gui_opened) 
tools.on_event(defines.events.on_gui_closed, on_gui_closed) 
return containerlib

