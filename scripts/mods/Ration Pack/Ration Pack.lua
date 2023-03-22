--[[
Title: Ration Pack
Author: Wobin
Date: 22/03/2023
Repository: https://github.com/Wobin/RationPack
]]--
local mod = get_mod("Ration Pack")
local Pickups = require("scripts/settings/pickup/pickups")
local charge_lookup = {}
local charge_colour = {
  [4] = Color.teal(255, true),
  [3] = Color.yellow(255, true),
  [2] = Color.orange(255, true),
  [1] = Color.red(255, true)
  }
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
                  style.color = charge_colour[remaining_charges]
                  charge_lookup[marker.id] = remaining_charges
                  break
                end              
              end
            end
          end
        end        
        return true
      end    
    return func(self, name, definition)
  end)