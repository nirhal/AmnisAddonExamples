
local assert, error, pairs, tonumber, tostring, type = assert, error, pairs, tonumber, tostring, type
local table = require"table"
local tconcat, tinsert, tremove = table.concat, table.insert, table.remove
local string = require"string"
local gsub, strfind, strformat = string.gsub, string.find, string.format
local max = require"math".max

local XmlPullParser = jlua.getClass("org.xmlpull.v1.XmlPullParser")
local XmlPullParserFactory = jlua.getClass("org.xmlpull.v1.XmlPullParserFactory")
local URL = jlua.getClass("java.net.URL")
local DataOutputStream = jlua.getClass("java.io.DataOutputStream")

local tescape = {
    ['&'] = '&amp;',
    ['<'] = '&lt;',
    ['>'] = '&gt;',
    ['"'] = '&quot;',
    ["'"] = '&apos;',
}
---------------------------------------------------------------------
-- Escape special characters.
---------------------------------------------------------------------
local function escape (text)
    return (gsub (text, "([&<>'\"])", tescape))
end

local tunescape = {
    ['&amp;'] = '&',
    ['&lt;'] = '<',
    ['&gt;'] = '>',
    ['&quot;'] = '"',
    ['&apos;'] = "'",
}
---------------------------------------------------------------------
-- Unescape special characters.
---------------------------------------------------------------------
local function unescape (text)
    return (gsub (text, "(&%a+%;)", tunescape))
end

local serialize

