--  file:    rml.lua
--  brief:   RmlUi Setup
--  author:  lov
--
--  Copyright (C) 2023.
--  Licensed under the terms of the GNU GPL, v2 or later.

if (RmlGuard or not RmlUi) then
	return
end
RmlGuard = true

RmlUi.CreateContext("overlay")

RmlUi.LoadFontFace("fonts/Poppins-Regular.otf", true)
RmlUi.LoadFontFace("fonts/Exo2-SemiBold.otf", true)
RmlUi.LoadFontFace("fonts/SourceHanSans-Regular.ttc", true)

RmlUi.LoadFontFace("fonts/monospaced/SourceCodePro-Medium.otf")

RmlUi.AddTranslationString("%%topbar.pullTooltip", "outputtext")
