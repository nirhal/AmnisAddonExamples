
require("Classes")
require("SubtitlesAddon")
require("xmlrpc")
--local inspect = require('inspect')


-- SettingsBuilder class definition:

OpenSubsSettings = newClass(SettingsBuilder)

function OpenSubsSettings:_init()
    self.superClass()._init(self)
    log("OpenSubsSettings loaded")
end

function OpenSubsSettings:build()
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

function OpenSubsSettings:valueChanged(screen, key)

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
OpenSubsService =  newClass(SubtitlesService)

function OpenSubsService:_init()
    self.superClass()._init(self)
    self.apiURL = "http://api.opensubtitles.org/xml-rpc"
    self.preferences = AddonHelper.settings.preferences
    log("OpenSubsAddon Loaded.")
end

function OpenSubsService:search(q, videoInfo, langs)

    local xmlrpc = XMLRPC:new(self.apiURL)
    local username = self.preferences:get("username", "")
    local password = self.preferences:get("password", "")
    local loginHash = xmlrpc:call("LogIn", username, password, "en", "WT APP v1")
    local token = loginHash["token"]

    local searchEntry = {}
    if (videoInfo ~= nil) then
        if (videoInfo:getHash() ~= nil) then
            searchEntry["moviehash"] = videoInfo:getHash()
            searchEntry["moviebytesize"] = videoInfo:getFileSize()
        else
            searchEntry["query"] = videoInfo:getTitle()
        end
    else
        searchEntry["query"] = q
    end
    searchEntry["sublanguageid"] = langs

    local searchVector = {searchEntry }

    local search = xmlrpc:call("SearchSubtitles", token, XMLRPC.newTypedValue(searchVector, XMLRPC.newArrayType("struct")))
    local searchResults = search["data"]

    local results = AddonHelper.subtitles.SubtitlesList:new()

    for _, result in ipairs(searchResults) do
        local entry = AddonHelper.subtitles.SubtitlesResult:new()
        entry:setTitle(result["SubFileName"])
        entry:setLanguage(result["SubLanguageID"])
        local data = {url = result["SubDownloadLink"], filePath = nil}
        entry:setData(data)
        results:add(entry)
    end

    xmlrpc:call("LogOut", token)

    return results

end


function OpenSubsService:select(item)
    local data = item:getData()
    if data.filePath == nil or AddonHelper.utils:fileExists(data.filePath) == false  then
        data.filePath = AddonHelper.utils:downloadFile(item:getTitle(), data.url, "gzip")
    end
    return data.filePath
end



openSubsSettings = OpenSubsSettings:new()
openSubsService = OpenSubsService:new()
