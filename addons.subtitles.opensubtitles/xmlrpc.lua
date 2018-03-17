
require("Classes")

local format, gsub, strfind, strsub = string.format, string.gsub, string.find, string.sub
local concat, tinsert = table.concat, table.insert
local ceil = math.ceil

local XmlPullParser = jlua.getClass("org.xmlpull.v1.XmlPullParser")
local XmlPullParserFactory = jlua.getClass("org.xmlpull.v1.XmlPullParserFactory")
local URL = jlua.getClass("java.net.URL")
local DataOutputStream = jlua.getClass("java.io.DataOutputStream")

---------------------------------------------------------------------
-- Convert a Lua Object into an XML-RPC string.
---------------------------------------------------------------------

---------------------------------------------------------------------
local formats = {
    boolean = "<boolean>%d</boolean>",
    number = "<double>%d</double>",
    string = "<string>%s</string>",

    array = "<array><data>\n%s\n</data></array>",
    double = "<double>%s</double>",
    int = "<int>%s</int>",
    struct = "<struct>%s</struct>",

    member = "<member><name>%s</name>%s</member>",
    value = "<value>%s</value>",

    param = "<param>%s</param>",

    params = [[
    <params>
      %s
    </params>]],

    methodCall = [[<?xml version="1.0"?>
    <methodCall>
      <methodName>%s</methodName>
      %s
    </methodCall>
    ]],

}
formats.table = formats.struct

local toxml = {}
toxml.double = function (v,t) return format (formats.double, v) end
toxml.int = function (v,t) return format (formats.int, v) end
toxml.string = function (v,t) return format (formats.string, v) end

---------------------------------------------------------------------
-- Build a XML-RPC representation of a boolean.
-- @param v Object.
-- @return String.
---------------------------------------------------------------------
function toxml.boolean (v)
    local n = (v and 1) or 0
    return format (formats.boolean, n)
end

---------------------------------------------------------------------
-- Build a XML-RPC representation of a number.
-- @param v Object.
-- @param t Object representing the XML-RPC type of the value.
-- @return String.
---------------------------------------------------------------------
function toxml.number (v, t)
    local tt = (type(t) == "table") and t["*type"]
    if tt == "int" or tt == "i4" then
        return toxml.int (v, t)
    elseif tt == "double" then
        return toxml.double (v, t)
    elseif v == ceil(v) then
        return toxml.int (v, t)
    else
        return toxml.double (v, t)
    end
end

---------------------------------------------------------------------
-- @param typ Object representing a type.
-- @return Function that generate an XML element of the given type.
-- The object could be a string (as usual in Lua) or a table with
-- a field named "type" that should be a string with the XML-RPC
-- type name.
---------------------------------------------------------------------
local function format_func (typ)
    if type (typ) == "table" then
        return toxml[typ.type]
    else
        return toxml[typ]
    end
end

---------------------------------------------------------------------
-- @param val Object representing an array of values.
-- @param typ Object representing the type of the value.
-- @return String representing the equivalent XML-RPC value.
---------------------------------------------------------------------
function toxml.array (val, typ)
    local ret = {}
    local et = typ.elemtype
    local f = format_func (et)
    for i,v in ipairs (val) do
        if et and et ~= "array" then
            tinsert (ret, format (formats.value, f (v, et)))
        else
            local ct,cv = type_val(v)
            local cf = format_func(ct)
            tinsert (ret, format (formats.value, cf(cv, ct)))
        end

    end
    return format (formats.array, concat (ret, '\n'))
end

---------------------------------------------------------------------
---------------------------------------------------------------------
function toxml.struct (val, typ)
    local ret = {}
    if type (typ) == "table" then
        for n,t in pairs (typ.elemtype) do
            local f = format_func (t)
            tinsert (ret, format (formats.member, n, f (val[n], t)))
        end
    else
        for i, v in pairs (val) do
            tinsert (ret, toxml.member (i, v))
        end
    end
    return format (formats.struct, concat (ret))
end

toxml.table = toxml.struct

---------------------------------------------------------------------
---------------------------------------------------------------------
function toxml.member (n, v)
    return format (formats.member, n, toxml.value (v))
end

---------------------------------------------------------------------
-- Get type and value of object.
---------------------------------------------------------------------
function type_val (obj)
    local t = type (obj)
    local v = obj
    if t == "table" then
        t = obj["*type"] or "table"
        v = obj["*value"] or obj
    end
    return t, v
end

---------------------------------------------------------------------
-- Convert a Lua object to a XML-RPC object (plain string).
---------------------------------------------------------------------
function toxml.value (obj)
    local to, val = type_val (obj)
    if type(to) == "table" then
        return format (formats.value, toxml[to.type] (val, to))
    else
        -- primitive (not structured) types.
        --return format (formats[to], val)
        return format (formats.value, toxml[to] (val, to))
    end
end

