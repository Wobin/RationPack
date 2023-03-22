--[[
Title: Ration Pack
Author: Wobin
Date: 22/03/2023
Repository: https://github.com/Wobin/RationPack
Version: 2.1
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

 mod:hook(CLASS.HudElementWorldMarkers, "_create_widget", function(func, self, name, definition)
    definition.passes[1].visibility_function = function(model, style)
        if model.icon == 'content/ui/materials/hud/interactions/icons/ammunition' then          
          local widget = self._widgets_by_name[name]
          for _, marker in ipairs(self._markers) do               
            if marker.widget == widget then                            
              if Pickups.by_name[Unit.get_data(marker.unit, "pickup_type")].ammo_crate then
                local charge = charge_lookup[marker.id] or 0
                local remaining_charges = GameSession.game_object_field(Managers.state.game_session:game_session(), Managers.state.unit_spawner:game_object_id(marker.unit), "charges")                            
                if remaining_charges and remaining_charges ~= charge then          
                  charge_lookup[marker.id] = remaining_charges
                  if mod:get("show_colours") then
                    style.color = charge_colour[remaining_charges]
                    return mod:get("show_colours")                    
                  end                                   
                end              
              end
            end
          end
        end        
        return true
      end    
    definition.passes[4].visibility_function = function(model) 
      if model.icon == 'content/ui/materials/hud/interactions/icons/ammunition' then
        local widget = self._widgets_by_name[name]
        for _, marker in ipairs(self._markers) do               
          if marker.widget == widget then                            
            if Pickups.by_name[Unit.get_data(marker.unit, "pickup_type")].ammo_crate then    
              return not mod:get("show_numbers")             
            end
          end
        end            
      end
      return true
    end        
    definition.style.remaining_count =  table.clone(UIFontSettings.header_2)
    definition.style.remaining_count.offset = {-10,10,4}
    definition.style.remaining_count.size= {64,64}
    definition.style.remaining_count.vertical_alignment = "center"
    definition.style.remaining_count.horizontal_alignment  = "left"
    definition.style.remaining_count.scale_to_material  = true
     table.insert(definition.passes, {
        style_id = 'remaining_count',
        pass_type = 'text',
        value_id = 'remaining_count',
        visibility_function = function(model)          
          if mod:get("show_numbers") and model.icon == 'content/ui/materials/hud/interactions/icons/ammunition' then          
            local widget = self._widgets_by_name[name]
            for _, marker in ipairs(self._markers) do               
              if marker.widget == widget then                            
                if Pickups.by_name[Unit.get_data(marker.unit, "pickup_type")].ammo_crate then                     
                    widget.content.remaining_count = mod:localize(charge_lookup[marker.id])               
                    widget.style.remaining_count.offset[1] = baseOffset[1] + xoffset[charge_lookup[marker.id]]   
                    if mod:get("show_colours") then
                      widget.style.remaining_count.text_color = fontContrast[charge_lookup[marker.id]]
                    end
                    return mod:get("show_numbers")
                end                            
              end
            end
          end
          return false
        end
      })
    return func(self, name, definition)
  end)
  