
local commons = {}

commons.prefix = "logistic_belt"

local prefix = commons.prefix

local function png(name) return ('__logistic_belt__/graphics/%s.png'):format(name) end

commons.debug_mode = false
commons.png = png
commons.item1 = "item1"

commons.device_name = prefix .. "-device"
commons.inserter_name = prefix .. "-inserter"
commons.filter_name = prefix .. "-inserter-filter"
commons.device_loader_name = prefix .. "-loader"
commons.slow_filter_name = prefix .. "-inserter-filter-slow"

commons.sushi_loader_name = prefix .. "-loader-sushi"
commons.sushi_name = prefix .. "-sushi"

commons.chest_name = prefix .. "-chest"
commons.router_name = prefix .. "-router"
commons.background_router_name = prefix .. "-background_router"
commons.pole_name = prefix .. "-pole"

commons.debug_mode = false
commons.trace_inserter = false

commons.device_panel_name = prefix .. "_device_frame"
commons.sushi_panel_name = prefix .. "_sushi_frame"

commons.connector_name = prefix .. "_connector"

commons.entities_to_clear = {
	commons.inserter_name,
	commons.filter_name,
	commons.slow_filter_name,
	prefix .. "-cc",
	prefix .. "-dc",
	prefix .. "-ac",
	prefix .. "-cc2"
}

commons.shift_button1_event = prefix .. "-shift-button1"

return commons

