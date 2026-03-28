--[[
Title: Ration Pack
Author: Wobin
Date: 18/03/2026
Repository: https://github.com/Wobin/RationPack
Version: 7.0
]] --

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local mod = get_mod("Ration Pack")
mod.version = "7.0"

-- ============================================================================
-- IMPORTS
-- ============================================================================

local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local Pickups = require("scripts/settings/pickup/pickups")
local BuffSettings = require("scripts/settings/buff/buff_settings")
local medical_crate_config = require("scripts/settings/deployables/templates/medical_crate")

-- ============================================================================
-- LOCAL REFERENCE
-- ============================================================================

local Color = Color
local Unit = Unit
local Managers = Managers
local GameSession = GameSession
local ScriptUnit = ScriptUnit
local World = World
local Quaternion = Quaternion
local Vector3 = Vector3
local CLASS = CLASS
local math = math

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Asset paths
local DECAL_UNIT_NAME = "content/levels/training_grounds/fx/decal_aoe_indicator"
local PACKAGE_NAME = "content/levels/training_grounds/missions/mission_tg_basic_combat_01"

-- Visual constants
local DECAL_Z_OFFSET = 0.1
local DECAL_BASE_DIAMETER_OFFSET = 1.5
local COLOR_ALPHA = 0.5
local COLOR_MULTIPLIER = 0.05
local UPDATE_THROTTLE_INTERVAL = 0.5

-- Color definitions
local FIELD_IMPROVEMENT_COLOR = { r = 11 / 255, g = 105 / 255, b = 116 / 255 }
local DEFAULT_DECAL_COLOR = { r = 0, g = 1, b = 0 }

-- ============================================================================
-- UI CONFIGURATION
-- ============================================================================

-- Charge state colors
local CHARGE_COLOR = {
  [4] = Color.teal(255, true),
  [3] = Color.yellow(255, true),
  [2] = Color.orange(255, true),
  [1] = Color.red(255, true)
}

-- Font colors for charge display
local FONT_CONTRAST = {
  [4] = Color.terminal_text_header(255, true),
  [3] = Color.terminal_text_body_dark(255, true),
  [2] = Color.terminal_text_body_dark(255, true),
  [1] = Color.terminal_text_header(255, true)
}

-- X-axis offset for charge numbers
local CHARGE_XOFFSET = { [4] = 2, [3] = 0, [2] = 0, [1] = 0 }

-- Text pass definition for widget rendering
local TEXT_PASS = {
  style_id = 'remaining_count',
  pass_type = 'text',
  value_id = 'remaining_count',
  visibility_function = function(content)
    return content and content.remaining_count ~= nil and content.remaining_count ~= "-"
  end
}

-- Text style configuration
local TEXT_STYLE = {
  offset               = { -10, 9, 4 },
  size                 = { 64, 64 },
  vertical_alignment   = "center",
  horizontal_alignment = "left"
}
table.merge(TEXT_STYLE, table.clone(UIFontSettings.header_2))

-- ============================================================================
-- STATE & CACHES
-- ============================================================================

-- Persistent storage
local decals = mod:persistent_table("medical_crate_decals")
local range_decals = mod:persistent_table("medical_crate_range_decals")
local has_checked_package = mod:persistent_table("texture_check", { false })

-- Runtime state
local NumericUI = nil
local charge_lookup = {}
local healthstations = {}
local interactee = {}

-- Caches for performance
local ammo_crate_cache = {}
local field_improvisation_cache = { value = false, last_check = 0 }
local FIELD_IMPROVISATION_CHECK_INTERVAL = 10

-- ============================================================================
-- VALIDATION FUNCTIONS
-- ============================================================================

local function is_valid_unit(unit)
  return unit and type(unit) == "userdata" and Unit and Unit.alive(unit)
end

local function is_valid_charge_count(charges)
  return type(charges) == "number" and charges >= 1 and charges <= 4
end

local function is_valid_marker(marker)
  return marker and marker.unit and marker.widget and is_valid_unit(marker.unit)
