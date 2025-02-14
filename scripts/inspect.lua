

local commons = require("scripts.commons")
local tools = require("scripts.tools")

local inspectlib = {}

local prefix = commons.prefix
local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

local inspect_name = prefix .. "_inspector"


function inspectlib.show(player, entity)
    local signals =  nil
    if not entity.valid then
        return
    end
    local cb = entity.get_control_behavior()
    if cb then
        local circuit = cb.get_circuit_network(defines.wire_type.red)
        if circuit then
            signals = circuit.signals
        end
    end

    tools.get_vars(player).inspectlib_selected = entity
    if not signals or #signals == 0 then
        inspectlib.close(player)
        return
    end
    
    local frame = player.gui.left[inspect_name]
    local signal_table
    if not frame then
        frame = player.gui.left.add{type="frame", name=inspect_name, direction="vertical"}
        signal_table = frame.add{type="table", column_count=5, name="signal_table" }
    else
        signal_table = frame.signal_table
        signal_table.clear()
    end

    if not signals then return end

    table.sort(signals, function(a,b) return a.count > b.count end)

    for _, signal in pairs(signals) do
        local s = signal.signal
        local sprite = (s.type == "virtual" and "virtual-signal" or s.type) .. "/" .. s.name
        signal_table.add{type="sprite-button", sprite=sprite, number= signal.count}
    end

end

function inspectlib.clear(player) 
    tools.get_vars(player).inspectlib_selected = nil
    inspectlib.close(player)
end

function inspectlib.close(player) 
    local frame = player.gui.left[inspect_name]
    if frame then
        frame.destroy()
    end
end

function inspectlib.refresh() 
    for _,player in pairs(game.players) do
        local entity = tools.get_vars(player).inspectlib_selected
        if entity then
            inspectlib.show(player, entity)
        end
    end
end

script.on_nth_tick(20, inspectlib.refresh)

return inspectlib