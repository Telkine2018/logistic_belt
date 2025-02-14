local commons = require("scripts.commons")
local tools = require("scripts.tools")

local png = commons.png
local prefix = commons.prefix
local debug_mode = commons.debug_mode

local empty_sheet = {
  filename = png('invisible'),
  priority = "very-low",
  width = 1,
  height = 1,
  frame_count = 1,
  y = 0
}

local connector_definitions = circuit_connector_definitions.create_vector(
  universal_connector_template,
  {
    { variation = 24, main_offset = util.by_pixel(-17, 0), shadow_offset = util.by_pixel(10, -0.5), show_shadow = false },
    { variation = 24, main_offset = util.by_pixel(-14, 0), shadow_offset = util.by_pixel(5, -5),    show_shadow = false },
    { variation = 24, main_offset = util.by_pixel(-17, 0), shadow_offset = util.by_pixel(-2.5, 6),  show_shadow = false },
    { variation = 31, main_offset = util.by_pixel(14, 0),  shadow_offset = util.by_pixel(5, -5),    show_shadow = false },
  }
)

local function create_inserters()
  local name = prefix .. "-device"

  local base_entity = data.raw["underground-belt"]["express-underground-belt"]
  -- local rounded_items_per_second = math.floor(base_entity.speed * 480 * 100 + 0.5) / 100


  local device_inserter = {
    type = "inserter",
    name = name,

    -- this name and icon appear in the power usage UI
    icons = {
      {
        icon = "__logistic_belt__/graphics/item/device.png",
        icon_size = 64,
      }
    },
    minable = { mining_time = 0.1, result = prefix .. "-device" },
    collision_box = { { -0.2, -0.2 }, { 0.2, 0.2 } },
    collision_mask = { layers = { ["floor"] = true, ["object"] = true, ["water_tile"] = true } },
    selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
    selection_priority = 50,
    allow_custom_vectors = true,
    energy_per_movement = ".0000001J",
    energy_per_rotation = ".0000001J",
    energy_source = {
      type = "void",
    },
    extension_speed = 1,
    rotation_speed = 0.5,
    pickup_position = { 0.0, 0 },
    insert_position = { 0.0, 0 },
    draw_held_item = false,
    draw_inserter_arrow = false,
    chases_belt_items = false,
    platform_picture = {

      sheets = {
        -- Base
        {
          filename = png("entity/hr-device"),
          height   = 192,
          priority = "extra-high",
          scale    = 0.5,
          width    = 192,
          y        = 192
        },
        -- Shadow
        {
          filename       = png("entity/hr-device-shadow"),
          height         = 192,
          priority       = "extra-high",
          scale          = 0.5,
          width          = 192,
          y              = 192,
          draw_as_shadow = true,
        }
      }
    },
    hand_base_picture = empty_sheet,
    hand_open_picture = empty_sheet,
    hand_closed_picture = empty_sheet,
    circuit_wire_connection_points = connector_definitions.points,
    circuit_connector_sprites = connector_definitions.sprites,
    circuit_wire_max_distance = 10000
  }


  for _, k in ipairs { "flags", "max_health", "resistances", "vehicle_impact_sound" } do
    device_inserter[k] = base_entity[k]
  end
  device_inserter.filter_count = 5

  local sushi_inserter = table.deepcopy(device_inserter)
  sushi_inserter.name = prefix .. "-sushi"
  sushi_inserter.minable = { mining_time = 0.1, result = prefix .. "-sushi" }
  sushi_inserter.platform_picture.sheets[1].filename = png("entity/hr-sushi")
  sushi_inserter.platform_picture.sheets[2].filename = png("entity/hr-sushi-shadow")


  local copy_inserter = table.deepcopy(device_inserter)
  copy_inserter.filter_count = 0
  copy_inserter.draw_circuit_wires = debug_mode
  copy_inserter.name = prefix .. "-inserter"
  copy_inserter.minable = { mining_time = 0.1 }
  --copy_inserter.collision_box = nil
  table.insert(copy_inserter.flags, "not-rotatable")
  if not debug_mode then
    copy_inserter.selection_box = nil
    table.insert(copy_inserter.flags, "hide-alt-info")
    table.insert(copy_inserter.flags, "not-on-map")
  end
  table.insert(copy_inserter.flags, "not-blueprintable")
  table.insert(copy_inserter.flags, "not-deconstructable")
  table.insert(copy_inserter.flags, "not-upgradable")

  local filter_inserter = table.deepcopy(copy_inserter)
  filter_inserter.name = prefix .. "-inserter-filter"
  filter_inserter.filter_count = 5

  local slow_inserter = table.deepcopy(filter_inserter)
  slow_inserter.name = prefix .. "-inserter-filter-slow"
  slow_inserter.extension_speed = 0.3
  slow_inserter.rotation_speed = 0.14

  data:extend { device_inserter, copy_inserter, filter_inserter, slow_inserter, sushi_inserter }