end

-- ============================================================================
-- AMMO CRATE FUNCTIONS
-- ============================================================================

local function is_ammo_crate(target)
  if not is_valid_unit(target) then
    return false
  end

  -- Return cached result if available
  if ammo_crate_cache[target] ~= nil then
    return ammo_crate_cache[target]
  end

  local result = false

  -- Check direct pickup_type data (only deployed ammo crates)
  if Unit.has_data(target, "pickup_type") then
    local pickup_type = Unit.get_data(target, "pickup_type")
    if pickup_type and pickup_type == "ammo_cache_deployable" then
      result = true
    end
  end

  -- Check unit template name (only deployed ammo crates, not pocketables)
  if not result and Unit.has_data(target, "unit_template_name") then
    local template_name = Unit.get_data(target, "unit_template_name")
    if template_name and template_name == "ammo_cache_deployable" then
      result = true
    end
  end

  ammo_crate_cache[target] = result
  return result
end

-- ============================================================================
-- CHARGE RETRIEVAL & WIDGET FUNCTIONS
-- ============================================================================

local function get_charges(marker)
  local unit = marker and marker.unit
  if not is_valid_unit(unit) then
    return nil
  end

  -- Check healthstation cache first
  local healthstation = healthstations[unit]
  if healthstation and type(healthstation._charge_amount) == "number" then
    return healthstation._charge_amount
  end

  -- Fetch game_object_id
  local unit_spawner = Managers and Managers.state and Managers.state.unit_spawner
  local game_object_id = unit_spawner and unit_spawner:game_object_id(unit)
  if not game_object_id then
    return nil
  end

  -- Get charges from game session
  local game_session = Managers.state.game_session and Managers.state.game_session:game_session()
  if not game_session then
    return nil
  end

  local charges = GameSession.game_object_field(game_session, game_object_id, "charges")
  return type(charges) == "number" and charges or nil
end

local function get_marker(self, unit)
  for _, marker in ipairs(self._markers) do
    if marker.unit == unit then return marker end
  end
end

local function text_change(marker, model)
  if not marker or not marker.unit or not marker.widget or not marker.widget.content or not marker.widget.style
    or not marker.widget.style.remaining_count or not marker.widget.style.remaining_count.offset then
    return
  end

  if healthstations[marker.unit] or not mod:get("show_numbers") then return end

  local remaining_charges = get_charges(marker)
  if not is_valid_charge_count(remaining_charges) then return end

  marker.widget.content.remaining_count = remaining_charges

  -- Update styling
  local scale = marker.scale
  local default_font_size = TEXT_STYLE.font_size
  local default_offset = TEXT_STYLE.offset
  local offset = marker.widget.style.remaining_count.offset
  local charge_xoffset = CHARGE_XOFFSET[remaining_charges] or 0

  -- Font size scaling
  marker.widget.style.remaining_count.font_size = marker.is_clamped
    and default_font_size
    or math.max(default_font_size * scale, 8)

  -- Offset scaling
  if marker.is_clamped then
    offset[1] = default_offset[1] - charge_xoffset
    offset[2] = default_offset[2]
  else
    offset[1] = default_offset[1] * scale - charge_xoffset
    offset[2] = default_offset[2] * scale
  end

  if mod:get("show_colours") then
    marker.widget.style.remaining_count.text_color = FONT_CONTRAST[remaining_charges]
  end

  marker.widget.dirty = true
end

local function check_background_colour(marker)
  local charge = charge_lookup[marker.unit] or 0
  local remaining_charges = get_charges(marker)
  if remaining_charges and remaining_charges ~= charge then
    charge_lookup[marker.unit] = remaining_charges
    if mod:get("show_colours") then
      marker.widget.style.background.color = CHARGE_COLOR[remaining_charges]
    end
  end
end

-- ============================================================================
-- BUFF DETECTION FUNCTIONS
-- ============================================================================

