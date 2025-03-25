--[[
Title: Ration Pack
Author: Wobin
Date: 25/03/2025
Repository: https://github.com/Wobin/RationPack
Version: 6.3.3
]]--
local mod = get_mod("Ration Pack")
mod.version = "6.3.3"
local charge_lookup = {}
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local Pickups = require("scripts/settings/pickup/pickups")
local BuffSettings = require("scripts/settings/buff/buff_settings")
local medical_crate_config = require("scripts/settings/deployables/templates/medical_crate")
local decal_unit_name = "content/levels/training_grounds/fx/decal_aoe_indicator"
local package_name = "content/levels/training_grounds/missions/mission_tg_basic_combat_01"
local decals = mod:persistent_table("medical_crate_decals")
local range_decals = mod:persistent_table("medical_crate_range_decals")
local has_checked_package = mod:persistent_table("texture_check", {false})
local NumericUI 

local healthstations = {}
local interactee = {}

local charge_colour = {
  [4] = Color.teal(255, true),
  [3] = Color.yellow(255, true),
  [2] = Color.orange(255, true),
  [1] = Color.red(255, true)
}
local fontContrast = { 
  [4] = Color.terminal_text_header(255, true),
  [3] = Color.terminal_text_body_dark(255, true),
  [2] = Color.terminal_text_body_dark(255, true),
  [1] = Color.terminal_text_header(255, true)
  }
local  xoffset = {[4] = 2, [3] = 0, [2] = 0, [1] = 0}

local text_pass = {
  style_id = 'remaining_count',
  pass_type = 'text',
  value_id = 'remaining_count',
  visibility_function = function() return false end          
}
        
local text_style = {
  offset = {-10,20,4},
  size= {64,64},
  vertical_alignment = "center",
  horizontal_alignment  = "left"
}

table.merge(text_style, table.clone(UIFontSettings.header_2))

-- Ammo Pack functions --

local function is_ammo_crate(target)
  return (target and 
  Unit and
  Unit.alive(target) and
  Unit.has_data(target, "pickup_type") and
  Unit.get_data(target, "pickup_type") ~= nil and
  Pickups.by_name[Unit.get_data(target, "pickup_type")] ~= nil and 
  Pickups.by_name[Unit.get_data(target, "pickup_type")].ammo_crate) or false 
end

local function get_charges(marker)
  return (not healthstations[marker.unit] and GameSession.game_object_field(Managers.state.game_session:game_session(), Managers.state.unit_spawner:game_object_id(marker.unit), "charges")) or healthstations[marker.unit]._charge_amount
end

local function get_marker(self, unit)
  for _, marker in ipairs(self._markers) do
    if marker.unit == unit then return marker end
  end
end

local function text_change(marker, model)
  if healthstations[marker.unit] or not mod:get("show_numbers") then return end  
  local remaining_charges = get_charges(marker)      
  marker.widget.content.remaining_count = remaining_charges  
  
  local scale = marker.scale
	local default_font_size = text_style.font_size
  if marker.is_clamped then
    marker.widget.style.remaining_count.font_size = default_font_size
  else
    marker.widget.style.remaining_count.font_size = math.max(default_font_size * scale, 1)
  end

  
  local lerp_multiplier = 0.02
  local default_offset = text_style.offset
  local offset = marker.widget.style.remaining_count.offset
  if not marker.is_clamped then
			offset[1] = default_offset[1] * (scale) - xoffset[remaining_charges]
			offset[2] = math.auto_lerp(0.4, 1.0, 24, 10, scale)
  else
			offset[1] = default_offset[1] - xoffset[remaining_charges]
			offset[2] = 10    
  end
      
  if mod:get("show_colours") then
    marker.widget.style.remaining_count.text_color = fontContrast[ remaining_charges ]
  end                            
end

local function check_background_colour(marker)
  local charge = charge_lookup[marker.unit] or 0
  local remaining_charges = get_charges(marker)                      
  if remaining_charges and remaining_charges ~= charge then          
    charge_lookup[marker.unit] = remaining_charges
    if mod:get("show_colours") then
      marker.widget.style.background.color = charge_colour[remaining_charges]                    
    end
  end
end

-- Field Improvisation Check -- 
local function has_field_improvisation()      
		local side_system = Managers.state.extension:system("side_system")    
		local side = side_system:get_side_from_name(side_system:get_default_player_side_name())
		local player_units = side.player_units
		local buff_keywords = BuffSettings.keywords
    local improved_keyword
		for _, player_unit in pairs(player_units) do
			local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")

			if buff_extension then
				improved_keyword = buff_extension:has_keyword(buff_keywords.improved_ammo_pickups)        
				if improved_keyword then
          return true					
				end
			end
		end 
    if not improved_keyword then
      return false
    end
  end

local function get_enhanced(style)
  if has_field_improvisation() then
    style.color = Color.steel_blue(255,true)
  else
    style.color = Color.ui_terminal(255,true)
  end
end


--- Medikit Aura Functions ---

local function pre_unit_destroyed(unit)
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

local function set_decal_colour(decal_unit, r, g, b)
  local material_value = Quaternion.identity()
	Quaternion.set_xyzw(material_value, r, g, b, 0.5)
	Unit.set_vector4_for_material(decal_unit, "projector", "particle_color", material_value, true)
	Unit.set_scalar_for_material( decal_unit, "projector", "color_multiplier", 0.05)
