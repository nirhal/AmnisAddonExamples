require("Classes")
require("SubtitlesAddon")
require("soap")


-- SettingsBuilder class definition:

BSPlayerSubsSettings = newClass(SettingsBuilder)

function BSPlayerSubsSettings:_init()
    self.superClass()._init(self)
    log("BSPlayerSubsSettings loaded")
end

function BSPlayerSubsSettings:build()
    local screen = AddonHelper.settings.AddonSettingsScreen:new()

    local username = AddonHelper.settings.AddonEditTextPreference:new("username")
    username:setDefaultValue("")
    username:setTitle("User name")
    screen:add(username)

    local password = AddonHelper.settings.AddonEditTextPreference:new("password")
    password:setDefaultValue("")
    password:setTitle("Password")
    password:setInputType("textPassword")
    screen:add(password)

    return screen
end

function BSPlayerSubsSettings:valueChanged(screen, key)

    local pref = screen:get(key)

    if (key == "username") then
        pref:setSummary(pref:getText())
    end

    if (key == "password") then
        if (pref:getText() == "") then
            pref:setSummary("No password")
        else
            pref:setSummary("********")
        end

    end
end


-- SubtitlesService class definition:
BSPlayerSubsService = newClass(SubtitlesService)

function BSPlayerSubsService:_init()
    self.superClass()._init(self)
    self.namespace = "http://s8.api.bsplayer-subtitles.com/v1.php"
    self.apiURL = "http://api.bsplayer-subtitles.com/v1.php"
    self.preferences = AddonHelper.settings.preferences
    log("Loaded.")
    return self
end

function BSPlayerSubsService:search(q, videoInfo, langs)

    if (videoInfo == nil or videoInfo:getHash() == nil) then
        -- Doesn't support text search, return error
        return AddonHelper.subtitles.SubtitlesError:new("This provider doesn't support text search.")
    end

    local soap = SOAP:new(self.apiURL)

    local username = self.preferences:get("username", "")
    local password = self.preferences:get("password", "")

    local request = {
        soapaction = self.apiURL .. "#logIn",
        namespace = self.namespace,
        method = "logIn",
        entries = {
            { tag = "username", attr = { ["xsi:type"] = "xsd:string" }, username },
            { tag = "password", attr = { ["xsi:type"] = "xsd:string" }, password },
            { tag = "AppID", attr = { ["xsi:type"] = "xsd:string" }, "WT_Addon_v0.1" },
        }
    }

    local response = soap:call(request);

    local ret = SOAP.findTag(response.entries, "return")
    local handle = SOAP.findTag(ret, "data")[1]

    request = {
        soapaction = self.apiURL .. "#searchSubtitles",
        namespace = self.namespace,
        method = "searchSubtitles",
        entries = {
            { tag = "handle", attr = { ["xsi:type"] = "xsd:string" }, handle },
            { tag = "movieHash", attr = { ["xsi:type"] = "xsd:string" }, videoInfo:getHash() },
            { tag = "movieSize", attr = { ["xsi:type"] = "xsd:int" }, videoInfo:getFileSize() },
            { tag = "languageId", attr = { ["xsi:type"] = "xsd:string" }, langs },
            { tag = "imdbId", attr = { ["xsi:type"] = "xsd:string" }, "*" },
        }
    }
    response = soap:call(request);
    ret = SOAP.findTag(response.entries, "return")
    local data = SOAP.findTag(ret, "data")

    local results = AddonHelper.subtitles.SubtitlesList:new()
    for _, item in ipairs(data) do
        local entry = AddonHelper.subtitles.SubtitlesResult:new()
        entry:setTitle(SOAP.findTag(item, "subName")[1])
        entry:setLanguage(SOAP.findTag(item, "subLang")[1])
        local data = {url = SOAP.findTag(item, "subDownloadLink")[1], filePath = nil}
        entry:setData(data)
        results:add(entry)
    end

    request = {
        soapaction = self.apiURL .. "#logOut",
        namespace = self.namespace,
        method = "logOut",
        entries = {
            { tag = "handle", attr = { ["xsi:type"] = "xsd:string" }, handle },
        }
    }
    response = soap:call(request);

    return results
end

function BSPlayerSubsService:select(item)
    local data = item:getData()
    if data.filePath == nil or AddonHelper.utils:fileExists(data.filePath) == false then
        data.filePath = AddonHelper.utils:downloadFile(item:getTitle(), data.url, "gzip")
    end
    return data.filePath
end


BSPlayerSubsServiceObj = BSPlayerSubsService:new()
BSPlayerSubsSettingsObj = BSPlayerSubsSettings:new()