local function has_field_improvisation(t)
  -- Use cached value if fresh enough
  if t and t - field_improvisation_cache.last_check < FIELD_IMPROVISATION_CHECK_INTERVAL then
    return field_improvisation_cache.value
  end

  
  if not Managers or not Managers.state or not Managers.state.extension then
    field_improvisation_cache.value = false
    if t then field_improvisation_cache.last_check = t end
    return false
  end

  local side_system = Managers.state.extension:system("side_system")
  if not side_system then
    field_improvisation_cache.value = false
    if t then field_improvisation_cache.last_check = t end
    return false
  end

  local side = side_system:get_side_from_name(side_system:get_default_player_side_name())
  if not side or not side.player_units then
    field_improvisation_cache.value = false
    if t then field_improvisation_cache.last_check = t end
    return false
  end

  -- Check for field improvisation buff on any player
  local player_units = side.player_units
  local buff_keywords = BuffSettings.keywords

  for i, player_unit in pairs(player_units) do
    local buff_extension = ScriptUnit.extension(player_unit, "buff_system")
    if buff_extension then
      if buff_extension:has_keyword(buff_keywords.improved_ammo_pickups) then
        field_improvisation_cache.value = true
        if t then field_improvisation_cache.last_check = t end
        return true
      end
    end
  end

  field_improvisation_cache.value = false
  if t then field_improvisation_cache.last_check = t end
  return false
end

-- ============================================================================
-- DECAL & AURA FUNCTIONS
-- ============================================================================

local function set_decal_colour(decal_unit, r, g, b)
  if not is_valid_unit(decal_unit) then
    return
  end

  local material_value = Quaternion.identity()
  Quaternion.set_xyzw(material_value, r, g, b, COLOR_ALPHA)
  Unit.set_vector4_for_material(decal_unit, "projector", "particle_color", material_value, true)
  Unit.set_scalar_for_material(decal_unit, "projector", "color_multiplier", COLOR_MULTIPLIER)
end

local function get_decal_unit(unit, r, g, b)
  if not is_valid_unit(unit) then
    return nil
  end

  local world = Unit.world(unit)
  local position = Unit.local_position(unit, 1)

  local decal_unit = World.spawn_unit_ex(world, DECAL_UNIT_NAME, nil, position + Vector3(0, 0, DECAL_Z_OFFSET))

  local diameter = medical_crate_config.proximity_radius * 2 + DECAL_BASE_DIAMETER_OFFSET
  Unit.set_local_scale(decal_unit, 1, Vector3(diameter, diameter, 1))

  set_decal_colour(decal_unit, r, g, b)

  return decal_unit
end

local function cleanup_decals(unit)
  if not is_valid_unit(unit) then
    return
  end

  ammo_crate_cache[unit] = nil

  local world = Unit.world(unit)

  local decal_unit = decals[unit]
  if decal_unit then
    World.destroy_unit(world, decal_unit)
    decals[unit] = nil
  end

  local range_decal = range_decals[unit]
  if range_decal then
    World.destroy_unit(world, range_decal)
    range_decals[unit] = nil
  end
end

local function spawn_decals(unit, dont_load_package)
  if not mod:get("show_medicae_radius") then
    return
  end

  if not Managers.package:has_loaded(PACKAGE_NAME) and not dont_load_package then
    Managers.package:load(PACKAGE_NAME, "Ration Pack", function()
      spawn_decals(unit, true)
    end)
    return
  end

  if not unit then
    return
  end

  decals[unit] = get_decal_unit(unit, 0, 1, 1)
  if not NumericUI or not NumericUI:get("show_medical_crate_radius") then
    range_decals[unit] = get_decal_unit(unit, 1, 1, 1)
  end
end

-- ============================================================================
-- LOGIC APPLICATION
-- ============================================================================

