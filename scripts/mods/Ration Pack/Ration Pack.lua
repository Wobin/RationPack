--[[
Title: Ration Pack
Author: Wobin
Date: 24/01/2024
Repository: https://github.com/Wobin/RationPack
Version: 5.0
]]--
local mod = get_mod("Ration Pack")
local charge_lookup = {}
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local Pickups = require("scripts/settings/pickup/pickups")
local BuffSettings = require("scripts/settings/buff/buff_settings")

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

local is_ammo_crate = function(target)
  return (target and 
  Unit and
  Unit.alive(target) and
  Unit.has_data(target, "pickup_type") and
  Unit.get_data(target, "pickup_type") ~= nil and
  Pickups.by_name[Unit.get_data(target, "pickup_type")] ~= nil and 
  Pickups.by_name[Unit.get_data(target, "pickup_type")].ammo_crate) or false 
end

local get_charges = function(marker)
  return (not healthstations[marker.unit] and GameSession.game_object_field(Managers.state.game_session:game_session(), Managers.state.unit_spawner:game_object_id(marker.unit), "charges")) or healthstations[marker.unit]._charge_amount
end

local get_marker = function(self, unit)
  for _, marker in ipairs(self._markers) do
    if marker.unit == unit then return marker end
  end
end

local text_change = function(marker, model)
  if healthstations[marker.unit] or not mod:get("show_numbers") then return end  
  local remaining_charges = get_charges(marker)      
  marker.widget.content.remaining_count = remaining_charges  
  
  local scale = marker.scale
	local default_font_size = text_style.font_size
  marker.widget.style.remaining_count.font_size = math.max(default_font_size * scale, 1)

  local lerp_multiplier = 0.02
  local default_offset = text_style.offset
  local offset = marker.widget.style.remaining_count.offset
			offset[1] = default_offset[1] * (scale) - xoffset[remaining_charges]
			offset[2] = math.auto_lerp(0.4, 1.0, 24, 10, scale)
      
  if mod:get("show_colours") then
    marker.widget.style.remaining_count.text_color = fontContrast[ remaining_charges ]
  end                            
end

local check_background_colour = function(marker)
  local charge = charge_lookup[marker.unit] or 0
  local remaining_charges = get_charges(marker)                      
  if remaining_charges and remaining_charges ~= charge then          
    charge_lookup[marker.unit] = remaining_charges
    if mod:get("show_colours") then
      marker.widget.style.background.color = charge_colour[remaining_charges]                    
    end
  end
end

local get_enhanced = function(style)      
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
          style.color = Color.coral(255, true)
					break
				end
			end
		end 
    if not improved_keyword then
      style.color = Color.ui_terminal(255,true)
    end
  end

mod.on_all_mods_loaded = function()
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
 end 