local mod = get_mod("Ration Pack")

return {
	name = mod:localize("mod_title"),
	description = mod:localize("mod_description"),
	is_togglable = true,
  options = {
		widgets = {
			{
				setting_id = "show_numbers",
				type = "checkbox",
				default_value = false
			},
      {
				setting_id = "show_colours",
				type = "checkbox",
				default_value = false
			},
      {
				setting_id = "show_medicae_radius",
				type = "checkbox",
				default_value = false
			}
		}
  }
}
