return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Ration Pack` encountered an error loading the Darktide Mod Framework.")

		new_mod("Ration Pack", {
			mod_script       = "Ration Pack/scripts/mods/Ration Pack/Ration Pack",
			mod_data         = "Ration Pack/scripts/mods/Ration Pack/Ration Pack_data",
			mod_localization = "Ration Pack/scripts/mods/Ration Pack/Ration Pack_localization",
		})
	end,
	packages = {},
}
