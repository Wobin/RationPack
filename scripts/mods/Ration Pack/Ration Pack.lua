--[[
Title: Ration Pack
Author: Wobin
Date: 22/03/2023
Repository: https://github.com/Wobin/RationPack
Version: 3.1
]]--
local mod = get_mod("Ration Pack")
local charge_lookup = {}
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local Pickups = require("scripts/settings/pickup/pickups")

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
local  xoffset = {[4] = -2, [3] = 0, [2] = 0, [1] = 0}
local baseOffset = {-10,10,4}

local text_pass = {
  style_id = 'remaining_count',
  pass_type = 'text',
  value_id = 'remaining_count',
  visibility_function = function() return false end          
}
        
local text_style = {
  offset = {-10,10,4},
  size= {64,64},
  vertical_alignment = "center",
  horizontal_alignment  = "left"
}

table.merge(text_style, table.clone(UIFontSettings.header_2))

local is_ammo_crate = function(target)
  if target ~= nil and Pickups.by_name[Unit.get_data(target, "pickup_type")] ~= nil then return Pickups.by_name[Unit.get_data(target, "pickup_type")].ammo_crate end
  return false  
end

local is_ammo_icon = function(model)
  return model.icon == 'content/ui/materials/hud/interactions/icons/ammunition' 
end

local get_charges = function(marker)
  return GameSession.game_object_field(Managers.state.game_session:game_session(), Managers.state.unit_spawner:game_object_id(marker.unit), "charges")
end

local get_marker = function(self, unit)
  for _, marker in ipairs(self._markers) do
    if marker.unit == unit then return marker end
  end
end

local text_change = function(marker, model)
  if not mod:get("show_numbers") then return end  
  marker.widget.content.remaining_count = charge_lookup[marker.id]          
  marker.widget.style.remaining_count.offset[1] = baseOffset[1] + xoffset[ charge_lookup[marker.id] ]      
  if mod:get("show_colours") then
    marker.widget.style.remaining_count.text_color = fontContrast[ charge_lookup[marker.id] ]
  end                            
end



local check_background_colour = function(marker)
  local charge = charge_lookup[marker.id] or 0
  local remaining_charges = get_charges(marker)                            
  if remaining_charges and remaining_charges ~= charge then          
    charge_lookup[marker.id] = remaining_charges
    if mod:get("show_colours") then
      marker.widget.style.background.color = charge_colour[remaining_charges]                    
    end
  end
end


mod.on_all_mods_loaded = function()
    mod:hook(CLASS.HudElementWorldMarkers, "_create_widget", function(func, self, name, definition)       
      definition.passes[#definition.passes + 1] = table.clone(text_pass)
      definition.style.remaining_count = table.clone(text_style)
      definition.content.remaining_count = "-"                    
      return func(self, name, definition)
    end)
  
  
    mod:hook_safe(CLASS.HudElementWorldMarkers, "event_add_world_marker_unit",  function (self, marker_type, unit, callback, data)
        if is_ammo_crate(unit) then           
          local marker = get_marker(self, unit)           
          for i,v in ipairs(marker.widget.passes) do
            if v.value_id == "remaining_count" then              
              v.visibility_function = function() return mod:get("show_numbers") end
              v.change_function = function(model) text_change(marker, model) end              
            end
            if v.value_id == "background" then
              v.change_function = function(model, style) check_background_colour(marker) end           
            end
            if v.value_id == "icon" then
              v.visibility_function = function(model) return not mod:get("show_numbers") end        
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
 end 