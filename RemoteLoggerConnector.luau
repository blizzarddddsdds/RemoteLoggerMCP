--!native
-- SimpleSpy Console-Only Version
-- Remote spy with all GUI removed, console output only

if getgenv().SimpleSpyExecuted and type(getgenv().SimpleSpyShutdown) == "function" then
    getgenv().SimpleSpyShutdown()
end
getgenv().SimpleSpyExecuted = nil

local realconfigs = {
    logcheckcaller = false,
    autoblock = false,
    funcEnabled = true,
    advancedinfo = false,
}

local configs = newproxy(true)
local configsmetatable = getmetatable(configs)

configsmetatable.__index = function(self, index)
    return realconfigs[index]
end

configsmetatable.__newindex = function(self, index, newindex)
    realconfigs[index] = newindex
end

local oth = syn and syn.oth
local unhook = oth and oth.unhook
local hook = oth and oth.hook

local lower = string.lower
local byte = string.byte
local round = math.round
local running = coroutine.running
local resume = coroutine.resume
local status = coroutine.status
local yield = coroutine.yield
local create = coroutine.create
local close = coroutine.close
local OldDebugId = game.GetDebugId
local info = debug.info

local IsA = game.IsA
local tostring = tostring
local tonumber = tonumber
local delay = task.delay
local spawn = task.spawn
local clear = table.clear
local clone = table.clone

local function blankfunction(...)
    return ...
end

local get_thread_identity = (syn and syn.get_thread_identity) or getidentity or getthreadidentity
local set_thread_identity = (syn and syn.set_thread_identity) or setidentity
local islclosure = islclosure or is_l_closure
local threadfuncs = (get_thread_identity and set_thread_identity and true) or false

local getinfo = getinfo or blankfunction
local getupvalues = getupvalues or debug.getupvalues or blankfunction
local getconstants = getconstants or debug.getconstants or blankfunction

local getcustomasset = getsynasset or getcustomasset
local getcallingscript = getcallingscript or blankfunction
local newcclosure = newcclosure or blankfunction
local clonefunction = clonefunction or blankfunction
local cloneref = cloneref or blankfunction
local request = request or syn and syn.request
local makewritable = makewriteable or function(tbl)
    setreadonly(tbl, false)
end
local makereadonly = makereadonly or function(tbl)
    setreadonly(tbl, true)
end
local isreadonly = isreadonly or table.isfrozen

local hookmetamethod = hookmetamethod or (makewriteable and makereadonly and getrawmetatable) and function(obj: object, metamethod: string, func: Function)
    local old = getrawmetatable(obj)
    if hookfunction then
        return hookfunction(old[metamethod], func)
    else
        local oldmetamethod = old[metamethod]
        makewriteable(old)
        old[metamethod] = func
        makereadonly(old)
        return oldmetamethod
    end
end

local function SafeGetService(service)
    return cloneref(game:GetService(service))
end

local function IsCyclicTable(tbl)
    local checkedtables = {}
    local function SearchTable(tbl)
        table.insert(checkedtables, tbl)
        for i, v in next, tbl do
            if type(v) == "table" then
                return table.find(checkedtables, v) and true or SearchTable(v)
            end
        end
    end
    return SearchTable(tbl)
end

local function deepclone(args: table, copies: table): table
    local copy = nil
    copies = copies or {}
    if type(args) == 'table' then
        if copies[args] then
            copy = copies[args]
        else
            copy = {}
            copies[args] = copy
            for i, v in next, args do
                copy[deepclone(i, copies)] = deepclone(v, copies)
            end
        end
    elseif typeof(args) == "Instance" then
        copy = cloneref(args)
    else
        copy = args
    end
    return copy
end

local function rawtostring(userdata)
    if type(userdata) == "table" or typeof(userdata) == "userdata" then
        local rawmetatable = getrawmetatable(userdata)
        local cachedstring = rawmetatable and rawget(rawmetatable, "__tostring")
        if cachedstring then
            local wasreadonly = isreadonly(rawmetatable)
            if wasreadonly then
                makewritable(rawmetatable)
            end
            rawset(rawmetatable, "__tostring", nil)
            local safestring = tostring(userdata)
            rawset(rawmetatable, "__tostring", cachedstring)
            if wasreadonly then
                makereadonly(rawmetatable)
            end
            return safestring
        end
    end
    return tostring(userdata)
end

local Players = SafeGetService("Players")
local RunService = SafeGetService("RunService")
local http = SafeGetService("HttpService")

local function jsone(str) return http:JSONEncode(str) end
local function jsond(str)
    local suc, err = pcall(http.JSONDecode, http, str)
    return suc and err or suc
end

-- Load external dependencies
local LazyFix = loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/refs/heads/main/SimpleSpyV3/DataToCode.lua"))()

-- State variables
local indent = 4
local scheduled = {}
local schedulerconnect
local topstr = ""
local bottomstr = ""
local getnilrequired = false
local prevTables = {}
local toggle = false

-- Data storage
local logs = {}
local blacklist = {}
local blocklist = {}
local generation = {}
local running_threads = {}
local originalnamecall

-- autoblock variables
local history = {}
local excluding = {}

-- Storage instances
local remoteEvent = Instance.new("RemoteEvent")
local unreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
local remoteFunction = Instance.new("RemoteFunction")
local GetDebugIdHandler = Instance.new("BindableFunction")

local originalEvent = remoteEvent.FireServer
local originalUnreliableEvent = unreliableRemoteEvent.FireServer
local originalFunction = remoteFunction.InvokeServer
local GetDebugIDInvoke = GetDebugIdHandler.Invoke

function GetDebugIdHandler.OnInvoke(obj: Instance)
    return OldDebugId(obj)
end

local function ThreadGetDebugId(obj: Instance): string
    return GetDebugIDInvoke(GetDebugIdHandler, obj)
end

local synv3 = false

if syn and identifyexecutor then
    local _, version = identifyexecutor()
    if (version and version:sub(1, 2) == 'v3') then
        synv3 = true
    end
end

