
local prefix = "logistic_belt"

data:extend(
    {
		{
			type = "bool-setting",
			name = prefix .. "-link_to_output_chest",
			setting_type = "runtime-global",
			default_value = true
		},
		{
			type = "bool-setting",
			name = prefix .. "-is_input_filtered",
			setting_type = "runtime-global",
			default_value = true
		},
		{
			type = "int-setting",
			name = prefix .. "-request_count",
			setting_type = "runtime-global",
			default_value = 20
		},
		{
			type = "int-setting",
			name = prefix .. "-item_count",
			setting_type = "runtime-global",
			default_value = 10
		},
		{
			type = "bool-setting",
			name = prefix .. "-add_filter",
			setting_type = "startup",
			default_value = true
		},
		{
			type = "int-setting",
			name = prefix .. "-router_inventory_size",
			setting_type = "startup",
			default_value = 50
		}

})