end

local function create_loaders()
  local device_loader_name = prefix .. "-loader"

  local device_loader = table.deepcopy(data.raw["underground-belt"]["express-underground-belt"])
  device_loader.type = "loader-1x1"
  device_loader.name = device_loader_name
  device_loader.icons = nil
  device_loader.flags = { "player-creation" }
  device_loader.localised_name = { "entity-name." .. device_loader_name }
  device_loader.minable = nil
  device_loader.collision_box = { { -0.3, -0.3 }, { 0.3, 0.3 } }
  device_loader.collision_mask = { layers = { ["transport_belt"] = true } }
  device_loader.selection_box = { { 0, 0 }, { 0, 0 } }
  device_loader.filter_count = 0
  device_loader.fast_replaceable_group = nil
  --entity.belt_animation_set = nil
  device_loader.structure = {
    direction_in = {
      sheets = {
        {
          filename = png("entity/hr-device"),
          height   = 192,
          scale    = 0.5,
          width    = 192,
          y        = 192
        },
        -- Shadow
        {
          filename       = png("entity/hr-device-shadow"),
          height         = 192,
          scale          = 0.5,
          width          = 192,
          y              = 192,
          draw_as_shadow = true,
        }
      }
    },
    direction_out = {
      sheets = {
        {
          filename = png("entity/hr-device"),
          height   = 192,
          scale    = 0.5,
          width    = 192,
          y        = 192
        },
        -- Shadow
        {
          filename       = png("entity/hr-device-shadow"),
          height         = 192,
          scale          = 0.5,
          width          = 192,
          y              = 192,
          draw_as_shadow = true,
        }
      }
    },
    back_patch = {
      sheet = empty_sheet },
    front_patch = {
      sheet = empty_sheet }
  }

  device_loader.belt_animation_set = {
    animation_set = {
      filename = png('invisible'),
      priority = "very-low",
      width = 1,
      height = 1,
      frame_count = 1,
      direction_count = 32
    }
  }

  device_loader.speed = 1
  device_loader.container_distance = 0
  device_loader.belt_length = 0.6
  device_loader.next_upgrade = nil

  local sushi_loader_name = prefix .. "-loader-sushi"
  local sushi_loader = table.deepcopy(device_loader)
  sushi_loader.name = sushi_loader_name
  sushi_loader.structure.direction_in.sheets[1].filename = png("entity/hr-sushi")
  sushi_loader.structure.direction_in.sheets[2].filename = png("entity/hr-sushi-shadow")
  sushi_loader.structure.direction_out.sheets[1].filename = png("entity/hr-sushi")
  sushi_loader.structure.direction_out.sheets[2].filename = png("entity/hr-sushi-shadow")

  data:extend {
    device_loader, sushi_loader
  }
end

create_inserters()
create_loaders()

-- log(serpent.block(data.raw["inserter"]["inserter"]))