-- Config persistence
xpcall(function()
    if isfile and readfile and isfolder and makefolder then
        local cachedconfigs = isfile("SimpleSpy//Settings.json") and jsond(readfile("SimpleSpy//Settings.json"))
        if cachedconfigs then
            for i, v in next, realconfigs do
                if cachedconfigs[i] == nil then
                    cachedconfigs[i] = v
                end
            end
            realconfigs = cachedconfigs
        end
        if not isfolder("SimpleSpy") then
            makefolder("SimpleSpy")
        end
        if not isfile("SimpleSpy//Settings.json") then
            writefile("SimpleSpy//Settings.json", jsone(realconfigs))
        end
        configsmetatable.__newindex = function(self, index, newindex)
            realconfigs[index] = newindex
            writefile("SimpleSpy//Settings.json", jsone(realconfigs))
        end
    end
end, function(err)
    warn("[SimpleSpy] Config error: " .. tostring(err))
end)

local function logthread(thread: thread)
    table.insert(running_threads, thread)
end

-- Prevents remote spam from causing lag
function clean()
    local max = getgenv().SIMPLESPYCONFIG_MaxRemotes or 500
    if #logs > max then
        local newLogs = {}
        for i = 1, math.min(100, #logs) do
            table.insert(newLogs, logs[i])
        end
        logs = newLogs
    end
end

local function ThreadIsNotDead(thread: thread): boolean
    return not status(thread) == "dead"
end

-- Helper: build arg types summary string like "[string, number, Instance<Part>, CFrame, bool]"
local function getArgTypes(args)
    if not args or #args == 0 then return "[]" end
    local types = {}
    for i = 1, #args do
        local v = args[i]
        local t = typeof(v)
        if t == "Instance" then
            local ok, cn = pcall(function() return v.ClassName end)
            types[i] = ok and ("Instance<" .. cn .. ">") or "Instance"
        elseif t == "table" then
            types[i] = "table(" .. #v .. ")"
        elseif t == "string" then
            if #v > 40 then
                types[i] = 'string("' .. v:sub(1, 37) .. '...")'
            else
                types[i] = 'string("' .. v .. '")'
            end
        elseif t == "number" then
            types[i] = "number(" .. tostring(v) .. ")"
        elseif t == "boolean" then
            types[i] = "bool(" .. tostring(v) .. ")"
        elseif t == "nil" then
            types[i] = "nil"
        else
            types[i] = t
        end
    end
    return "[" .. table.concat(types, ", ") .. "]"
end

-- Helper: walk the call stack and build a trace string
-- In Roblox Luau, debug.info(level, "sln") returns: source, line, name
local function getStackTrace(startLevel)
    local stack = {}
    local level = startLevel or 3
    for i = 1, 12 do
        local ok, src, line, name = pcall(info, level, "sln")
        if not ok or not src then break end
        local entry = tostring(src) .. ":" .. tostring(line or "?")
        if name and name ~= "" then
            entry = entry .. " (" .. name .. ")"
        end
        stack[#stack + 1] = entry
        level = level + 1
    end
    if #stack == 0 then return "" end
    return table.concat(stack, " > ")
end

-- Helper: safely serialize a return value for logging
local function safeSerializeReturnValue(results)
    if not results or #results == 0 then return "nil" end
    local parts = {}
    for i = 1, math.min(#results, 10) do
        local v = results[i]
        local t = typeof(v)
        local ok, str = pcall(function()
            if t == "Instance" then
                return "Instance<" .. v.ClassName .. ">(" .. v:GetFullName() .. ")"
            elseif t == "table" then
                local hs = game:GetService("HttpService")
                local s, j = pcall(function() return hs:JSONEncode(v) end)
                if s and #j < 200 then return j end
                return "table(" .. #v .. " entries)"
            elseif t == "string" then
                if #v > 100 then return '"' .. v:sub(1, 97) .. '..."' end
                return '"' .. v .. '"'
            elseif t == "boolean" or t == "number" then
                return tostring(v)
            elseif v == nil then
                return "nil"
            else
                return t .. "(" .. tostring(v) .. ")"
            end
        end)
        parts[i] = ok and str or (t .. "(?)")
    end
    if #results > 10 then parts[#parts + 1] = "..." end
    return table.concat(parts, ", ")
end

-- Scheduling system
function schedule(f, ...)
    table.insert(scheduled, {f, ...})
end

function scheduleWait()
    local thread = running()
    schedule(function()
        resume(thread)
    end)
    yield()
end

local function taskscheduler()
    if not toggle then
        scheduled = {}
        return
    end
    if #scheduled > (getgenv().SIMPLESPYCONFIG_MaxRemotes or 500) + 100 then
        table.remove(scheduled, #scheduled)
    end
    if #scheduled > 0 then
        local currentf = scheduled[1]
        table.remove(scheduled, 1)
        if type(currentf) == "table" and type(currentf[1]) == "function" then
            pcall(unpack(currentf))
        end
    end
end

local function tablecheck(tabletocheck, instance, id)
    return tabletocheck[id] or tabletocheck[instance.Name]
end

-------------------------------------------------------------------------------
-- SERIALIZATION SYSTEM
-------------------------------------------------------------------------------

local CustomGeneration = {
    Vector3 = (function()
        local temp = {}
        for i, v in Vector3 do
            if type(v) == "vector" then
                temp[v] = `Vector3.{i}`
            end
        end
        return temp
    end)(),
    Vector2 = (function()
        local temp = {}
        for i, v in Vector2 do
            if type(v) == "userdata" then
                temp[v] = `Vector2.{i}`
            end
        end
        return temp
    end)(),
    CFrame = {
        [CFrame.identity] = "CFrame.identity"
    }
}

local number_table = {
    ["inf"] = "math.huge",
    ["-inf"] = "-math.huge",
    ["nan"] = "0/0"
}

local ufunctions
ufunctions = {
    TweenInfo = function(u)
        return `TweenInfo.new({u.Time}, {u.EasingStyle}, {u.EasingDirection}, {u.RepeatCount}, {u.Reverses}, {u.DelayTime})`
    end,
    Ray = function(u)
        local Vector3tostring = ufunctions["Vector3"]
        return `Ray.new({Vector3tostring(u.Origin)}, {Vector3tostring(u.Direction)})`
    end,
    BrickColor = function(u)
        return `BrickColor.new({u.Number})`
    end,
    NumberRange = function(u)
        return `NumberRange.new({u.Min}, {u.Max})`
    end,
    Region3 = function(u)
        local center = u.CFrame.Position
        local centersize = u.Size / 2
        local Vector3tostring = ufunctions["Vector3"]
        return `Region3.new({Vector3tostring(center - centersize)}, {Vector3tostring(center + centersize)})`
    end,
    Faces = function(u)
        local faces = {}
        if u.Top then table.insert(faces, "Top") end
        if u.Bottom then table.insert(faces, "Enum.NormalId.Bottom") end
        if u.Left then table.insert(faces, "Enum.NormalId.Left") end
        if u.Right then table.insert(faces, "Enum.NormalId.Right") end
        if u.Back then table.insert(faces, "Enum.NormalId.Back") end
        if u.Front then table.insert(faces, "Enum.NormalId.Front") end
        return `Faces.new({table.concat(faces, ", ")})`
    end,
    EnumItem = function(u)
        return tostring(u)
    end,
    Enums = function(u)
        return "Enum"
    end,
    Enum = function(u)
        return `Enum.{u}`
    end,
    Vector3 = function(u)
        return CustomGeneration.Vector3[u] or `Vector3.new({u})`
    end,
    Vector2 = function(u)
        return CustomGeneration.Vector2[u] or `Vector2.new({u})`
    end,
    CFrame = function(u)
        return CustomGeneration.CFrame[u] or `CFrame.new({table.concat({u:GetComponents()}, ", ")})`
    end,
    PathWaypoint = function(u)
        return `PathWaypoint.new({ufunctions["Vector3"](u.Position)}, {u.Action}, "{u.Label}")`
    end,
    UDim = function(u)
        return `UDim.new({u})`
    end,
    UDim2 = function(u)
        return `UDim2.new({u})`
    end,
    Rect = function(u)
        local Vector2tostring = ufunctions["Vector2"]
        return `Rect.new({Vector2tostring(u.Min)}, {Vector2tostring(u.Max)})`
    end,
    Color3 = function(u)
        return `Color3.new({u.R}, {u.G}, {u.B})`
    end,
    RBXScriptSignal = function(u)
        return "RBXScriptSignal --[[not supported]]"
    end,
    RBXScriptConnection = function(u)
        return "RBXScriptConnection --[[not supported]]"
    end,
}

local typeofv2sfunctions = {
    number = function(v)
        local number = tostring(v)
        return number_table[number] or number
    end,
    boolean = function(v)
        return tostring(v)
    end,
    string = function(v, l)
        return formatstr(v, l)
    end,
    ["function"] = function(v)
        return f2s(v)
    end,
    table = function(v, l, p, n, vtv, i, pt, path, tables, tI)
        return t2s(v, l, p, n, vtv, i, pt, path, tables, tI)
    end,
    Instance = function(v)
        local DebugId = OldDebugId(v)
        return i2p(v, generation[DebugId])
    end,
    userdata = function(v)
        if configs.advancedinfo then
            if getrawmetatable(v) then
                return "newproxy(true)"
            end
            return "newproxy(false)"
        end
        return "newproxy(true)"
    end
}

local typev2sfunctions = {
    userdata = function(v, vtypeof)
        if ufunctions[vtypeof] then
            return ufunctions[vtypeof](v)
        end
        return `{vtypeof}({rawtostring(v)}) --[[Generation Failure]]`
    end,
    vector = ufunctions["Vector3"]
}

function v2s(v, l, p, n, vtv, i, pt, path, tables, tI)
    local vtypeof = typeof(v)
    local vtypeoffunc = typeofv2sfunctions[vtypeof]
    local vtypefunc = typev2sfunctions[type(v)]
    local vtype = type(v)
    if not tI then
        tI = {0}
    else
        tI[1] += 1
    end
    if vtypeoffunc then
        return vtypeoffunc(v, l, p, n, vtv, i, pt, path, tables, tI)
    elseif vtypefunc then
        return vtypefunc(v, vtypeof)
    end
    return `{vtypeof}({rawtostring(v)}) --[[Generation Failure]]`
end

function v2v(t)
    topstr = ""
    bottomstr = ""
    getnilrequired = false
    local ret = ""
    local count = 1
    for i, v in next, t do
        if type(i) == "string" and i:match("^[%a_]+[%w_]*$") then
            ret = ret .. "local " .. i .. " = " .. v2s(v, nil, nil, i, true) .. "\n"
        elseif rawtostring(i):match("^[%a_]+[%w_]*$") then
            ret = ret .. "local " .. lower(rawtostring(i)) .. "_" .. rawtostring(count) .. " = " .. v2s(v, nil, nil, lower(rawtostring(i)) .. "_" .. rawtostring(count), true) .. "\n"
        else
            ret = ret .. "local " .. type(v) .. "_" .. rawtostring(count) .. " = " .. v2s(v, nil, nil, type(v) .. "_" .. rawtostring(count), true) .. "\n"
        end
        count = count + 1
    end
    if getnilrequired then
        topstr = "function getNil(name,class) for _,v in next, getnilinstances() do if v.ClassName==class and v.Name==name then return v;end end end\n" .. topstr
    end
    if #topstr > 0 then
        ret = topstr .. "\n" .. ret
    end
    if #bottomstr > 0 then
        ret = ret .. bottomstr
    end
    return ret
end

function t2s(t, l, p, n, vtv, i, pt, path, tables, tI)
    local globalIndex = table.find(getgenv(), t)
    if type(globalIndex) == "string" then
        return globalIndex
    end
    if not tI then
        tI = {0}
    end
    if not path then
        path = ""
    end
    if not l then
        l = 0
        tables = {}
    end
    if not p then
        p = t
    end
    for _, v in next, tables do
        if n and rawequal(v, t) then
            bottomstr = bottomstr .. "\n" .. rawtostring(n) .. rawtostring(path) .. " = " .. rawtostring(n) .. rawtostring(({v2p(v, p)})[2])
            return "{} --[[DUPLICATE]]"
        end
    end
    table.insert(tables, t)
    local s = "{"
    local size = 0
    l += indent
    for k, v in next, t do
        size = size + 1
        if size > (getgenv().SimpleSpyMaxTableSize or 1000) then
            s = s .. "\n" .. string.rep(" ", l) .. "-- MAXIMUM TABLE SIZE REACHED"
            break
        end
        if rawequal(k, t) then
            bottomstr ..= `\n{n}{path}[{n}{path}] = {(rawequal(v, k) and `{n}{path}` or v2s(v, l, p, n, vtv, k, t, `{path}[{n}{path}]`, tables))}`
            size -= 1
            continue
        end
        local currentPath = ""
        if type(k) == "string" and k:match("^[%a_]+[%w_]*$") then
            currentPath = "." .. k
        else
            currentPath = "[" .. v2s(k, l, p, n, vtv, k, t, path .. currentPath, tables, tI) .. "]"
        end
        if size % 100 == 0 then
            scheduleWait()
        end
        s = s .. "\n" .. string.rep(" ", l) .. "[" .. v2s(k, l, p, n, vtv, k, t, path .. currentPath, tables, tI) .. "] = " .. v2s(v, l, p, n, vtv, k, t, path .. currentPath, tables, tI) .. ","
    end
    if #s > 1 then
        s = s:sub(1, #s - 1)
    end
    if size > 0 then
        s = s .. "\n" .. string.rep(" ", l - indent)
    end
    return s .. "}"
end

function f2s(f)
    for k, x in next, getgenv() do
        local isgucci, gpath
        if rawequal(x, f) then
            isgucci, gpath = true, ""
        elseif type(x) == "table" then
            isgucci, gpath = v2p(f, x)
        end
        if isgucci and type(k) ~= "function" then
            if type(k) == "string" and k:match("^[%a_]+[%w_]*$") then
                return k .. gpath
            else
                return "getgenv()[" .. v2s(k) .. "]" .. gpath
            end
        end
    end
    if configs.funcEnabled then
        local funcname = info(f, "n")
        if funcname and funcname:match("^[%a_]+[%w_]*$") then
            return `function {funcname}() end -- Function Called: {funcname}`
        end
    end
    return tostring(f)
end

function i2p(i, customgen)
    if customgen then
        return customgen
    end
    local player = getplayer(i)
    local parent = i
    local out = ""
    if parent == nil then
        return "nil"
    elseif player then
        while true do
            if parent and parent == player.Character then
                if player == Players.LocalPlayer then
                    return 'game:GetService("Players").LocalPlayer.Character' .. out
                else
                    return i2p(player) .. ".Character" .. out
                end
            else
                if parent.Name:match("[%a_]+[%w+]*") ~= parent.Name then
                    out = ':FindFirstChild(' .. formatstr(parent.Name) .. ')' .. out
                else
                    out = "." .. parent.Name .. out
                end
            end
            task.wait()
            parent = parent.Parent
        end
    elseif parent ~= game then
        while true do
            if parent and parent.Parent == game then
                if SafeGetService(parent.ClassName) then
                    if lower(parent.ClassName) == "workspace" then
                        return `workspace{out}`
                    else
                        return 'game:GetService("' .. parent.ClassName .. '")' .. out
                    end
                else
                    if parent.Name:match("[%a_]+[%w_]*") then
                        return "game." .. parent.Name .. out
                    else
                        return 'game:FindFirstChild(' .. formatstr(parent.Name) .. ')' .. out
                    end
                end
            elseif not parent.Parent then
                getnilrequired = true
                return 'getNil(' .. formatstr(parent.Name) .. ', "' .. parent.ClassName .. '")' .. out
            else
                if parent.Name:match("[%a_]+[%w_]*") ~= parent.Name then
                    out = ':WaitForChild(' .. formatstr(parent.Name) .. ')' .. out
                else
                    out = ':WaitForChild("' .. parent.Name .. '")' .. out
                end
            end
            if i:IsDescendantOf(Players.LocalPlayer) then
                return 'game:GetService("Players").LocalPlayer' .. out
            end
            parent = parent.Parent
            task.wait()
        end
    else
        return "game"
    end
end

function getplayer(instance)
    for _, v in next, Players:GetPlayers() do
        if v.Character and (instance:IsDescendantOf(v.Character) or instance == v.Character) then
            return v
        end
    end
end

function v2p(x, t, path, prev)
    if not path then
        path = ""
    end
    if not prev then
        prev = {}
    end
    if rawequal(x, t) then
        return true, ""
    end
    for i, v in next, t do
        if rawequal(v, x) then
            if type(i) == "string" and i:match("^[%a_]+[%w_]*$") then
                return true, (path .. "." .. i)
            else
                return true, (path .. "[" .. v2s(i) .. "]")
            end
        end
        if type(v) == "table" then
            local duplicate = false
            for _, y in next, prev do
                if rawequal(y, v) then
                    duplicate = true
                end
            end
            if not duplicate then
                table.insert(prev, t)
                local found
                found, p = v2p(x, v, path, prev)
                if found then
                    if type(i) == "string" and i:match("^[%a_]+[%w_]*$") then
                        return true, "." .. i .. p
                    else
                        return true, "[" .. v2s(i) .. "]" .. p
                    end
                end
            end
        end
    end
    return false, ""
end

function formatstr(s, indentation)
    if not indentation then
        indentation = 0
    end
    local handled, reachedMax = handlespecials(s, indentation)
    return '"' .. handled .. '"' .. (reachedMax and " --[[ MAXIMUM STRING SIZE REACHED ]]" or "")
end

local function isFinished(coroutines: table)
    for _, v in next, coroutines do
        if status(v) == "running" then
            return false
        end
    end
    return true
end

local specialstrings = {
    ["\n"] = function(thread, index)
        resume(thread, index, "\\n")
    end,
    ["\t"] = function(thread, index)
        resume(thread, index, "\\t")
    end,
    ["\\"] = function(thread, index)
        resume(thread, index, "\\\\")
    end,
    ['"'] = function(thread, index)
        resume(thread, index, '\\"')
    end
}

function handlespecials(s, indentation)
    local i = 0
    local n = 1
    local coroutines = {}
    local coroutineFunc = function(i, r)
        s = s:sub(0, i - 1) .. r .. s:sub(i + 1, -1)
    end
    local timeout = 0
    repeat
        i += 1
        if timeout >= 10 then
            task.wait()
            timeout = 0
        end
        local char = s:sub(i, i)
        if byte(char) then
            timeout += 1
            local c = create(coroutineFunc)
            table.insert(coroutines, c)
            local specialfunc = specialstrings[char]
            if specialfunc then
                specialfunc(c, i)
                i += 1
            elseif byte(char) > 126 or byte(char) < 32 then
                resume(c, i, "\\" .. byte(char))
                i += #rawtostring(byte(char))
            end
            if i >= n * 100 then
                local extra = string.format('" ..\n%s"', string.rep(" ", indentation + indent))
                s = s:sub(0, i) .. extra .. s:sub(i + 1, -1)
                i += #extra
                n += 1
            end
        end
    until char == "" or i > (getgenv().SimpleSpyMaxStringSize or 10000)
    while not isFinished(coroutines) do
        RunService.Heartbeat:Wait()
    end
    clear(coroutines)
    if i > (getgenv().SimpleSpyMaxStringSize or 10000) then
        s = string.sub(s, 0, getgenv().SimpleSpyMaxStringSize or 10000)
        return s, true
    end
    return s, false
end

-------------------------------------------------------------------------------
-- CODE GENERATION
-------------------------------------------------------------------------------

function genScript(remote, args)
    prevTables = {}
    local gen = ""
    if #args > 0 then
        xpcall(function()
            gen = "local args = " .. LazyFix.Convert(args, true) .. "\n"
        end, function(err)
            gen ..= "-- Error: " .. tostring(err) .. "\nlocal args = {}\n"
        end)
        if not remote:IsDescendantOf(game) and not getnilrequired then
            gen = "function getNil(name,class) for _,v in next, getnilinstances()do if v.ClassName==class and v.Name==name then return v;end end end\n\n" .. gen
        end
        if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
            gen ..= LazyFix.ConvertKnown("Instance", remote) .. ":FireServer(unpack(args))"
        elseif remote:IsA("RemoteFunction") then
            gen = gen .. LazyFix.ConvertKnown("Instance", remote) .. ":InvokeServer(unpack(args))"
        end
    else
        if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
            gen ..= LazyFix.ConvertKnown("Instance", remote) .. ":FireServer()"
        elseif remote:IsA("RemoteFunction") then
            gen ..= LazyFix.ConvertKnown("Instance", remote) .. ":InvokeServer()"
        end
    end
    prevTables = {}
    return gen
end

-------------------------------------------------------------------------------
-- REMOTE LOGGING (Console Only)
-------------------------------------------------------------------------------

function newRemote(type, data)
    local remote = data.remote
    local callingscript = data.callingscript

    local log = {
        Name = remote.Name,
        Remote = remote,
        args = data.args,
        method = data.method,
        Source = callingscript,
        infofunc = data.infofunc,
        timestamp = tick(),
        blocked = data.blockcheck,
        argTypes = data.argTypes or "",
        stackTrace = data.stackTrace or "",
        remoteClass = data.remoteClass or "",
        returnValue = data.returnValue or nil,
    }

    logs[#logs + 1] = log
    clean()
end

-------------------------------------------------------------------------------
-- HOOKING SYSTEM
-------------------------------------------------------------------------------

function remoteHandler(data)
    if configs.autoblock then
        local id = data.id
        if excluding[id] then
            return
        end
        if not history[id] then
            history[id] = {badOccurances = 0, lastCall = tick()}
        end
        if tick() - history[id].lastCall < 1 then
            history[id].badOccurances += 1
            return
        else
            history[id].badOccurances = 0
        end
        if history[id].badOccurances > 3 then
            excluding[id] = true
            return
        end
        history[id].lastCall = tick()
    end

    if (data.remote:IsA("RemoteEvent") or data.remote:IsA("UnreliableRemoteEvent")) and lower(data.method) == "fireserver" then
        newRemote("event", data)
    elseif data.remote:IsA("RemoteFunction") and lower(data.method) == "invokeserver" then
        newRemote("function", data)
    end
end

local newindex = function(method, originalfunction, ...)
    if typeof(...) == 'Instance' then
        local remote = cloneref(...)
        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") or remote:IsA("UnreliableRemoteEvent") then
            if not configs.logcheckcaller and checkcaller() then return originalfunction(...) end
            local id = ThreadGetDebugId(remote)
            local blockcheck = tablecheck(blocklist, remote, id)
            local args = {select(2, ...)}
            local pendingData = nil
            if not tablecheck(blacklist, remote, id) and not IsCyclicTable(args) then
                local data = {
                    method = method,
                    remote = remote,
                    args = deepclone(args),
                    infofunc = infofunc,
                    callingscript = callingscript,
                    metamethod = "__index",
                    blockcheck = blockcheck,
                    id = id,
                    argTypes = getArgTypes(args),
                    stackTrace = getStackTrace(3),
                    remoteClass = remote.ClassName,
                }
                args = nil
                if configs.funcEnabled then
                    data.infofunc = info(2, "f")
                    local calling = getcallingscript()
                    data.callingscript = calling and cloneref(calling) or nil
                end
                if not blockcheck and (lower(method) == "invokeserver") then
                    pendingData = data
                else
                    schedule(remoteHandler, data)
                end
            end
            if blockcheck then return end
            if pendingData then
                local results = {originalfunction(...)}
                pendingData.returnValue = safeSerializeReturnValue(results)
                schedule(remoteHandler, pendingData)
                return unpack(results)
            end
        end
    end
    return originalfunction(...)
end

local newnamecall = newcclosure(function(...)
    local method = getnamecallmethod()
    if method and (method == "FireServer" or method == "fireServer" or method == "InvokeServer" or method == "invokeServer") then
        if typeof(...) == 'Instance' then
            local remote = cloneref(...)
            if IsA(remote, "RemoteEvent") or IsA(remote, "RemoteFunction") or IsA(remote, "UnreliableRemoteEvent") then
                if not configs.logcheckcaller and checkcaller() then return originalnamecall(...) end
                local id = ThreadGetDebugId(remote)
                local blockcheck = tablecheck(blocklist, remote, id)
                local args = {select(2, ...)}
                local pendingData = nil
                if not tablecheck(blacklist, remote, id) and not IsCyclicTable(args) then
                    local data = {
                        method = method,
                        remote = remote,
                        args = deepclone(args),
                        infofunc = infofunc,
                        callingscript = callingscript,
                        metamethod = "__namecall",
                        blockcheck = blockcheck,
                        id = id,
                        argTypes = getArgTypes(args),
                        stackTrace = getStackTrace(3),
                        remoteClass = remote.ClassName,
                    }
                    args = nil
                    if configs.funcEnabled then
                        data.infofunc = info(2, "f")
                        local calling = getcallingscript()
                        if type(calling) == "userdata" then
                            data.callingscript = calling and cloneref(calling) or nil
                        end
                    end
                    if not blockcheck and (lower(method) == "invokeserver") then
                        pendingData = data
                    else
                        schedule(remoteHandler, data)
                    end
                end
                if blockcheck then return end
                if pendingData then
                    local results = {originalnamecall(...)}
                    pendingData.returnValue = safeSerializeReturnValue(results)
                    schedule(remoteHandler, pendingData)
                    return unpack(results)
                end
            end
        end
    end
    return originalnamecall(...)
end)

local newFireServer = newcclosure(function(...)
    return newindex("FireServer", originalEvent, ...)
end)

local newUnreliableFireServer = newcclosure(function(...)
    return newindex("FireServer", originalUnreliableEvent, ...)
end)

local newInvokeServer = newcclosure(function(...)
    return newindex("InvokeServer", originalFunction, ...)
end)

-- Initialize hooks (always on)
local function initHooks()
    local oldnamecall
    if synv3 then
        oldnamecall = hook(getrawmetatable(game).__namecall, clonefunction(newnamecall))
        originalEvent = hook(Instance.new("RemoteEvent").FireServer, clonefunction(newFireServer))
        originalFunction = hook(Instance.new("RemoteFunction").InvokeServer, clonefunction(newInvokeServer))
        originalUnreliableEvent = hook(Instance.new("UnreliableRemoteEvent").FireServer, clonefunction(newUnreliableFireServer))
    else
        if hookmetamethod then
            oldnamecall = hookmetamethod(game, "__namecall", clonefunction(newnamecall))
        else
            oldnamecall = hookfunction(getrawmetatable(game).__namecall, clonefunction(newnamecall))
        end
        originalEvent = hookfunction(Instance.new("RemoteEvent").FireServer, clonefunction(newFireServer))
        originalFunction = hookfunction(Instance.new("RemoteFunction").InvokeServer, clonefunction(newInvokeServer))
        originalUnreliableEvent = hookfunction(Instance.new("UnreliableRemoteEvent").FireServer, clonefunction(newUnreliableFireServer))
    end
    originalnamecall = originalnamecall or function(...)
        return oldnamecall(...)
    end
end

-------------------------------------------------------------------------------
-- MAIN INITIALIZATION
-------------------------------------------------------------------------------

if not getgenv().SimpleSpyExecuted then
    local succeeded, err = pcall(function()
        if not RunService:IsClient() then
            error("SimpleSpy cannot run on the server!")
        end

        -- Enable the spy (always on)
        initHooks()
        toggle = true

        -- Start scheduler
        schedulerconnect = RunService.Heartbeat:Connect(taskscheduler)

        -- Pre-cache common instance paths
        spawn(function()
            local lp = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() or Players.LocalPlayer
            generation = {
                [OldDebugId(lp)] = 'game:GetService("Players").LocalPlayer',
                [OldDebugId(lp:GetMouse())] = 'game:GetService("Players").LocalPlayer:GetMouse()',
                [OldDebugId(game)] = "game",
                [OldDebugId(workspace)] = "workspace"
            }
        end)
    end)

    if succeeded then
        getgenv().SimpleSpyExecuted = true
        getgenv().SimpleSpyShutdown = function()
            getgenv()._SimpleSpyMCPShuttingDown = true
            local ws = getgenv()._SimpleSpyMCPWebSocket
            if ws then
                pcall(function() ws:Close() end)
                getgenv()._SimpleSpyMCPWebSocket = nil
            end
            MCPHttpRunning = false
            if MCPWebSocket then
                MCPWebSocket = nil
            end
            -- Disconnect scheduler heartbeat
            if schedulerconnect then
                pcall(function() schedulerconnect:Disconnect() end)
                schedulerconnect = nil
            end
            -- Clear state
            getgenv().SimpleSpy = nil
            getgenv().SimpleSpyExecuted = nil
            getgenv().SimpleSpyShutdown = nil
        end
    else
        warn("[SimpleSpy] Error: " .. rawtostring(err))
        return
    end
else
    return
end

-------------------------------------------------------------------------------
-- EXPOSED API
-------------------------------------------------------------------------------

getgenv().SimpleSpy = {
    -- Data access
    logs = logs,
    blacklist = blacklist,
    blocklist = blocklist,

    -- Serialization functions
    genScript = genScript,
    v2s = v2s,
    t2s = t2s,
    i2p = i2p,
    f2s = f2s,
    v2v = v2v,
    v2p = v2p,
    formatstr = formatstr,

    -- Utilities
    deepclone = deepclone,
    rawtostring = rawtostring,

    -- Config
    configs = configs,

    -- Helper
    getNil = function(name, class)
        for _, v in next, getnilinstances() do
            if v.ClassName == class and v.Name == name then
                return v
            end
        end
    end
}

-------------------------------------------------------------------------------
-- MCP CONNECTOR
-- Connects to Remote Logger MCP server via WebSocket or HTTP polling
-------------------------------------------------------------------------------

local MCPBridgeURL = getgenv().RemoteLoggerBridgeURL or "localhost:16385"
local MCPBridgeSecret = (function()
    local g = getgenv and getgenv()
    if g and g.RemoteLoggerBridgeSecret and type(g.RemoteLoggerBridgeSecret) == "string" then return g.RemoteLoggerBridgeSecret end
    return nil
end)()
local MCPEnabled = getgenv().RemoteLoggerMCPEnabled ~= false -- Default true
local MCPWebSocket = nil
local MCPConnection = nil
local MCPHttpRunning = false
local MCP_WS_RETRIES = 3
local MCP_WS_RETRY_DELAY = 1.5
local MCP_WS_RECONNECT_DELAY = 2

-- Helper to safely serialize log data for MCP
local function serializeLogForMCP(log, index)
    local success, result = pcall(function()
        local sourcePath = "unknown"
        if log.Source then
            sourcePath = log.Source:GetFullName()
        end

        local generatedScript = ""
        if log.Remote and log.args then
            generatedScript = genScript(log.Remote, log.args)
        end

        -- Serialize function info
        -- log.infofunc comes from debug.info(2, "f") which returns the raw function in Roblox Luau
        local funcInfo = nil
        if log.infofunc then
            if type(log.infofunc) == "function" then
                local ok, fname, fsource, fline, fnparams, fisvararg = pcall(info, log.infofunc, "nsla")
                if ok then
                    funcInfo = {
                        name = tostring(fname or ""),
                        source = tostring(fsource or ""),
                        currentline = fline or 0,
                        numparams = fnparams or 0,
                        isvararg = fisvararg or false
                    }
                else
                    funcInfo = { name = "", source = "" }
                end
            elseif type(log.infofunc) == "table" then
                funcInfo = {
                    name = log.infofunc.name or "",
                    source = log.infofunc.source or "",
                    linedefined = log.infofunc.linedefined or 0,
                    currentline = log.infofunc.currentline or 0,
                    numparams = log.infofunc.numparams or 0,
                    isvararg = log.infofunc.isvararg or false
                }
            end
        end

        return {
            index = index,
            name = log.Name or "unknown",
            path = log.Remote and i2p(log.Remote) or "unknown",
            method = log.method or "unknown",
            argsCount = log.args and #log.args or 0,
            source = sourcePath,
            blocked = log.blocked or false,
            script = generatedScript,
            argTypes = log.argTypes or "",
            stackTrace = log.stackTrace or "",
            remoteClass = log.remoteClass or "",
            returnValue = log.returnValue or nil,
        }
    end)

    if success then
        return result
    else
        return {
            index = index,
            name = log.Name or "unknown",
            error = "Failed to serialize: " .. tostring(result)
        }
    end
end

-- Handle MCP commands
local function handleMCPCommand(data)
    local cmd = type(data) == "string" and jsond(data) or data
    if type(cmd) ~= "table" or not cmd.type then
        return { id = cmd.id, error = "Invalid command format", success = false }
    end

    local responseType = cmd.type
    local responseData = { id = cmd.id, success = true }

    if responseType == "get-remote-logs" then
        local limit = tonumber(cmd.limit) or 100
        limit = math.min(math.max(limit, 1), 500)

        local output = {}
        -- Index 1 = oldest (logs[1]), index N = newest (logs[N]); iterate oldest-first
        for i = 1, math.min(limit, #logs) do
            local serialized = serializeLogForMCP(logs[i], i)
            table.insert(output, serialized)
        end

        responseData.output = jsone(output)

    elseif responseType == "get-remote-log" then
        -- Get a specific log by index
        local idx = tonumber(cmd.index) or 1
        if logs[idx] then
            responseData.output = jsone(serializeLogForMCP(logs[idx], idx))
        else
            responseData.error = "Log index out of range"
            responseData.success = false
        end

    elseif responseType == "clear-remote-logs" then
        clear(logs)
        responseData.output = "Logs cleared"

    elseif responseType == "get-status" then
        responseData.output = jsone({
            enabled = true,
            logCount = #logs,
            connected = MCPWebSocket ~= nil or MCPHttpRunning,
            config = {
                logcheckcaller = realconfigs.logcheckcaller,
                autoblock = realconfigs.autoblock,
                funcEnabled = realconfigs.funcEnabled,
                advancedinfo = realconfigs.advancedinfo
            }
        })

    elseif responseType == "serialize-value" then
        -- Serialize any value to a string
        local value = cmd.value
        responseData.output = v2s(value)

    elseif responseType == "get-remote-path" then
        -- Get path of a remote by index
        local idx = tonumber(cmd.index) or 1
        if logs[idx] and logs[idx].Remote then
            responseData.output = i2p(logs[idx].Remote)
        else
            responseData.error = "Remote not found"
            responseData.success = false
        end

    elseif responseType == "get-calling-script" then
        -- Get calling script info for a log
        local idx = tonumber(cmd.index) or 1
        if logs[idx] then
            local log = logs[idx]
            local fInfo = nil
            if log.infofunc then
                if type(log.infofunc) == "function" then
                    local ok, fname, fsource, fline = pcall(info, log.infofunc, "nsl")
                    if ok then
                        fInfo = { name = tostring(fname or ""), source = tostring(fsource or ""), currentline = fline or 0 }
                    else
                        fInfo = { name = "", source = "" }
                    end
                elseif type(log.infofunc) == "table" then
                    fInfo = {
                        name = log.infofunc.name or "",
                        source = log.infofunc.source or "",
                        linedefined = log.infofunc.linedefined or 0,
                        currentline = log.infofunc.currentline or 0
                    }
                end
            end
            responseData.output = jsone({
                path = log.Source and log.Source:GetFullName() or "unknown",
                name = log.Source and log.Source.Name or "unknown",
                className = log.Source and log.Source.ClassName or "unknown",
                funcInfo = fInfo
            })
        else
            responseData.error = "Log not found"
            responseData.success = false
        end

    elseif responseType == "generate-script" then
        -- Generate a script for a specific log
        local idx = tonumber(cmd.index) or 1
        if logs[idx] and logs[idx].Remote then
            responseData.output = genScript(logs[idx].Remote, logs[idx].args or {})
        else
            responseData.error = "Log not found"
            responseData.success = false
        end

    elseif responseType == "blacklist-remote" then
        -- Add a remote to blacklist (won't log)
        local idx = tonumber(cmd.index)
        local name = cmd.name
        if idx and logs[idx] and logs[idx].Remote then
            local id = ThreadGetDebugId(logs[idx].Remote)
            blacklist[id] = true
            responseData.output = "Blacklisted remote: " .. logs[idx].Name
        elseif name then
            blacklist[name] = true
            responseData.output = "Blacklisted remote by name: " .. name
        else
            responseData.error = "Specify index or name"
            responseData.success = false
        end

    elseif responseType == "block-remote" then
        -- Add a remote to blocklist (won't fire)
        local idx = tonumber(cmd.index)
        local name = cmd.name
        if idx and logs[idx] and logs[idx].Remote then
            local id = ThreadGetDebugId(logs[idx].Remote)
            blocklist[id] = true
            responseData.output = "Blocked remote: " .. logs[idx].Name
        elseif name then
            blocklist[name] = true
            responseData.output = "Blocked remote by name: " .. name
        else
            responseData.error = "Specify index or name"
            responseData.success = false
        end

    elseif responseType == "unblacklist-remote" then
        local idx = tonumber(cmd.index)
        local name = cmd.name
        if idx and logs[idx] and logs[idx].Remote then
            local id = ThreadGetDebugId(logs[idx].Remote)
            blacklist[id] = nil
            responseData.output = "Unblacklisted remote: " .. logs[idx].Name
        elseif name then
            blacklist[name] = nil
            responseData.output = "Unblacklisted remote: " .. name
        else
            responseData.error = "Specify index or name"
            responseData.success = false
        end

    elseif responseType == "unblock-remote" then
        local idx = tonumber(cmd.index)
        local name = cmd.name
        if idx and logs[idx] and logs[idx].Remote then
            local id = ThreadGetDebugId(logs[idx].Remote)
            blocklist[id] = nil
            responseData.output = "Unblocked remote: " .. logs[idx].Name
        elseif name then
            blocklist[name] = nil
            responseData.output = "Unblocked remote: " .. name
        else
            responseData.error = "Specify index or name"
            responseData.success = false
        end

    elseif responseType == "get-blacklists" then
        responseData.output = jsone({
            blacklist = blacklist,
            blocklist = blocklist
        })

    else
        responseData.error = "Unknown command: " .. responseType
        responseData.success = false
    end

    return responseData
end

-- Send response back to MCP server
local function sendMCPResponse(data)
    local payload = jsone(data)

    -- Only use one transport at a time to avoid double-sending
    -- Prefer WebSocket if connected
    if MCPWebSocket then
        local success, err = pcall(function()
            MCPWebSocket:Send(payload)
        end)
        if success then return end
        -- If WebSocket send failed, clear it and fall through to HTTP
        MCPWebSocket = nil
    end

    -- Only use HTTP polling if WebSocket is not connected
    if MCPHttpRunning and request then
        pcall(function()
            local headers = { ["Content-Type"] = "application/json" }
            if MCPBridgeSecret and MCPBridgeSecret ~= "" then
                headers["X-Bridge-Secret"] = MCPBridgeSecret
            end
            request({
                Url = "http://" .. MCPBridgeURL .. "/respond",
                Method = "POST",
                Headers = headers,
                Body = payload
            })
        end)
    end
end

-- HTTP Polling loop (fallback when WebSocket not available)
local function startHttpPolling()
    if MCPHttpRunning then return end
    MCPHttpRunning = true

    spawn(function()
        while MCPHttpRunning and MCPEnabled do
            pcall(function()
                local headers = nil
                if MCPBridgeSecret and MCPBridgeSecret ~= "" then
                    headers = { ["X-Bridge-Secret"] = MCPBridgeSecret }
                end
                local response = request({
                    Url = "http://" .. MCPBridgeURL .. "/poll",
                    Method = "GET",
                    Headers = headers
                })

                if response and response.StatusCode == 200 and response.Body then
                    local cmd = jsond(response.Body)
                    if cmd and cmd.type then
                        local result = handleMCPCommand(cmd)
                        sendMCPResponse(result)
                    end
                end
            end)

            task.wait(0.5) -- Poll every 500ms
        end
        MCPHttpRunning = false
    end)
end

-- Prefer WebSocket; try common executor globals (Volt uses WebSocket, Syn uses syn.websocket)
local function getWebSocketAPI()
    if syn and syn.websocket then return syn.websocket end
    if type(WebSocket) == "table" and type(WebSocket.connect) == "function" then return WebSocket end
    if type(websocket) == "table" and type(websocket.connect) == "function" then return websocket end
    if type(_G.WebSocket) == "table" and type(_G.WebSocket.connect) == "function" then return _G.WebSocket end
    return nil
end

-- WebSocket connection with retries; falls back to HTTP only after retries fail
local function connectWebSocket()
    MCPHttpRunning = false

    local WS = getWebSocketAPI()
    if not WS then
        startHttpPolling()
        return
    end

    local url = "ws://" .. MCPBridgeURL
    local ws = nil
    for attempt = 1, MCP_WS_RETRIES do
        local ok, result = pcall(function()
            return WS.connect(url)
        end)
        if ok and result then
            ws = result
            break
        end
        if attempt < MCP_WS_RETRIES then
            task.wait(MCP_WS_RETRY_DELAY)
        end
    end

    if ws then
        MCPWebSocket = ws
        getgenv()._SimpleSpyMCPWebSocket = ws

        if MCPBridgeSecret and MCPBridgeSecret ~= "" then
            pcall(function()
                ws:Send(jsone({ type = "auth", secret = MCPBridgeSecret }))
            end)
        end

        ws.OnMessage:Connect(function(message)
            local cmd = jsond(message)
            if cmd then
                local result = handleMCPCommand(cmd)
                sendMCPResponse(result)
            end
        end)

        ws.OnClose:Connect(function()
            MCPWebSocket = nil
            if getgenv()._SimpleSpyMCPWebSocket == ws then
                getgenv()._SimpleSpyMCPWebSocket = nil
            end
            -- If we closed on purpose (Shutdown / disconnect), do not reconnect
            if getgenv()._SimpleSpyMCPShuttingDown then
                getgenv()._SimpleSpyMCPShuttingDown = nil
                startHttpPolling()
                return
            end
            -- Unexpected close: try to reconnect via WebSocket after a delay (mainly use WebSocket)
            spawn(function()
                task.wait(MCP_WS_RECONNECT_DELAY)
                if not MCPEnabled then return end
                if getgenv()._SimpleSpyMCPWebSocket then return end
                connectWebSocket()
            end)
        end)
    else
        startHttpPolling()
    end
end

-- Start MCP connector
if MCPEnabled then
    spawn(function()
        task.wait(1)
        connectWebSocket()
    end)
end

-- Expose MCP functions
getgenv().SimpleSpy.mcp = {
    connect = connectWebSocket,
    disconnect = function()
        getgenv()._SimpleSpyMCPShuttingDown = true
        MCPHttpRunning = false
        if MCPWebSocket then
            pcall(function() MCPWebSocket:Close() end)
            MCPWebSocket = nil
        end
        if getgenv()._SimpleSpyMCPWebSocket then
            getgenv()._SimpleSpyMCPWebSocket = nil
        end
    end,
    isConnected = function()
        return MCPWebSocket ~= nil or MCPHttpRunning
    end,
    setURL = function(url)
        MCPBridgeURL = url
    end
}
print("SimpleSpy initialized")