function mod:apply_ration_pack_logic(marker)
  if not is_valid_marker(marker) then
    return
  end

  if marker.widget._ration_pack_applied then
    return
  end

  -- Skip ammo crates - handled by interaction template hook
  if is_ammo_crate(marker.unit) then
    marker.widget._ration_pack_applied = true
    return
  end

  if healthstations[marker.unit] then
    marker.life_time = false
    charge_lookup[marker.unit] = 0

    -- Configure widget passes
    for i, v in ipairs(marker.widget.passes) do
      if v.value_id == "remaining_count" then
        v.visibility_function = function(content, style) return not healthstations[marker.unit] and mod:get("show_numbers") end
        v.change_function = function(model, style) text_change(marker, model) end
      elseif v.value_id == "background" then
        v.change_function = function(model, style) check_background_colour(marker) end
      elseif v.value_id == "icon" then
        v.visibility_function = function(content, style)
          if healthstations[marker.unit] then
            return content.icon ~= nil
          end
          if is_ammo_crate(marker.unit) then
            return content.icon ~= nil and not mod:get("show_numbers")
          end
          return content.icon ~= nil
        end
      end
    end

    marker.widget.dirty = true
  else
    -- Remove remaining_count pass for non-healthstations
    for i = #marker.widget.passes, 1, -1 do
      if marker.widget.passes[i].value_id == "remaining_count" then
        table.remove(marker.widget.passes, i)
        break
      end
    end
    marker.widget.style.remaining_count = nil
    marker.widget.content.remaining_count = nil
  end

  marker.widget._ration_pack_applied = true
end

-- ============================================================================
-- HOOKS & INITIALIZATION
-- ============================================================================

