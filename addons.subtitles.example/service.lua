
require("Classes")
require("SubtitlesAddon")


-- SettingsBuilder class definition:

SubtitlesExampleSettings = newClass(SettingsBuilder)

function SubtitlesExampleSettings:_init()
    self.superClass()._init(self)
    log("Example Subtitles Settings loaded")
end

function SubtitlesExampleSettings:build()
    local screen = AddonHelper.settings.AddonSettingsScreen:new()

    local a_number = AddonHelper.settings.AddonEditTextPreference:new("a_number")
    a_number:setInputType("number")
    a_number:setDefaultValue("1")
    a_number:setTitle("Subtitles A count")
    screen:add(a_number)

    local switch = AddonHelper.settings.AddonSwitchPreference:new("show_b")
    switch:setDefaultValue(true)
    switch:setTitle("Show Subtitles B")
    screen:add(switch)

    local b_number = AddonHelper.settings.AddonEditTextPreference:new("b_number")
    b_number:setInputType("number")
    b_number:setDefaultValue("2")
    b_number:setTitle("Subtitles B count")
    screen:add(b_number)

    local b_lang = AddonHelper.settings.AddonListPreference:new("b_lang")
    b_lang:setDefaultValue("eng")
    b_lang:setTitle("Language of B subtitles")
    b_lang:addEntry("eng","English")
    b_lang:addEntry("dut","Dutch")
    b_lang:addEntry("fre","French")
    screen:add(b_lang)

    return screen
end

function SubtitlesExampleSettings:valueChanged(screen, key)

    local pref = screen:get(key)

    if (key == "a_number" or key == "b_number") then
        if (pref:getText() == "1") then
            pref:setSummary("Show it once")
        else
            pref:setSummary("Show it " .. pref:getText() .. " times")
        end

    end

    if (key == "show_b") then
        screen:get("b_number"):setEnabled(pref:isChecked())
        screen:get("b_lang"):setEnabled(pref:isChecked())
    end

    if (key == "b_lang") then
        pref:setSummary(pref:getText())
    end
end


-- SubtitlesService class definition:
SubtitlesExampleService =  newClass(SubtitlesService)

function SubtitlesExampleService:_init()
    self.superClass()._init(self)
    self.preferences = AddonHelper.settings.preferences
    log("Example Subtitles service Loaded.")
end

function SubtitlesExampleService:search(q, videoInfo, langs)

    local results = AddonHelper.subtitles.SubtitlesList:new()

    local a_number = tonumber(self.preferences:get("a_number", "1"))
    for i=1,a_number do
        local entry = AddonHelper.subtitles.SubtitlesResult:new()
        entry:setTitle("Subtitles A #" .. tostring(i))
        entry:setLanguage("eng")
        entry:setData("A")
        results:add(entry)
    end

    local show_b = self.preferences:get("show_b", true)
    if show_b then
        local b_number = tonumber(self.preferences:get("b_number", "2"))
        for i=1,b_number do
            local entry = AddonHelper.subtitles.SubtitlesResult:new()
            entry:setTitle("Subtitles B #" .. tostring(i))
            entry:setLanguage(self.preferences:get("b_lang", "eng"))
            entry:setData("B")
            results:add(entry)
        end
    end

    return results

end


function SubtitlesExampleService:select(item)
    if item:getData() == "A" then
        return AddonHelper.addonInformation:getFilesDir() .. "/A.srt"
    elseif item:getData() == "B" then
        return AddonHelper.addonInformation:getFilesDir() .. "/B.srt"
    end
    return nil
end



subtitlesExampleSettings = SubtitlesExampleSettings:new()
subtitlesExampleService = SubtitlesExampleService:new()