end

local function get_decal_unit(unit, r, g, b)

	local world = Unit.world(unit)
	local position = Unit.local_position(unit, 1)

	local decal_unit = World.spawn_unit_ex(world, decal_unit_name, nil, position + Vector3(0, 0, 0.1))

	local diameter = medical_crate_config.proximity_radius * 2 + 1.5
	Unit.set_local_scale(decal_unit, 1, Vector3(diameter, diameter, 1))
  
  set_decal_colour(decal_unit, r, g, b)
  
  return decal_unit
end

local function unit_spawned(unit, dont_load_package)
	if not mod:get("show_medicae_radius") then
		return
	end

	if not Managers.package:has_loaded(package_name) and not dont_load_package then
		Managers.package:load(package_name, "Ration Pack", function()
			unit_spawned(unit, true)
		end)
		return
	end
  
	if not unit then
		return
	end

  
  local unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
  --mod:dump(unit_data_extension, "medkit", 1)
	decals[unit] = get_decal_unit(unit, 0, 1, 1)
  if not NumericUI or not NumericUI:get("show_medical_crate_radius") then
    range_decals[unit] = get_decal_unit(unit, 1, 1, 1)
  end
end

mod.on_all_mods_loaded = function()
    mod:info(mod.version)
    NumericUI = get_mod("NumericUI")
    local is_mod_loading = true
    if mod:get("show_medicae_radius") then
      Managers.package:load(package_name, "Ration Pack")
    end
  
    mod:hook(CLASS.HudElementWorldMarkers, "_create_widget", function(func, self, name, definition)       
      definition.passes[#definition.passes + 1] = table.clone(text_pass)
      definition.style.remaining_count = table.clone(text_style)
      definition.content.remaining_count = "-"                    
      return func(self, name, definition)
    end)
  
    local counter = 0
  
    mod:hook_safe(CLASS.HudElementWorldMarkers, "event_add_world_marker_unit",  function (self, marker_type, unit, callback, data)
        if is_ammo_crate(unit) or healthstations[unit] then           
          local marker = get_marker(self, unit)              
          marker.life_time = false
          charge_lookup[marker.unit] = 0
          for i,v in ipairs(marker.widget.passes) do
            if is_ammo_crate(unit) and v.value_id == "ring" then
              v.change_function = function(model, style) get_enhanced(style) end                
            end
            if v.value_id == "remaining_count" then              
              v.visibility_function = function() return not healthstations[unit] and mod:get("show_numbers") end
              v.change_function = function(model, style) text_change(marker, model) end              
            end
            if v.value_id == "background" then
              v.change_function = function(model, style) check_background_colour(marker) end           
            end
            if v.value_id == "icon" then
              v.visibility_function = function(model) return healthstations[marker.unit] or not mod:get("show_numbers") end        
            end
          end
          marker.widget.dirty = true
        else
          local marker = get_marker(self, unit)           
          for i,v in ipairs(marker.widget.passes) do
            if v.value_id == "remaining_count" then
              table.remove(marker.widget.passes, i)
              break
            end
          end
          marker.widget.style.remaining_count = nil          
          marker.widget.content.remaining_count = nil
        end
    end)
   
    mod:hook_require("scripts/extension_systems/health_station/health_station_extension", function(healthStation)
    mod:hook_safe(healthStation, "_update_indicators",function (self)        
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
    mod:hook_require("scripts/extension_systems/unit_templates", function(instance)    
        if is_mod_loading then
          mod:hook_safe(instance.medical_crate_deployable, "husk_init", function(unit)              
            unit_spawned(unit, false)
          end)
          mod:hook_safe(instance.medical_crate_deployable, "local_init", function(unit)              
            unit_spawned(unit, false)
          end)
          if instance.medical_crate_deployable.pre_unit_destroyed then
            mod:hook_safe(instance.medical_crate_deployable, "pre_unit_destroyed", pre_unit_destroyed)
          else
            instance.medical_crate_deployable.pre_unit_destroyed = pre_unit_destroyed
          end          
        end
        is_mod_loading = false
    end)
  
    local reserve = 0
    local updateThrottle = {}
    mod:hook_safe(CLASS.ProximityHeal, "update", function(self, dt,t)
      if not mod:get("show_medicae_radius") then return end
      if not self._unit or not decals[self._unit] then return end
      -- throttle updates
      if not updateThrottle[self._unit] then updateThrottle[self._unit] = t end
      if t - updateThrottle[self._unit] < 0.5 then return end
      updateThrottle[self._unit] = t 
      
      if has_field_improvisation() then
        set_decal_colour(decals[self._unit], 11/255 , 105/255, 116/255)
      else
        set_decal_colour(decals[self._unit], 0, 1, 0)
      end
      if self._amount_of_damage_healed ~= reserve then
        local diameter =  math.lerp(medical_crate_config.proximity_radius * 2 + 1.5, 1.5, self._amount_of_damage_healed / self._heal_reserve)
        Unit.set_local_scale(decals[self._unit], 1, Vector3(diameter, diameter, 1))
        reserve = self._amount_of_damage_healed
      end
    end)    
 end 