---------------------------------------------------------------------
-- @param ... List of parameters.
-- @return String representing the `params' XML-RPC element.
---------------------------------------------------------------------
function toxml.params (...)
    local params_list = {}
    for i = 1, select ("#", ...) do
        params_list[i] = format (formats.param, toxml.value (select (i, ...)))
    end
    return format (formats.params, concat (params_list, '\n      '))
end

---------------------------------------------------------------------
-- @param method String with method's name.
-- @param ... List of parameters.
-- @return String representing the `methodCall' XML-RPC element.
---------------------------------------------------------------------
function toxml.methodCall (method, ...)
    local idx = strfind (method, "[^A-Za-z_.:/0-9]")
    if idx then
        error (format ("Invalid character `%s'", strsub (method, idx, idx)))
    end
    return format (formats.methodCall, method, toxml.params (...))
end

local function deserialize(parser)
    parser:require(XmlPullParser.START_TAG, nil, "value")

    if parser:isEmptyElementTag() then
        return ""
    end

    local obj = ""
    local hasType = true
    local typeNodeName = nil

    jlua.try(function()
            parser:nextTag()
            typeNodeName = parser:getName()
            if typeNodeName == "value" and parser:getEventType() == XmlPullParser.END_TAG then
                return ""
            end
        end, function(e)
            hasType = false
        end)

    if hasType then
        if typeNodeName == "int" or typeNodeName == "i4" or typeNodeName == "i8" or typeNodeName == "double" then
            obj = tonumber(parser:nextText())
        elseif typeNodeName == "boolean" then
            obj = (parser:nextText() == "1")
        elseif typeNodeName == "string" then
            obj = parser:nextText()
        elseif typeNodeName == "array" then
            parser:nextTag() -- <data>
            parser:require(XmlPullParser.START_TAG, nil, "data")
            parser:nextTag()
            obj = {}
            while parser:getName() == "value" do
                tinsert(obj, deserialize(parser))
                parser:nextTag()
            end
            parser:require(XmlPullParser.END_TAG, nil, "data")
            parser:nextTag() -- </array>
            parser:require(XmlPullParser.END_TAG, nil, "array")
        elseif typeNodeName == "struct" then
            parser:nextTag()
            obj = {}
            while parser:getName() == "member" do
                local memberName = nil
                local memberValue = nil
                while true do
                    parser:nextTag()
                    local name = parser:getName()
                    if name == "name" then
                        memberName = parser:nextText()
                    elseif name == "value" then
                        memberValue = deserialize(parser)
                    else
                        break
                    end
                end
                if memberName ~= nil and memberValue ~= nil then
                    obj[memberName] = memberValue
                end
                parser:require(XmlPullParser.END_TAG, nil, "member")
                parser:nextTag()
            end
            parser:require(XmlPullParser.END_TAG, nil, "struct")

        else
            obj = parser:nextText()
        end
    else
        obj = parser:getText()
    end

    parser:nextTag()
    parser:require(XmlPullParser.END_TAG, nil, "value")
    return obj

end

XMLRPC = newClass()

function XMLRPC:_init(url)
    self.xmlParserFactory = XmlPullParserFactory:newInstance()
    self.url = URL:new(url)
end

function XMLRPC:call(method, ...)
    local data = toxml.methodCall(method, ...)
    local datastr = jlua.getClass("java.lang.String"):new(data)
    local databytes = datastr:getBytes(jlua.getClass("java.nio.charset.Charset"):forName("UTF-8"))

    local conn = self.url:openConnection()
    conn:setConnectTimeout(5000)
    conn:setReadTimeout(5000)
    conn:setDoOutput( true )
    conn:setInstanceFollowRedirects( true )
    conn:setRequestMethod( "POST" )
    conn:setRequestProperty( "Content-Type", "text/xml;charset=UTF-8")
    conn:setRequestProperty( "Content-Length", tostring(databytes.length))
    conn:setUseCaches( false )
    local wr = DataOutputStream:new(conn:getOutputStream())
    wr:write(databytes)


    local is = conn:getInputStream()

    local pullParser = self.xmlParserFactory:newPullParser()

    pullParser:setInput(is, nil)

    pullParser:nextTag()
    pullParser:require(XmlPullParser.START_TAG, nil, "methodResponse")
    pullParser:nextTag()
    local tag = pullParser:getName()
    if tag == "params" then
        pullParser:nextTag() -- <param>
        pullParser:require(XmlPullParser.START_TAG, nil, "param")
        pullParser:nextTag() -- <value>
        local obj = deserialize(pullParser)
        return obj
    elseif tag == "fault" then
        pullParser:nextTag() -- <value>
        local obj = deserialize(pullParser)
        local faultString = obj["faultString"]
        local faultCode = obj["faultCode"]
        jlua.throw(faultString .. " (" .. faultCode .. ")")
    else
        jlua.throw("Bad tag <" .. tag .. ">.")
    end

end

---------------------------------------------------------------------
-- Create a representation of an array with the given element type.
---------------------------------------------------------------------
function XMLRPC.newArrayType (elemtype)
    return { type = "array", elemtype = elemtype, }
end

---------------------------------------------------------------------
-- Create a representation of a structure with the given members.
---------------------------------------------------------------------
function XMLRPC.newStructType (members)
    return { type = "struct", elemtype = members, }
end

---------------------------------------------------------------------
-- Create a representation of a value according to a type.
-- @param val Any Lua value.
-- @param typ A XML-RPC type.
---------------------------------------------------------------------
function XMLRPC.newTypedValue (val, typ)
    return { ["*type"] = typ, ["*value"] = val }
end