---------------------------------------------------------------------
-- Serialize the table of attributes.
-- @param a Table with the attributes of an element.
-- @return String representation of the object.
---------------------------------------------------------------------
local function attrs (a)
    if not a then
        return "" -- no attributes
    else
        local c = {}
        if a[1] then
            for i = 1, #a do
                local v = a[i]
                c[i] = strformat ("%s=%q", v, a[v])
            end
        else
            for i, v in pairs (a) do
                c[#c+1] = strformat ("%s=%q", i, v)
            end
        end
        if #c > 0 then
            return " "..tconcat (c, " ")
        else
            return ""
        end
    end
end

---------------------------------------------------------------------
-- Serialize the children of an object.
-- @param obj Table with the object to be serialized.
-- @return String representation of the children.
---------------------------------------------------------------------
local function contents (obj)
    if not obj[1] then
        return ""
    else
        local c = {}
        for i = 1, #obj do
            c[i] = serialize (obj[i])
        end
        return tconcat (c)
    end
end

---------------------------------------------------------------------
-- Serialize an object.
-- @param obj Table with the object to be serialized.
-- @return String with representation of the object.
---------------------------------------------------------------------
serialize = function (obj)
    local tt = type(obj)
    if tt == "string" then
        return escape(unescape(obj))
    elseif tt == "number" then
        return obj
    elseif tt == "table" then
        local t = obj.tag
        assert (t, "Invalid table format (no `tag' field)")
        return strformat ("<%s%s>%s</%s>", t, attrs(obj.attr), contents(obj), t)
    else
        return ""
    end
end

---------------------------------------------------------------------
-- Add header element (if it exists) to object.
-- Cleans old header element anyway.
---------------------------------------------------------------------
local header_template = {
    tag = "soap:Header",
}
local function insert_header (obj, header)
    -- removes old header
    if obj[2] then
        tremove (obj, 1)
    end
    if header then
        header_template[1] = header
        tinsert (obj, 1, header_template)
    end
end

local envelope_template = {
    tag = "soap:Envelope",
    attr = { "xmlns:soap", "soap:encodingStyle", "xmlns:xsi", "xmlns:xsd",
        ["xmlns:soap"] = nil, -- to be filled
        ["soap:encodingStyle"] = "http://schemas.xmlsoap.org/soap/encoding/",
        ["xmlns:xsi"] = "http://www.w3.org/2001/XMLSchema-instance",
        ["xmlns:xsd"] = "http://www.w3.org/2001/XMLSchema",
    },
    {
        tag = "soap:Body",
        [1] = {
            tag = nil, -- must be filled
            attr = {}, -- must be filled
        },
    }
}
local xmlns_soap = "http://schemas.xmlsoap.org/soap/envelope/"
local xmlns_soap12 = "http://www.w3.org/2003/05/soap-envelope"

---------------------------------------------------------------------
-- Converts a LuaExpat table into a SOAP message.
-- @param args Table with the arguments, which could be:
-- namespace: String with the namespace of the elements.
-- method: String with the method's name;
-- entries: Table of SOAP elements (LuaExpat's format);
-- header: Table describing the header of the SOAP envelope (optional);
-- internal_namespace: String with the optional namespace used
--	as a prefix for the method name (default = "");
-- soapversion: Number of SOAP version (default = 1.1);
-- @return String with SOAP envelope element.
---------------------------------------------------------------------
local function encode (args)
    if tonumber(args.soapversion) == 1.2 then
        envelope_template.attr["xmlns:soap"] = xmlns_soap12
    else
        envelope_template.attr["xmlns:soap"] = xmlns_soap
    end
    local xmlns = "xmlns"
    if args.internal_namespace then
        xmlns = xmlns..":"..args.internal_namespace
        args.method = args.internal_namespace..":"..args.method
    end
    -- Cleans old header and insert a new one (if it exists).
    insert_header (envelope_template, args.header)
    -- Sets new body contents (and erase old content).
    local body = (envelope_template[2] and envelope_template[2][1]) or envelope_template[1][1]
    for i = 1, max (#body, #args.entries) do
        body[i] = args.entries[i]
    end
    -- Sets method (actually, the table's tag) and namespace.
    body.tag = args.method
    body.attr[xmlns] = args.namespace
    return serialize (envelope_template)
end

local function skip(parser)
    local depth = 1
    while depth ~= 0 do
        local next = parser:next()
        if next == XmlPullParser.END_TAG then
            depth = depth - 1
        elseif next == XmlPullParser.START_TAG then
            depth = depth + 1
        end
    end
end

local function list_children (parser)

    local children = {}
    while parser:next() ~= XmlPullParser.END_TAG do
        if parser:getEventType() == XmlPullParser.TEXT then
            if not parser:isWhitespace() then
                local child = parser:getText();
                tinsert(children, child)
            end
        elseif parser:getEventType() == XmlPullParser.START_TAG then
            local attrs = {}
            local has_attrs = false
            for i=0,(parser:getAttributeCount()-1) do
                has_attrs = true
                local attr_name = parser:getAttributeName(i)
                if parser:getAttributePrefix(i) ~= nil then
                    attr_name = parser:getAttributePrefix(i) .. ":" .. attr_name
                end
                attrs[attr_name] = parser:getAttributeValue(i)
            end
            local tag = parser:getName()
            local child = list_children(parser)
            child.tag = tag
            if has_attrs then
                child.attr = attrs
            end
            tinsert(children, child)

        end
    end
    return children
end

local function decode (parser)
    parser:nextTag()
    local tag = parser:getName()
    parser:require(XmlPullParser.START_TAG, nil, "Envelope")

    local ret = {}
    parser:nextTag()
    tag = parser:getName()
    if tag == "Header" then
        ret.header = list_children (parser)
        parser:nextTag()
    end
    parser:require(XmlPullParser.START_TAG, nil, "Body")
    parser:nextTag()
    ret.method = parser:getName()
    ret.namespace = parser:getNamespace()

    ret.entries = list_children (parser)

    return ret

end

local mandatory_soapaction = "Field `soapaction' is mandatory for SOAP 1.1 (or you can force SOAP version with `soapversion' field)"
local invalid_args = "Supported SOAP versions: 1.1 and 1.2.  The presence of soapaction field is mandatory for SOAP version 1.1.\nsoapversion, soapaction = "


SOAP = newClass()

function SOAP:_init(url)
    self.xmlParserFactory = XmlPullParserFactory:newInstance()
    self.xmlParserFactory:setNamespaceAware(true)
    self.url = URL:new(url)
end

function SOAP:call(args)

    local soap_action, content_type_header
    if (not args.soapversion) or tonumber(args.soapversion) == 1.1 then
        soap_action = '"'..assert(args.soapaction, mandatory_soapaction)..'"'
        content_type_header = "text/xml"
    elseif tonumber(args.soapversion) == 1.2 then
        soap_action = nil
        content_type_header = "application/soap+xml"
    else
        assert(false, invalid_args..tostring(args.soapversion)..", "..tostring(args.soapaction))
    end

    local data = '<?xml version="1.0" encoding="UTF-8"?>' .. encode(args)
    local datastr = jlua.getClass("java.lang.String"):new(data)
    local databytes = datastr:getBytes(jlua.getClass("java.nio.charset.Charset"):forName("UTF-8"))

    local conn = self.url:openConnection()
    conn:setDoOutput( true )
    conn:setInstanceFollowRedirects( true )
    conn:setRequestMethod( "POST" )
    conn:setRequestProperty( "Content-Type", content_type_header .. ";charset=UTF-8")
    conn:setRequestProperty( "Content-Length", tostring(databytes.length))
    if soap_action ~= nil then
        conn:setRequestProperty( "SOAPAction", soap_action)
    end
    conn:setUseCaches( false )
    local wr = DataOutputStream:new(conn:getOutputStream())
    wr:write(databytes)

    local is = conn:getInputStream()

    local pullParser = self.xmlParserFactory:newPullParser()

    pullParser:setInput(is, nil)


    return decode(pullParser)

end

function SOAP.findTag(data, tag)
    for _, item in ipairs(data) do
        if item.tag == tag then
            return item
        end
    end
    return nil
end