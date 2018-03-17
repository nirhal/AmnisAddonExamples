require("Classes")
require("SubtitlesAddon")
require("soap")
require("base64")

-- SubtitlesService class definition:
GetSubsService = newClass(SubtitlesService)

function GetSubsService:_init()
    self.superClass()._init(self)
    self.apiURL = "http://api.getsubtitle.com/server.php"
    self.preferences = AddonHelper.settings.preferences
    log("Loaded.")
    return self
end

function GetSubsService:search(q, videoInfo, langs)

    if (videoInfo == nil or videoInfo:getHash() == nil) then
        -- Doesn't support text search, return error
        return AddonHelper.subtitles.SubtitlesError:new("This provider doesn't support text search.")
    end

    local request = {
        soapaction = "searchSubtitlesByHash_wsdl#searchSubtitlesByHash",
        namespace = "searchSubtitlesByHash_wsdl",
        method = "searchSubtitlesByHash",
        entries = {
            { tag = "hash", attr = { ["xsi:type"] = "xsd:string" }, videoInfo:getHash() },
            { tag = "language", attr = { ["xsi:type"] = "xsd:string" }, langs },
            { tag = "index",   attr = { ["xsi:type"] = "xsd:int" }, 0 },
            { tag = "count",   attr = { ["xsi:type"] = "xsd:int" }, 100 },
        }
    }


    local soap = SOAP:new(self.apiURL)
    local response = soap:call(request);
    local ret = SOAP.findTag(response.entries, "return")

    local results = AddonHelper.subtitles.SubtitlesList:new()
    for _, item in ipairs(ret) do
        local entry = AddonHelper.subtitles.SubtitlesResult:new()
        entry:setTitle(SOAP.findTag(item, "file_name")[1])
        entry:setLanguage(SOAP.findTag(item, "desc_reduzido")[1])
        local data = {cod = SOAP.findTag(item, "cod_subtitle_file")[1], filePath = nil}
        entry:setData(data)
        results:add(entry)
    end

    return results

end


function GetSubsService:select(item)
    local itemdata = item:getData()
    if itemdata.filePath == nil or AddonHelper.utils:fileExists(data.filePath) == false  then

        local request = {
            soapaction = "downloadSubtitles_wsdl#downloadSubtitles",
            namespace = "downloadSubtitles_wsdl",
            method = "downloadSubtitles",
            entries = {
                { tag = "subtitles", attr = { ["xsi:type"] = "xsd:Array" },
                    { tag = "item",
                        { tag = "cod_subtitle_file",   attr = { ["xsi:type"] = "xsd:int" }, itemdata["cod"] },
                    }
                }
            }
        }
        local soap = SOAP:new(self.apiURL)
        local response = soap:call(request);

        local ret = SOAP.findTag(response.entries, "return")
        local arritem = ret[1]

        local data = SOAP.findTag(arritem, "data")[1]

        local decodedBytes = base64dec(data)
        itemdata.filePath = AddonHelper.utils:saveByteArrayToFile(item:getTitle(), decodedBytes, "deflate_wrap")
    end
    return itemdata.filePath

end

getSubsService = GetSubsService:new()