mod.on_all_mods_loaded = function()
  NumericUI = get_mod("NumericUI")
  local is_mod_loading = true

  if mod:get("show_medicae_radius") then
    Managers.package:load(PACKAGE_NAME, "Ration Pack")
  end

  -- Hook: Add remaining_count pass to widget definitions
  mod:hook(CLASS.HudElementWorldMarkers, "_create_widget", function(func, self, name, definition)
    definition.passes[#definition.passes + 1] = table.clone(TEXT_PASS)
    definition.style.remaining_count = table.clone(TEXT_STYLE)
    definition.content.remaining_count = "-"
    return func(self, name, definition)
  end)

  -- Hook: Apply logic when marker is added
  mod:hook_safe(CLASS.HudElementWorldMarkers, "event_add_world_marker_unit",
    function(self, marker_type, unit, callback, data)
      local marker = get_marker(self, unit)
      if marker then
        mod:apply_ration_pack_logic(marker)
      end
    end)

  -- Hook: Update markers every frame
  mod:hook(CLASS.HudElementWorldMarkers, "_calculate_markers",
    function(func, self, dt, t, input_service, ui_renderer, render_settings)
      func(self, dt, t, input_service, ui_renderer, render_settings)

      for _, marker in ipairs(self._markers) do
        if is_valid_marker(marker) then
          -- Apply logic if not yet applied
          if not marker.widget._ration_pack_applied then
            if is_ammo_crate(marker.unit) or healthstations[marker.unit] then
              mod:apply_ration_pack_logic(marker)
            end
          end

          -- Update font scaling every frame
          if marker.widget.style and marker.widget.style.remaining_count then
            local remaining_charges = get_charges(marker)
            if is_valid_charge_count(remaining_charges) then
              local default_font_size = TEXT_STYLE.font_size
              local default_offset = TEXT_STYLE.offset
              local offset = marker.widget.style.remaining_count.offset
              local charge_xoffset = CHARGE_XOFFSET[remaining_charges] or 0

              marker.widget.style.remaining_count.font_size = default_font_size
              offset[1] = default_offset[1] - charge_xoffset
              offset[2] = default_offset[2]
            end
          end
        end
      end
    end)

  -- Hook: Update interaction markers
  mod:hook_safe(CLASS.HudElementWorldMarkers, "init", function(self)
    local interaction_template = self._marker_templates["interaction"]

    if interaction_template and interaction_template.update_function then
      local original_update = interaction_template.update_function

      interaction_template.update_function = function(parent, ui_renderer, widget, marker, template_self, dt, t)
        original_update(parent, ui_renderer, widget, marker, template_self, dt, t)

        if not is_valid_marker(marker) or not widget or not widget.content or not widget.style then
          return
        end

        local unit = marker.unit
        local is_ammo = is_ammo_crate(unit)
        local content = widget.content
        local style = widget.style

        -- Update ammo crate display
        if is_ammo then
          local remaining_charges = get_charges(marker)

          if is_valid_charge_count(remaining_charges) then
            if mod:get("show_numbers") then
              content.remaining_count = remaining_charges
            end

            if mod:get("show_colours") then
              if style.background then
                style.background.color = CHARGE_COLOR[remaining_charges]
              end
            end

            if style.icon and style.icon.color then
              if mod:get("show_numbers") then
                style.icon.color[1] = 0
              else
                style.icon.color[1] = 255
              end
            end
          end
        end

        -- Apply field improvisation styling to ammo crates only
        if has_field_improvisation(t) and is_ammo then
          if style and style.ring then
            style.ring.color = { 255, 70, 130, 180 }
          end
        end
      end
    end
  end)

  -- Hook: Health station extension
  mod:hook_require("scripts/extension_systems/health_station/health_station_extension", function(healthStation)
    mod:hook_safe(healthStation, "_update_indicators", function(self)
      if not healthstations[self._unit] then
        healthstations[self._unit] = self
        interactee[self] = ScriptUnit.fetch_component_extension(self._unit, "interactee_system")

        mod:hook(interactee[self], "show_marker", function(func, self, interactor_unit)
          if healthstations[self._unit]._charge_amount > 0 then
            return function() return true end
          end
          return func(self, interactor_unit)
        end)
      end
    end)
  end)

  -- Hook: Unit template initialization
  mod:hook_require("scripts/extension_systems/unit_templates", function(instance)
    if is_mod_loading then
      mod:hook_safe(instance.medical_crate_deployable, "husk_init", function(unit)
        spawn_decals(unit, false)
      end)

      mod:hook_safe(instance.medical_crate_deployable, "local_init", function(unit)
        spawn_decals(unit, false)
      end)

      if instance.medical_crate_deployable.pre_unit_destroyed then
        mod:hook_safe(instance.medical_crate_deployable, "pre_unit_destroyed", cleanup_decals)
      else
        instance.medical_crate_deployable.pre_unit_destroyed = cleanup_decals
      end
    end

    is_mod_loading = false
  end)

  -- Hook: Update proximity heal visual
  local reserve = 0
  local updateThrottle = {}

  mod:hook_safe(CLASS.ProximityHeal, "update", function(self, dt, t)
    if not mod:get("show_medicae_radius") then return end
    if not is_valid_unit(self._unit) or not decals[self._unit] then return end

    -- Throttle updates
    if not updateThrottle[self._unit] then updateThrottle[self._unit] = t end
    if t - updateThrottle[self._unit] < UPDATE_THROTTLE_INTERVAL then return end
    updateThrottle[self._unit] = t

    -- Update decal color based on field improvisation
    if has_field_improvisation(t) then
      set_decal_colour(decals[self._unit], FIELD_IMPROVEMENT_COLOR.r, FIELD_IMPROVEMENT_COLOR.g, FIELD_IMPROVEMENT_COLOR.b)
    else
      set_decal_colour(decals[self._unit], DEFAULT_DECAL_COLOR.r, DEFAULT_DECAL_COLOR.g, DEFAULT_DECAL_COLOR.b)
    end

    -- Update decal size based on remaining heal amount
    if self._amount_of_damage_healed ~= reserve then
      local diameter = math.lerp(
        medical_crate_config.proximity_radius * 2 + DECAL_BASE_DIAMETER_OFFSET,
        DECAL_BASE_DIAMETER_OFFSET,
        self._amount_of_damage_healed / self._heal_reserve
      )
      Unit.set_local_scale(decals[self._unit], 1, Vector3(diameter, diameter, 1))
      reserve = self._amount_of_damage_healed
    end
  end)
end
