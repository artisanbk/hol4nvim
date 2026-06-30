--[[
  Filetype detection for HOL4 script files.

  Files under ftdetect/ are sourced at startup whenever the plugin is on the
  runtimepath, so *Script.sml is recognised as `hol4script` before any such
  file is opened. This is the canonical, load-order-independent place for
  detection -- it works for a normally-installed plugin regardless of whether
  setup() has run yet.
--]]
vim.filetype.add({
	pattern = {
		[".*Script%.sml"] = "hol4script",
	},
})
