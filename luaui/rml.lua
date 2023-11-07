--  file:    rml.lua
--  brief:   RmlUi Setup
--  author:  lov
--
--  Copyright (C) 2023.
--  Licensed under the terms of the GNU GPL, v2 or later.

if (RmlGuard or not rmlui) then
	return
end
RmlGuard = true


rmlui.LoadFontFace("fonts/Poppins-Regular.otf", true)
rmlui.LoadFontFace("fonts/Exo2-SemiBold.otf", true)
rmlui.LoadFontFace("fonts/SourceHanSans-Regular.ttc", true)

rmlui.LoadFontFace("fonts/monospaced/SourceCodePro-Medium.otf")

rmlui.AddTranslationString("%%topbar.pullTooltip", "outputtext")
