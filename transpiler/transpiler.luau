local Transpiler = {Version = "3.50"}

-- Embedded runtime sources. Generated scripts are self-contained and do not require external Laua runtime modules.

local LAUA_ASYNC_RUNTIME_SOURCE = [====[
type LauaPromiseStatus = "Pending" | "Fulfilled" | "Rejected"
type LauaPackedValues = {n: number, [number]: any}
type LauaPromiseState = {
    _status: LauaPromiseStatus,
    _values: LauaPackedValues?,
    _waiters: {thread},
}

local Async: any = {}
local Promise: {[string]: any} = {}
Promise.__index = Promise

local function isPromise(value: any): boolean
    return type(value) == "table" and getmetatable(value) == Promise
end

local function settle(promise: LauaPromiseState, status: LauaPromiseStatus, values: LauaPackedValues)
    if promise._status ~= "Pending" then return end
    promise._status = status
    promise._values = values
    for _, thread in promise._waiters do
        task.spawn(thread, status == "Fulfilled", table.unpack(values, 1, values.n))
    end
    table.clear(promise._waiters)
end

function Async.run(callback: (...any) -> ...any, ...: any)
    assert(type(callback) == "function", "Async.run expects a function")
    local promise: LauaPromiseState = {_status = "Pending", _values = nil, _waiters = {}}
    setmetatable(promise, Promise)
    task.spawn(function(...)
        local result = table.pack(pcall(callback, ...))
        if result[1] then
            local values = table.pack(table.unpack(result, 2, result.n))
            if values.n == 1 and isPromise(values[1]) then
                local settled = table.pack(pcall(Async.await, values[1]))
                if settled[1] then
                    settle(promise, "Fulfilled", table.pack(table.unpack(settled, 2, settled.n)))
                else
                    settle(promise, "Rejected", table.pack(settled[2]))
                end
            else
                settle(promise, "Fulfilled", values)
            end
        else
            settle(promise, "Rejected", table.pack(result[2]))
        end
    end, ...)
    return promise
end

function Async.await(value: any)
    if not isPromise(value) then
        if type(value) == "table" and type(value.Wait) == "function" and type(value.Fire) == "function" then
            return (value :: {Wait: (any) -> ...any}):Wait()
        end
        return value
    end
    if value._status == "Fulfilled" then
        return table.unpack(value._values, 1, value._values.n)
    end
    if value._status == "Rejected" then error(value._values[1], 2) end
    local current = coroutine.running()
    if not current then error("await requires a yieldable coroutine", 2) end
    table.insert(value._waiters, current)
    local outcome = table.pack(coroutine.yield())
    if not outcome[1] then error(outcome[2], 2) end
    return table.unpack(outcome, 2, outcome.n)
end

function Promise:await()
    return Async.await(self)
end

function Promise:andThen(callback: (...any) -> ...any)
    return Async.run(function()
        return callback(Async.await(self))
    end)
end

function Promise:catch(callback: (...any) -> ...any)
    return Async.run(function()
        local result = table.pack(pcall(Async.await, self))
        if result[1] then return table.unpack(result, 2, result.n) end
        return callback(result[2])
    end)
end

function Promise:finally(callback: () -> ())
    return Async.run(function()
        local result = table.pack(pcall(Async.await, self))
        callback()
        if not result[1] then error(result[2], 0) end
        return table.unpack(result, 2, result.n)
    end)
end

function Promise.getStatus(self: LauaPromiseState): LauaPromiseStatus
    return self._status
end

Async.Promise = Promise
Async.isPromise = isPromise
return Async
]====]

local LAUA_CORE_RUNTIME_SOURCE = [====[
local LauaCore = {}

function LauaCore.optional(value: any, key: any): any
    if value == nil then return nil end
    if typeof(value) == "Instance" then
        local ok, result = pcall(function() return value[key] end)
        if ok then return result end
        if typeof(key) == "string" then return (value :: Instance):FindFirstChild(key) end
        return nil
    end
    return value[key]
end

function LauaCore.coalesce(value: any, fallback: () -> any): any
    if value ~= nil then return value end
    return fallback()
end


-- Laua: spread merges consecutive array entries and then named keys.
function LauaCore.spread(...: any): {[any]: any}
    local result = {}
    for index = 1, select("#", ...) do
        local item = select(index, ...)
        assert(type(item) == "table", "spread expects tables")
        for arrayIndex = 1, #item do
            table.insert(result, item[arrayIndex])
        end
        for key, value in item do
            if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #item then
                result[key] = value
            end
        end
    end
    return result
end

function LauaCore.slice(value: any, first: number?, last: number?): any
    local valueType = typeof(value)
    if valueType == "string" then
        return string.sub(value, first or 1, last or #value)
    end
    if valueType == "buffer" then
        local length = buffer.len(value)
        local startIndex = first or 1
        local endIndex = last or length
        if startIndex < 0 then startIndex = length + startIndex + 1 end
        if endIndex < 0 then endIndex = length + endIndex + 1 end
        startIndex = math.clamp(startIndex, 1, length + 1)
        endIndex = math.clamp(endIndex, 0, length)
        local size = math.max(0, endIndex - startIndex + 1)
        local result = buffer.create(size)
        if size > 0 then buffer.copy(result, 0, value, startIndex - 1, size) end
        return result
    end
    error("slice supports strings and buffers only")
end


-- Laua is: matches a Laua class or one of its ancestors.
function LauaCore.is(value: any, class: any): boolean
    if type(class) ~= "table" or type(value) ~= "table" then return false end
    local candidate = getmetatable(value)
    for _ = 1, 4 do
        if type(candidate) ~= "table" then return false end
        if candidate == class then return true end
        local meta = getmetatable(candidate)
        candidate = type(meta) == "table" and meta.__index or nil
    end
    local visited = {}
    while type(candidate) == "table" and not visited[candidate] do
        if candidate == class then return true end
        visited[candidate] = true
        local meta = getmetatable(candidate)
        candidate = type(meta) == "table" and meta.__index or nil
    end
    return false
end

-- Unlike an eager index, the index expression is not evaluated for nil.
function LauaCore.optionalCall(value: any, callback: (any) -> any): any
    if value == nil then return nil end
    return callback(value)
end

function LauaCore.optionalIndex(value: any, key: () -> any): any
    if value == nil then return nil end
    local index = key()
    if typeof(value) == "Instance" then
        local ok, result = pcall(function() return value[index] end)
        if ok then return result end
        if typeof(index) == "string" then return (value :: Instance):FindFirstChild(index) end
        return nil
    end
    return value[index]
end

-- Cache complete result tuples, including nils; cache keys use argument identity.
function LauaCore.memo(callback: (...any) -> ...any): (...any) -> ...any
    local root: {[any]: any} = {}
    local nilKey = {}
    local terminal = {}
    local wrapped = function(...)
        local node: {[any]: any} = root
        for index = 1, select("#", ...) do
            local key = select(index, ...)
            if key == nil then key = nilKey end
            local nextNode: {[any]: any}? = node[key]
            if nextNode ~= nil then
                node = nextNode
            else
                local created: {[any]: any} = {}
                node[key] = created
                node = created
            end
        end
        local cached: {n: number, [number]: any}? = node[terminal]
        if cached == nil then
            local result = table.pack(callback(...))
            node[terminal] = result
            return table.unpack(result, 1, result.n)
        end
        return table.unpack(cached, 1, cached.n)
    end
    if LauaCore._memoResets == nil then
        LauaCore._memoResets = setmetatable({}, {__mode = "k"})
    end
    LauaCore._memoResets[wrapped] = function()
        root = {}
    end
    return wrapped
end

-- Clear one memoized function or every memo cache in this script.
-- Clearing resets the cache, not the memoized function's identity.
function LauaCore.clearMemo(callback: ((...any) -> ...any)?): boolean
    local resets = LauaCore._memoResets
    if resets == nil then return false end
    if callback ~= nil then
        local reset = resets[callback]
        if reset == nil then error("memo.clear expects a memoized function", 2) end
        reset()
        return true
    end
    for _, reset in resets do reset() end
    return true
end

LauaCore.table = {}

function LauaCore.table.filter<T>(items: {T}, predicate: (T, number) -> boolean): {T}
    local out: {T} = {}
    for index, item in items do
        if predicate(item, index) then table.insert(out, item) end
    end
    return out
end

function LauaCore.table.map<T, U>(items: {T}, callback: (T, number) -> U): {U}
    local out: {U} = table.create(#items)
    for index, item in items do
        out[index] = callback(item, index)
    end
    return out
end

function LauaCore.table.reduce<T, U>(items: {T}, callback: (U, T, number) -> U, initial: U): U
    local current: U = initial
    for index, item in items do current = callback(current, item, index) end
    return current
end

function LauaCore.table.findWhere<T>(items: {T}, predicate: (T, number) -> boolean): T?
    for index, item in items do
        if predicate(item, index) then return item end
    end
    return nil
end

-- Lazy imports can break *some* initialisation cycles if neither module
-- accesses the other before both have finished loading.
function LauaCore.lazyModule(resolve: () -> any): any
    local loaded = false
    local target = nil
    local function get()
        if not loaded then
            target = resolve()
            loaded = true
        end
        return target
    end
    return setmetatable({}, {
        __index = function(_, key) return get()[key] end,
        __newindex = function(_, key, value) get()[key] = value end,
        __call = function(_, ...) return get()(...) end,
    })
end

return LauaCore
]====]


local function trim(value: string): string
    return (value:match("^%s*(.-)%s*$") or "")
end

local function maskNonCode(source: string): string
    if not source:find('"', 1, true) and not source:find("'", 1, true) and not source:find("`", 1, true) and not source:find("[", 1, true) and not source:find("--", 1, true) then return source end
    local output = table.create(#source)
    local position = 1
    local quote = nil
    local longClose = nil
    local lineComment = false

    while position <= #source do
        local char = source:sub(position, position)
        local nextChar = source:sub(position + 1, position + 1)

        if longClose then
            local closing = source:sub(position, position + #longClose - 1) == longClose
            if closing then
                for _ = 1, #longClose do output[#output + 1] = " " end
                position += #longClose
                longClose = nil
            else
                output[#output + 1] = char == "\n" and "\n" or " "
                position += 1
            end
        elseif lineComment then
            output[#output + 1] = char == "\n" and "\n" or " "
            if char == "\n" then lineComment = false end
            position += 1
        elseif quote then
            if char == "\\" and position < #source then
                output[#output + 1] = " "
                output[#output + 1] = " "
                position += 2
            else
                output[#output + 1] = char == "\n" and "\n" or " "
                if char == quote then quote = nil end
                position += 1
            end
        elseif char == "-" and nextChar == "-" then
            local equals = source:sub(position + 2, position + 2) == "[" and source:sub(position + 3):match("^(=*)%[") or nil
            if equals then
                local opening = 4 + #equals
                for _ = 1, opening do output[#output + 1] = " " end
                position += opening
                longClose = "]" .. equals .. "]"
            else
                output[#output + 1] = " "
                output[#output + 1] = " "
                lineComment = true
                position += 2
            end
        elseif char == '"' or char == "'" or char == "`" then
            quote = char
            output[#output + 1] = " "
            position += 1
        elseif char == "[" then
            local equals = (nextChar == "[" or nextChar == "=") and source:sub(position + 1):match("^(=*)%[") or nil
            if equals then
                local opening = 2 + #equals
                for _ = 1, opening do output[#output + 1] = " " end
                position += opening
                longClose = "]" .. equals .. "]"
            else
                output[#output + 1] = char
                position += 1
            end
        else
            output[#output + 1] = char
            position += 1
        end
    end

    return table.concat(output)
end

local function splitLines(source: string)
    local lines = {}
    local start = 1
    while true do
        local ending = source:find("\n", start, true)
        if not ending then
            table.insert(lines, {Start = start, Finish = #source, Text = source:sub(start)})
            return lines
        end
        table.insert(lines, {Start = start, Finish = ending - 1, Text = source:sub(start, ending - 1)})
        start = ending + 1
    end
end

local function blockStart(line: string): boolean
    if line:match("^abstract%s+class%s+") or line:match("^final%s+class%s+") or line:match("^class%s+") then return true end
    if line:match("^namespace%s+") or line:match("^return%s+namespace%s+") or line:match("^enum%s+") or line:match("^match%s+") or line:match("^schema%s+") then return true end
    if line:match("^constructor%s*%(") or line:match("^defer%s*$") or line:match("^operator%s+") or line:match("^watch%s+[%a_][%w_]*%s*%(") then return true end
    if line:match("^async%s+function%s+") or line:match("^local%s+async%s+function%s+") then return true end
    if line:match("^get%s+[%a_][%w_]*%s*%(") or line:match("^set%s+[%a_][%w_]*%s*%(") then return true end
    if line:match("^function%s+") or line:match("^local%s+function%s+") then return true end
    if line:match("^.*=%s*function%s*%(") then return true end
    if line:match("^if%s+.*%s+then%s*$") or line:match("^for%s+.*%s+do%s*$") then return true end
    if line:match("^while%s+.*%s+do%s*$") or line:match("^do%s*$") or line:match("^repeat%s*$") then return true end
    local remainder = line
    while true do
        local found = false
        for _, modifier in {"public", "private", "protected", "static", "override", "final", "abstract"} do
            local rest = remainder:match("^" .. modifier .. "%s+(.+)$")
            if rest then remainder = rest; found = true; break end
        end
        if not found then break end
    end
    if remainder:match("^function%s+") or remainder:match("^async%s+function%s+") or remainder:match("^get%s+[%a_][%w_]*%s*%(") or remainder:match("^set%s+[%a_][%w_]*%s*%(") then return true end
    return false
end

local function findBlock(source: string, startIndex: number, precomputedLines: any?)
    local lines = precomputedLines or splitLines(maskNonCode(source))
    local lineIndex = nil
    local low, high = 1, #lines
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local line = lines[middle]
        if startIndex < line.Start then
            high = middle - 1
        elseif startIndex > line.Finish then
            low = middle + 1
        else
            lineIndex = middle
            break
        end
    end
    if not lineIndex then error("Cannot find Laua block") end

    local depth = 0
    for index = lineIndex, #lines do
        local line = lines[index]
        if line.BlockOpen == nil then
            local code = trim(line.Text)
            line.BlockOpen = blockStart(code)
            line.BlockClose = code:match("^end%s*;?%s*$") ~= nil or code:match("^until%s+") ~= nil
        end
        if line.BlockOpen then depth += 1 end
        if line.BlockClose then
            depth -= 1
            if depth == 0 then return line end
        end
    end

    error("Missing 'end' in Laua source")
end

local function findKeyword(source: string, keyword: string, precomputedMask: string?, startAt: number?): number?
    local masked = precomputedMask or maskNonCode(source)
    local start = startAt or 1

    while true do
        local first, last = masked:find(keyword, start, true)
        if not first then return nil end
        local before = masked:sub(first - 1, first - 1)
        local after = masked:sub(last + 1, last + 1)
        if not before:match("[%w_%.:]") and not after:match("[%w_]") then
            if keyword == "enum" or keyword == "namespace" then
                local lineStart = (masked:sub(1, first - 1):match(".*()\n") or 0) + 1
                local prefix = trim(masked:sub(lineStart, first - 1))
                local following = masked:sub(last + 1):match("^%s+([%a_][%w_]*)%s*\n")
                if not following then following = masked:sub(last + 1):match("^%s+([%a_][%w_]*)%s*$") end
                if following and (prefix == "" or keyword == "namespace" and prefix == "return") then return first end
            else
                return first
            end
        end
        start = last + 1
    end
end

local function normalized(source: string, prefix: string): string
    local lines = splitLines(source)
    local first, last = 1, #lines
    while first <= last and trim(lines[first].Text) == "" do first += 1 end
    while last >= first and trim(lines[last].Text) == "" do last -= 1 end
    if first > last then return "" end
    local minimum = math.huge
    for index = first, last do
        local line = lines[index].Text
        if trim(line) ~= "" then
            local leading = line:match("^[ \t]*") or ""
            minimum = math.min(minimum, #leading)
        end
    end
    local result = {}
    for index = first, last do
        local line = lines[index].Text
        if trim(line) == "" then
            table.insert(result, "")
        else
            table.insert(result, prefix .. line:sub(minimum + 1))
        end
    end
    return table.concat(result, "\n")
end

local transpileSource

local function transpileNew(source: string): string
    local masked = maskNonCode(source)
    local output = {}
    local cursor, last = 1, 1
    while true do
        local start = findKeyword(source, "new", masked, cursor)
        if not start then break end
        local rest = source:sub(start + 3)
        local whitespace, className = rest:match("^(%s+)([%a_][%w_%.]*)")
        -- `new` may be a normal table key or variable; transform only `new Class`.
        if not className then cursor = start + 3; continue end
        local after = start + 3 + #whitespace + #className
        local suffix = source:sub(after)
        table.insert(output, source:sub(last, start - 1))
        table.insert(output, className)
        table.insert(output, suffix:match("^%s*%(") and ".new" or ".new()")
        last, cursor = after, after
    end
    if #output == 0 then return source end
    table.insert(output, source:sub(last))
    return table.concat(output)
end

local function transpileEnums(source: string): string
    while true do
        local start = findKeyword(source, "enum")
        if not start then return source end
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then error("Enum body expected") end
        local name = trim(source:sub(start, headerEnd - 1)):match("^enum%s+([%a_][%w_]*)$")
        if not name then error("Invalid enum declaration") end
        local closing = findBlock(source, start)
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local members = {}
        local nextNumber = 0

        for _, row in splitLines(body) do
            local line = trim(row.Text):gsub(",$", "")
            if line == "" or line:match("^%-%-") then continue end
            local memberName, value = line:match("^([%a_][%w_]*)%s*=%s*(.+)$")
            if not memberName then
                memberName = line:match("^([%a_][%w_]*)$")
                if not memberName then error(`Invalid enum member: {line}`) end
                value = tostring(nextNumber)
                nextNumber += 1
            else
                local integer = tonumber(value)
                if integer and integer % 1 == 0 then nextNumber = integer + 1 end
            end
            table.insert(members, `    {memberName} = {value},`)
        end
        local replacement = "local " .. name .. " = table.freeze({\n" .. table.concat(members, "\n") .. "\n})"
        source = source:sub(1, start - 1) .. replacement .. source:sub(closing.Finish + 1)
    end
end

local function parseModifiers(header: string)
    local modifiers = {}
    local rest = trim(header)
    while true do
        local modifier, tail = nil, nil
        if not modifier then
            for _, possible in {"public", "private", "protected", "static", "override", "abstract", "final"} do
                local before = rest:match("^" .. possible .. "%s+(.+)$")
                if before then
                    modifier = possible
                    tail = before
                    break
                end
            end
        end
        if not modifier then break end
        if modifiers[modifier] then error(`Duplicate modifier '{modifier}'`) end
        modifiers[modifier] = true
        rest = tail
    end
    return modifiers, rest
end

local function getParams(params: string): string
    local names = {}
    for part in params:gmatch("[^,]+") do
        local name = trim(part):match("^([%a_][%w_]*)")
        if name then table.insert(names, name) end
    end
    return table.concat(names, ", ")
end

local function replaceSuper(source: string, base: string, instanceReceiver: boolean?): string
    local includeSelf = instanceReceiver ~= false
    local masked = maskNonCode(source)
    local changes = {}
    local cursor = 1
    while true do
        local start, finish, separator, method = masked:find("%f[%w]super%s*([:.])%s*([%a_][%w_]*)", cursor)
        if not start then break end
        if masked:sub(start - 1, start - 1):match("[.:]") then cursor = finish + 1; continue end
        local open = finish + 1
        while masked:sub(open, open):match("%s") and open <= #masked do open += 1 end
        local isCall = masked:sub(open, open) == "("
        if separator == ":" and not isCall then error(`Expected '(' after super:{method}`) end
        if separator == ":" and not includeSelf then error(`super:{method}(...) cannot be used in a static method`) end
        if isCall and includeSelf then
            local depth = 0
            local close = nil
            for index = open, #masked do
                local char = masked:sub(index, index)
                if char == "(" then depth += 1 end
                if char == ")" then
                    depth -= 1
                    if depth == 0 then close = index; break end
                end
            end
            if not close then error(`Unclosed super.{method}(`) end
            local args = trim(source:sub(open + 1, close - 1))
            table.insert(changes, {Start = start, Finish = close, Replacement = base .. "." .. method .. "(self" .. (args ~= "" and ", " .. args or "") .. ")"})
            cursor = close + 1
        else
            table.insert(changes, {Start = start, Finish = finish, Replacement = base .. "." .. method})
            cursor = finish + 1
        end
    end
    for index = #changes, 1, -1 do
        local item = changes[index]
        source = source:sub(1, item.Start - 1) .. item.Replacement .. source:sub(item.Finish + 1)
    end
    return source
end

local LAUA_OPERATOR_MAP = { ["+"] = "__add", ["-"] = "__sub", ["*"] = "__mul", ["/"] = "__div", ["//"] = "__idiv", ["%"] = "__mod", ["^"] = "__pow", [".."] = "__concat", ["=="] = "__eq", ["<"] = "__lt", ["<="] = "__le", ["#"] = "__len" }
local LAUA_METHOD_KINDS = {"async function", "function", "get", "set"}

local function transpileClasses(source: string): string
    local allocationRequirements: {[string]: {Values: boolean, Initialized: boolean}} = {}
    local hookFreeClasses: {[string]: boolean} = {}
    local featureRequirements: {[string]: {Getters: boolean, Setters: boolean, Lazy: boolean, Watchers: boolean}} = {}
    local finalMethodRequirements: {[string]: boolean} = {}
    local finalClassFlags: {[string]: boolean} = {}
    local searchFrom = 1
    while true do
        local start = findKeyword(source, "class", nil, searchFrom)
        if not start then return source end
        local lineStart = (source:sub(1, start - 1):match(".*()\n") or 0) + 1
        local prefix = trim(source:sub(lineStart, start - 1))
        if prefix ~= "" and prefix ~= "final" and prefix ~= "abstract" then
            local endOfLine = source:find("\n", start, true) or (#source + 1)
            local candidate = trim(source:sub(start, endOfLine - 1))
            if candidate:match("^class%s+[%a_][%w_]*$") or candidate:match("^class%s+[%a_][%w_]*%s+extends%s+[%a_][%w_%.]*$") then
                error(`Invalid class modifier '{prefix}'`)
            end
            searchFrom = start + 5
            continue
        end
        searchFrom = 1
        local declarationStart = prefix ~= "" and lineStart or start
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then error("Class body expected") end
        local header = trim(source:sub(start, headerEnd - 1))
        local name, base = header:match("^class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_%.]*)$")
        if not name then name = header:match("^class%s+([%a_][%w_]*)$") end
        if not name then error(`Invalid class declaration: {header}`) end
        local closing = findBlock(source, start)
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local lines = splitLines(body)
        local blockLines = splitLines(maskNonCode(body))
        local fields, statics, methods, getters, setters, operators, lazies, watchers = {}, {}, {}, {}, {}, {}, {}, {}
        local attributes = {}
        local names = {}
        local ctor = nil
        local index = 1

        while index <= #lines do
            local row = lines[index]
            local headerText = trim(row.Text)
            if headerText == "" or headerText:match("^%-%-") then
                index += 1
                continue
            end
            if headerText:match("^@") then
                table.insert(attributes, headerText)
                index += 1
                continue
            end
            local modifiers, remainder = parseModifiers(headerText)
            local kind, memberName, params, returnType = nil, nil, nil, nil
            if not kind then
                for _, possible in LAUA_METHOD_KINDS do
                    memberName, params = remainder:match("^" .. possible .. "%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*$")
                    if memberName then kind = possible; break end
                end
            end
            if not kind then
                for _, possible in LAUA_METHOD_KINDS do
                    memberName, params, returnType = remainder:match("^" .. possible .. "%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*:%s*(.+)$")
                    if memberName then kind = possible; break end
                end
            end
            local operatorSymbol, operatorParams = remainder:match("^operator%s+([^%s%(]+)%s*%(([^)]*)%)%s*$")
            if operatorSymbol then
                local metamethod = LAUA_OPERATOR_MAP[operatorSymbol]
                if not metamethod then error(`Unsupported operator '{operatorSymbol}'`) end
                if operatorSymbol == "-" and trim(operatorParams) == "" then metamethod = "__unm" end
                if (metamethod == "__unm" or metamethod == "__len") and trim(operatorParams) ~= "" then error(`Unary operator '{operatorSymbol}' takes no arguments`) end
                if metamethod ~= "__unm" and metamethod ~= "__len" and not trim(operatorParams):match("^[%a_][%w_]*%s*:?[%w_ ]*$") then error("Binary operator requires exactly one parameter") end
                if names[metamethod] then error(`Duplicate operator '{operatorSymbol}'`) end
                if next(modifiers) then error("Operators cannot have modifiers") end
                names[metamethod] = true
                local operatorAt = row.Start + (row.Text:find("operator", 1, true) or 1) - 1
                local operatorEnd = findBlock(body, operatorAt, blockLines)
                local operatorHeaderEnd = body:find("\n", operatorAt, true)
                local operatorBody = operatorHeaderEnd and body:sub(operatorHeaderEnd + 1, operatorEnd.Start - 1) or ""
                table.insert(operators, {Name = metamethod, Params = operatorParams, Body = operatorBody})
                local nextIndex = nil
                for pos = index + 1, #lines do
                    if lines[pos].Start > operatorEnd.Finish then nextIndex = pos; break end
                end
                index = nextIndex or (#lines + 1)
                continue
            end
            local watchName, watchParams = remainder:match("^watch%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*$")
            if watchName then
                if next(modifiers) or #attributes > 0 then error("watch cannot use modifiers or attributes") end
                if watchers[watchName] then error(`Duplicate watcher '{watchName}'`) end
                local oldParam, newParam = watchParams:match("^%s*([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*$")
                if not oldParam or not newParam or oldParam == newParam then error("watch requires two distinct parameters: oldValue, newValue") end
                local at = row.Start + (row.Text:find("watch", 1, true) or 1) - 1
                local done = findBlock(body, at, blockLines)
                local nextLine = body:find("\n", at, true)
                watchers[watchName] = {Params = watchParams, Body = nextLine and body:sub(nextLine + 1, done.Start - 1) or ""}
                local nextIndex = nil
                for pos = index + 1, #lines do
                    if lines[pos].Start > done.Finish then nextIndex = pos; break end
                end
                index = nextIndex or (#lines + 1)
                continue
            end
            local lazyName, lazyValue = remainder:match("^lazy%s+([%a_][%w_]*)%s*=%s*(.+)$")
            if lazyName then
                if next(modifiers) or #attributes > 0 then error("lazy cannot use modifiers or attributes") end
                if names[lazyName] or lazies[lazyName] then error(`Duplicate member '{lazyName}'`) end
                names[lazyName] = true
                lazies[lazyName] = lazyValue
                index += 1
                continue
            end
            local ctorParams = remainder:match("^constructor%s*%(([^)]*)%)%s*$")
            if kind or ctorParams then
                local kindStart = row.Start + (row.Text:find(kind or "constructor", 1, true) or 1) - 1
                local ending = findBlock(body, kindStart, blockLines)
                local nextLine = body:find("\n", kindStart, true)
                local memberBody = nextLine and body:sub(nextLine + 1, ending.Start - 1) or ""
                local member = {Name = memberName, Kind = kind or "constructor", Params = params or ctorParams,
                    Body = memberBody, ReturnType = returnType and trim(returnType) or "", Static = modifiers.static == true, Abstract = modifiers.abstract == true,
                    Final = modifiers.final == true, Override = modifiers.override == true, Attributes = table.concat(attributes, "\n")}
                attributes = {}
                if member.Kind == "constructor" then
                    if ctor then error(`Duplicate constructor in '{name}'`) end
                    if next(modifiers) then error("Constructor cannot use class member modifiers") end
                    ctor = member
                elseif member.Kind == "get" or member.Kind == "set" then
                    if member.Static then error("Static getters/setters are not supported") end
                    if member.Kind == "get" and trim(member.Params) ~= "" then error("Getter cannot take parameters") end
                    if member.Kind == "set" and not trim(member.Params):match("^[%a_][%w_]*%s*:?[%w_ ]*$") then error("Setter requires one parameter") end
                    if member.Kind == "get" then table.insert(getters, member) else table.insert(setters, member) end
                else
                    if names[member.Name] then error(`Duplicate class member '{member.Name}'`) end
                    names[member.Name] = true
                    if member.Override and not base then error(`Cannot override '{member.Name}' without a parent class`) end
                    table.insert(methods, member)
                end
                local nextIndex = nil
                for pos = index + 1, #lines do
                    if lines[pos].Start > ending.Finish then nextIndex = pos; break end
                end
                index = nextIndex or (#lines + 1)
                continue
            end
            local field, value = remainder:match("^([%a_][%w_]*)%s*=%s*(.+)$")
            if not field then field, value = remainder:match("^([%a_][%w_]*)%s*:%s*[^%s=].-%s*=%s*(.+)$") end
            if not field then field = remainder:match("^([%a_][%w_]*)%s*:%s*[^%s=].-%s*$") end
            if not field then error(`Invalid class member: {headerText}`) end
            if names[field] then error(`Duplicate class member '{field}'`) end
            if modifiers.final or modifiers.override or modifiers.abstract then error(`Invalid modifier for field '{field}'`) end
            if #attributes > 0 then error("Attributes are supported on methods only") end
            names[field] = true
            table.insert(modifiers.static and statics or fields, {Name = field, Value = value})
            index += 1
        end

        local properties = {}
        for _, member in getters do properties[member.Name] = true end
        for _, member in setters do properties[member.Name] = true end
        for _, field in fields do
            if properties[field.Name] or lazies[field.Name] then error(`Property '{field.Name}' conflicts with a field`) end
        end
        for lazyName in lazies do
            if properties[lazyName] then error(`Lazy member '{lazyName}' conflicts with getter/setter`) end
        end
        local availableFields = {}
        for _, field in fields do availableFields[field.Name] = true end
        for lazyName in lazies do availableFields[lazyName] = true end
        for watchName in watchers do
            if properties[watchName] then error(`Watched member '{watchName}' conflicts with getter/setter`) end
            if not availableFields[watchName] then error(`watch '{watchName}' requires a declared instance field or lazy property`) end
        end

        local ctorBody = ctor and ctor.Body or ""
        local parentInit = base and `{base}.__init(self{ctor and trim(ctor.Params) ~= "" and ", " .. getParams(ctor.Params) or ""})` or nil
        if base and ctor then
            local ctorLines = splitLines(ctorBody)
            for _, row in ctorLines do
                local text = trim(row.Text)
                if text ~= "" and not text:match("^%-%-") then
                    local args = text:match("^super%s*%((.*)%)%s*$")
                    if args then
                        parentInit = `{base}.__init(self{trim(args) ~= "" and ", " .. args or ""})`
                        ctorBody = ctorBody:sub(1, row.Start - 1) .. ctorBody:sub(row.Finish + 1)
                    end
                    break
                end
            end
        end
        if maskNonCode(ctorBody):find("super%s*%(") then error("super(...) must be first in constructor") end
        if base then ctorBody = replaceSuper(ctorBody, base) end
        if not base and maskNonCode(ctorBody):find("super%s*[:%.%(%[]") then error("super requires a parent class") end
        if not base then
            for _, member in methods do
                if maskNonCode(member.Body):find("%f[%w]super%s*[:%.%(%[]") then error("super requires a parent class") end
            end
            for _, member in getters do
                if maskNonCode(member.Body):find("%f[%w]super%s*[:%.%(%[]") then error("super requires a parent class") end
            end
            for _, member in setters do
                if maskNonCode(member.Body):find("%f[%w]super%s*[:%.%(%[]") then error("super requires a parent class") end
            end
            for _, member in operators do
                if maskNonCode(member.Body):find("%f[%w]super%s*[:%.%(%[]") then error("super requires a parent class") end
            end
            for _, member in watchers do
                if maskNonCode(member.Body):find("%f[%w]super%s*[:%.%(%[]") then error("super requires a parent class") end
            end
        end

        -- Only allocate lazy/watched state when this known inheritance chain needs it.
        -- Unknown or external parent classes retain the conservative allocation path.
        local parentAllocation = base and allocationRequirements[base] or nil
        local needsValues = next(watchers) ~= nil or next(lazies) ~= nil or (base ~= nil and (parentAllocation == nil or parentAllocation.Values))
        local needsInitialized = next(lazies) ~= nil or (base ~= nil and (parentAllocation == nil or parentAllocation.Initialized))
        allocationRequirements[name] = {Values = needsValues, Initialized = needsInitialized}
        local hookFree = #getters == 0 and #setters == 0 and next(lazies) == nil and next(watchers) == nil and (base == nil or hookFreeClasses[base] == true)
        hookFreeClasses[name] = hookFree
        -- Only emit metadata and dispatch handlers used by known inheritance chains.
        -- Preserve full hooks for unknown/external base classes.
        local inheritedFeatures = base and featureRequirements[base] or nil
        local unknownBase = base ~= nil and inheritedFeatures == nil
        local usesGetters = #getters > 0 or unknownBase or (inheritedFeatures ~= nil and inheritedFeatures.Getters)
        local usesSetters = #setters > 0 or unknownBase or (inheritedFeatures ~= nil and inheritedFeatures.Setters)
        local usesLazy = next(lazies) ~= nil or unknownBase or (inheritedFeatures ~= nil and inheritedFeatures.Lazy)
        local usesWatchers = next(watchers) ~= nil or unknownBase or (inheritedFeatures ~= nil and inheritedFeatures.Watchers)
        featureRequirements[name] = {Getters = usesGetters, Setters = usesSetters, Lazy = usesLazy, Watchers = usesWatchers}
        local parentFinalMethods = base ~= nil and (finalMethodRequirements[base] == nil or finalMethodRequirements[base])
        local needsFinalMethods = parentFinalMethods
        for _, method in methods do if method.Final then needsFinalMethods = true end end
        finalMethodRequirements[name] = needsFinalMethods
        local checkFinalParent = base ~= nil and finalClassFlags[base] ~= false
        finalClassFlags[name] = prefix == "final"

        -- A plain class does not need getter, setter, watcher, or lazy-property hooks.
        -- Keep __init so later subclasses can safely call the parent initializer.
        local plainClass = not base and prefix == "" and #getters == 0 and #setters == 0 and next(lazies) == nil and next(watchers) == nil
        if plainClass then
            for _, method in methods do
                if method.Abstract or method.Final or method.Override then plainClass = false; break end
            end
        end
        if plainClass then
            local simple = {"local " .. name .. ": {[string]: any} = {}", name .. ".__index = " .. name}
            for _, field in statics do if field.Value ~= nil then table.insert(simple, `{name}.{field.Name} = {transpileSource(field.Value)}`) end end
            table.insert(simple, `function {name}.__init(self: any{ctor and trim(ctor.Params) ~= "" and ", " .. ctor.Params or ""})`)
            for _, field in fields do if field.Value ~= nil then table.insert(simple, `    self.{field.Name} = {transpileSource(field.Value)}`) end end
            local simpleCtor = normalized(transpileSource(ctorBody), "    ")
            if simpleCtor ~= "" then table.insert(simple, simpleCtor) end
            table.insert(simple, "end")
            table.insert(simple, `function {name}.new(...: any): any`)
            table.insert(simple, "    local self: any = setmetatable({}, " .. name .. ")")
            table.insert(simple, `    {name}.__init(self, ...)`)
            table.insert(simple, "    return self")
            table.insert(simple, "end")
            for _, operator in operators do
                table.insert(simple, `function {name}.{operator.Name}(self: any{trim(operator.Params) ~= "" and ", " .. (operator.Params:match("^%s*[%a_][%w_]*%s*$") and trim(operator.Params) .. ": any" or operator.Params) or ""})`)
                local code = normalized(transpileSource(operator.Body), "    ")
                if code ~= "" then table.insert(simple, code) end
                table.insert(simple, "end")
            end
            for _, method in methods do
                local code = normalized(transpileSource(method.Body), "    ")
                table.insert(simple, `{method.Attributes ~= "" and method.Attributes .. "\n" or ""}{method.Kind == "async function" and "async " or ""}function {name}.{method.Name}({method.Static and method.Params or "self: any" .. (trim(method.Params) ~= "" and ", " .. method.Params or "")}){method.ReturnType ~= "" and ": " .. method.ReturnType or ""}`)
                if code ~= "" then table.insert(simple, code) end
                table.insert(simple, "end")
            end
            source = source:sub(1, declarationStart - 1) .. table.concat(simple, "\n") .. source:sub(closing.Finish + 1)
            continue
        end

        -- Known hook-free inheritance needs no property lookup closures,
        -- lazy state, getter/setter tables, or watcher metadata.
        if hookFree then
            local simple = {}
            if base then
                if checkFinalParent then table.insert(simple, `if {base}.__final then error("Cannot extend final class '{base}'") end`) end
                table.insert(simple, "local " .. name .. ": any = setmetatable({}, {__index = " .. base .. "})")
            else
                table.insert(simple, "local " .. name .. ": {[string]: any} = {}")
            end
            table.insert(simple, `{name}.__index = {name}`)
            if prefix == "abstract" then table.insert(simple, `{name}.__abstract = true`) end
            if prefix == "final" then table.insert(simple, `{name}.__final = true`) end
            if needsFinalMethods then
                local finalEntries = {}
                for _, method in methods do
                    if method.Final then table.insert(finalEntries, `["{method.Name}"] = true`) end
                end
                local finalTable = "{" .. table.concat(finalEntries, ", ") .. "}"
                table.insert(simple, `{name}.__finalMethods = {base and "setmetatable(" .. finalTable .. ", {__index = " .. base .. ".__finalMethods or {}})" or finalTable}`)
            end
            for _, field in statics do if field.Value ~= nil then table.insert(simple, `{name}.{field.Name} = {transpileSource(field.Value)}`) end end
            table.insert(simple, `function {name}.__init(self: any{ctor and trim(ctor.Params) ~= "" and ", " .. ctor.Params or ""})`)
            if parentInit then table.insert(simple, "    " .. parentInit) end
            for _, field in fields do if field.Value ~= nil then table.insert(simple, `    self.{field.Name} = {transpileSource(field.Value)}`) end end
            local init = normalized(transpileSource(ctorBody), "    ")
            if init ~= "" then table.insert(simple, init) end
            table.insert(simple, "end")
            table.insert(simple, `function {name}.new(...: any): any`)
            if prefix == "abstract" then table.insert(simple, `    error("Cannot instantiate abstract class '{name}'")`) end
            table.insert(simple, "    local self: any = setmetatable({}, " .. name .. ")")
            table.insert(simple, `    {name}.__init(self, ...)`)
            table.insert(simple, "    return self")
            table.insert(simple, "end")
            for _, op in operators do
                local opBody = normalized(transpileSource(base and replaceSuper(op.Body, base) or op.Body), "    ")
                table.insert(simple, `function {name}.{op.Name}(self: any{trim(op.Params) ~= "" and ", " .. (op.Params:match("^%s*[%a_][%w_]*%s*$") and trim(op.Params) .. ": any" or op.Params) or ""})`)
                if opBody ~= "" then table.insert(simple, opBody) end
                table.insert(simple, "end")
            end
            for _, method in methods do
                if base and parentFinalMethods then table.insert(simple, `if {base}.__finalMethods and {base}.__finalMethods["{method.Name}"] then error("Cannot override final method '{method.Name}'") end`) end
                local methodBody = base and replaceSuper(method.Body, base, not method.Static) or method.Body
                if maskNonCode(methodBody):find("super%s*%(") then error("super(...) can only be called in constructors") end
                methodBody = normalized(transpileSource(methodBody), "    ")
                table.insert(simple, `{method.Attributes ~= "" and method.Attributes .. "\n" or ""}{method.Kind == "async function" and "async " or ""}function {name}.{method.Name}({method.Static and method.Params or "self: any" .. (trim(method.Params) ~= "" and ", " .. method.Params or "")}){method.ReturnType ~= "" and ": " .. method.ReturnType or ""}`)
                if method.Abstract then
                    table.insert(simple, `    error("Abstract method '{name}.{method.Name}' must be overridden")`)
                elseif methodBody ~= "" then
                    table.insert(simple, methodBody)
                end
                table.insert(simple, "end")
            end
            source = source:sub(1, declarationStart - 1) .. table.concat(simple, "\n") .. source:sub(closing.Finish + 1)
            continue
        end

        local generated = {}
        if base then
            if checkFinalParent then table.insert(generated, `if {base}.__final then error("Cannot extend final class '{base}'") end`) end
            table.insert(generated, "local " .. name .. ": any = setmetatable({}, {__index = " .. base .. "})")
        else
            table.insert(generated, "local " .. name .. ": {[string]: any} = {}")
        end
        if prefix == "final" then table.insert(generated, `{name}.__final = true`) end
        if prefix == "abstract" then table.insert(generated, `{name}.__abstract = true`) end
        if needsFinalMethods then
            local finalEntries = {}
            for _, method in methods do
                if method.Final then table.insert(finalEntries, `["{method.Name}"] = true`) end
            end
            local finalTable = "{" .. table.concat(finalEntries, ", ") .. "}"
            local finalMethods = base and ("setmetatable(" .. finalTable .. ", {__index = " .. base .. ".__finalMethods or {}})") or finalTable
            table.insert(generated, `{name}.__finalMethods = {finalMethods}`)
        end
        local function inherited(tableName: string): string
            return base and ("setmetatable({}, {__index = " .. base .. "." .. tableName .. " or {}})") or "{}"
        end
        if usesGetters then table.insert(generated, `{name}.__getters = {inherited("__getters")}`) end
        if usesSetters then table.insert(generated, `{name}.__setters = {inherited("__setters")}`) end
        if usesLazy then table.insert(generated, `{name}.__lazy = {inherited("__lazy")}`) end
        if usesWatchers then
            table.insert(generated, `{name}.__watchers = {inherited("__watchers")}`)
            table.insert(generated, `{name}.__watchedFields = {inherited("__watchedFields")}`)
            for watchName in watchers do table.insert(generated, `{name}.__watchedFields["{watchName}"] = true`) end
        end
        if not usesGetters and not usesLazy and not usesWatchers then
            table.insert(generated, `{name}.__index = {name}`)
        else
            table.insert(generated, `{name}.__index = function(self: any, key: any)`)
            if usesGetters then
                table.insert(generated, `    local getter: ((any) -> any)? = {name}.__getters[key]`)
                table.insert(generated, "    if getter then return getter(self) end")
            end
            if usesLazy then
                table.insert(generated, `    local lazy: ((any) -> any)? = {name}.__lazy[key]`)
                table.insert(generated, "    if lazy then")
                table.insert(generated, "        if not self.__lauaInitialized[key] then")
                table.insert(generated, "            self.__lauaInitialized[key] = true")
                table.insert(generated, "            local ok, value = pcall(lazy, self)")
                table.insert(generated, "            if not ok then self.__lauaInitialized[key] = nil; error(value, 0) end")
                table.insert(generated, "            self.__lauaValues[key] = value")
                table.insert(generated, "        end")
                table.insert(generated, "        return self.__lauaValues[key]")
                table.insert(generated, "    end")
            end
            if usesWatchers then table.insert(generated, `    if {name}.__watchedFields[key] then return self.__lauaValues[key] end`) end
            table.insert(generated, `    return {name}[key]`)
            table.insert(generated, "end")
        end
        if usesSetters or usesGetters or usesLazy or usesWatchers then
            table.insert(generated, `{name}.__newindex = function(self: any, key: any, value: any)`)
            if usesSetters then
                table.insert(generated, `    local setter: ((any, any) -> ())? = {name}.__setters[key]`)
                table.insert(generated, "    if setter then setter(self, value); return end")
            end
            if usesGetters then table.insert(generated, `    if {name}.__getters[key] then error("Cannot assign to read-only property: " .. key) end`) end
            if usesLazy or usesWatchers then
                local tracked = usesLazy and `{name}.__lazy[key]` or ""
                if usesWatchers then tracked = (tracked ~= "" and tracked .. " or " or "") .. `{name}.__watchedFields[key]` end
                table.insert(generated, `    if {tracked} then`)
                table.insert(generated, "        local oldValue = self.__lauaValues[key]")
                if usesLazy then table.insert(generated, `        if {name}.__lazy[key] and not self.__lauaInitialized[key] then self.__lauaInitialized[key] = true end`) end
                table.insert(generated, "        self.__lauaValues[key] = value")
                if usesWatchers then
                    table.insert(generated, `        local watcher: ((any, any, any) -> ())? = {name}.__watchers[key]`)
                    table.insert(generated, "        if watcher and oldValue ~= value then watcher(self, oldValue, value) end")
                end
                table.insert(generated, "        return")
                table.insert(generated, "    end")
            end
            table.insert(generated, "    rawset(self, key, value)")
            table.insert(generated, "end")
        end
        for lazyName, lazyValue in lazies do
            table.insert(generated, `{name}.__lazy["{lazyName}"] = function(self: any) return {transpileSource(lazyValue)} end`)
        end
        for watchName, watcher in watchers do
            table.insert(generated, `{name}.__watchers["{watchName}"] = function(self: any, {watcher.Params})`)
            local code = normalized(transpileSource(base and replaceSuper(watcher.Body, base) or watcher.Body), "    ")
            if code ~= "" then table.insert(generated, code) end
            table.insert(generated, "end")
        end
        for _, field in statics do if field.Value ~= nil then table.insert(generated, `{name}.{field.Name} = {transpileSource(field.Value)}`) end end
        table.insert(generated, `function {name}.__init(self: any{ctor and trim(ctor.Params) ~= "" and ", " .. ctor.Params or ""})`)
        if parentInit then table.insert(generated, "    " .. parentInit) end
        for _, field in fields do
            if field.Value == nil then continue end
            if watchers[field.Name] then
                table.insert(generated, `    self.__lauaValues["{field.Name}"] = {transpileSource(field.Value)}`)
            else
                table.insert(generated, `    self.{field.Name} = {transpileSource(field.Value)}`)
            end
        end
        local innerCtor = normalized(transpileSource(ctorBody), "    ")
        if innerCtor ~= "" then table.insert(generated, innerCtor) end
        table.insert(generated, "end")
        table.insert(generated, `function {name}.new(...: any): any`)
        if prefix == "abstract" then table.insert(generated, `    error("Cannot instantiate abstract class '{name}'")`) end
        local instanceSlots = {}
        if needsValues then table.insert(instanceSlots, "__lauaValues = {}") end
        if needsInitialized then table.insert(instanceSlots, "__lauaInitialized = {}") end
        table.insert(generated, "    local self: any = setmetatable({" .. table.concat(instanceSlots, ", ") .. "}, " .. name .. ")")
        table.insert(generated, `    {name}.__init(self, ...)`)
        table.insert(generated, "    return self")
        table.insert(generated, "end")
        for _, member in getters do
            local nested = base and replaceSuper(member.Body, base) or member.Body
            table.insert(generated, `{name}.__getters.{member.Name} = function(self: any){member.ReturnType ~= "" and ": " .. member.ReturnType or ""}`)
            local code = normalized(transpileSource(nested), "    ")
            if code ~= "" then table.insert(generated, code) end
            table.insert(generated, "end")
        end
        for _, member in setters do
            local nested = base and replaceSuper(member.Body, base) or member.Body
            table.insert(generated, `{name}.__setters.{member.Name} = function(self: any, {member.Params}){member.ReturnType ~= "" and ": " .. member.ReturnType or ""}`)
            local code = normalized(transpileSource(nested), "    ")
            if code ~= "" then table.insert(generated, code) end
            table.insert(generated, "end")
        end
        for _, operator in operators do
            local nested = base and replaceSuper(operator.Body, base) or operator.Body
            table.insert(generated, `function {name}.{operator.Name}(self: any{trim(operator.Params) ~= "" and ", " .. (operator.Params:match("^%s*[%a_][%w_]*%s*$") and trim(operator.Params) .. ": any" or operator.Params) or ""})`)
            local code = normalized(transpileSource(nested), "    ")
            if code ~= "" then table.insert(generated, code) end
            table.insert(generated, "end")
        end
        for _, method in methods do
            if base and parentFinalMethods then table.insert(generated, `if {base}.__finalMethods and {base}.__finalMethods["{method.Name}"] then error("Cannot override final method '{method.Name}'") end`) end
            if base and method.Override then table.insert(generated, `if not {base}.{method.Name} then error("No inherited method '{method.Name}' to override") end`) end
            local nested = base and replaceSuper(method.Body, base, not method.Static) or method.Body
            table.insert(generated, `{method.Attributes ~= "" and method.Attributes .. "\n" or ""}{method.Kind == "async function" and "async " or ""}function {name}.{method.Name}({method.Static and method.Params or "self: any" .. (trim(method.Params) ~= "" and ", " .. method.Params or "")}){method.ReturnType ~= "" and ": " .. method.ReturnType or ""}`)
            local code = normalized(transpileSource(nested), "    ")
            if method.Abstract then
                table.insert(generated, `    error("Abstract method '{method.Name}' must be overridden")`)
            elseif code ~= "" then
                table.insert(generated, code)
            end
            table.insert(generated, "end")
        end
        source = source:sub(1, declarationStart - 1) .. table.concat(generated, "\n") .. source:sub(closing.Finish + 1)
    end
end

local function transpileNamespaces(source: string): string
    while true do
        local start = findKeyword(source, "namespace")
        if not start then return source end
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then error("Namespace body expected") end
        local name = trim(source:sub(start, headerEnd - 1)):match("^namespace%s+([%a_][%w_]*)$")
        if not name then error("Invalid namespace declaration") end
        local closing = findBlock(source, start)
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local output = {}
        local depth = 0
        for _, line in splitLines(body) do
            local raw = line.Text
            local code = trim(maskNonCode(raw))
            local fn = depth == 0 and (code:match("^function%s+([%a_][%w_]*)%s*%b()%s*$") or code:match("^function%s+([%a_][%w_]*)%s*%b()%s*:%s*[%a_][%w_]*%s*$") or code:match("^async%s+function%s+([%a_][%w_]*)%s*%b()%s*$") or code:match("^async%s+function%s+([%a_][%w_]*)%s*%b()%s*:%s*[%a_][%w_]*%s*$")) or nil
            local field = depth == 0 and code:match("^([%a_][%w_]*)%s*=%s*.+$") or nil
            if fn then
                local newLine
                if code:match("^async%s+function%s+") then
                    newLine = raw:gsub("function%s+" .. fn, "function " .. name .. "." .. fn, 1)
                else
                    newLine = raw:gsub("function%s+" .. fn, name .. "." .. fn .. " = function", 1)
                end
                table.insert(output, newLine)
            elseif field then
                local newLine = raw:gsub("^([ \t]*)" .. field, "%1" .. name .. "." .. field, 1)
                table.insert(output, newLine)
            else
                table.insert(output, raw)
            end
            if blockStart(code) then depth += 1 end
            if code:match("^end%s*;?%s*$") or code:match("^until%s+") then depth -= 1 end
        end
        local transformed = normalized(transpileSource(table.concat(output, "\n")), "    ")
        local lineStart = (source:sub(1, start - 1):match(".*()\n") or 0) + 1
        local prefix = trim(source:sub(lineStart, start - 1))
        if prefix == "return" then
            local indentation = source:sub(lineStart, start - 1):match("^([ \t]*)") or ""
            local block = "do\n    local " .. name .. " = {}\n" .. transformed .. "\n    return " .. name .. "\nend"
            source = source:sub(1, lineStart - 1) .. indentation .. block .. source:sub(closing.Finish + 1)
        elseif prefix == "" then
            local block = "local " .. name .. " = {}\ndo\n" .. transformed .. "\nend"
            source = source:sub(1, start - 1) .. block .. source:sub(closing.Finish + 1)
        else
            error("namespace must be standalone or directly returned")
        end
    end
end

transpileSource = function(source: string): string
    if source:find("enum", 1, true) then source = transpileEnums(source) end
    if source:find("namespace", 1, true) then source = transpileNamespaces(source) end
    if source:find("class", 1, true) then source = transpileClasses(source) end
    if source:find("new", 1, true) then source = transpileNew(source) end
    return source
end

local function replaceRange(source: string, first: number, last: number, replacement: string): string
    return source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
end

local function transpileExports(source: string): (string, {string}, string?)
    local names = {}
    local seen = {}
    local rows = {}
    local className: string? = nil
    for _, row in splitLines(source) do
        local raw = row.Text
        if not raw:find("export", 1, true) then
            table.insert(rows, raw)
            continue
        end
        local masked = trim(maskNonCode(raw))
        if not masked:match("^export%s+") or masked:match("^export%s+type%s+") then
            table.insert(rows, raw)
            continue
        end
        local indent, rest = raw:match("^([ \t]*)export%s+(.+)$")
        if not rest then error("Invalid export statement") end
        local name = rest:match("^final%s+class%s+([%a_][%w_]*)") or rest:match("^abstract%s+class%s+([%a_][%w_]*)")
            or rest:match("^class%s+([%a_][%w_]*)") or rest:match("^enum%s+([%a_][%w_]*)")
            or rest:match("^namespace%s+([%a_][%w_]*)") or rest:match("^async%s+function%s+([%a_][%w_]*)")
            or rest:match("^function%s+([%a_][%w_]*)") or rest:match("^local%s+function%s+([%a_][%w_]*)")
            or rest:match("^local%s+async%s+function%s+([%a_][%w_]*)") or rest:match("^local%s+([%a_][%w_]*)%s*=") or rest:match("^local%s+([%a_][%w_]*)%s*:%s*.-%s*=")
        if not name then error(`Unsupported export declaration: {rest}`) end
        local isClass = rest:match("^class%s+") ~= nil or rest:match("^final%s+class%s+") ~= nil or rest:match("^abstract%s+class%s+") ~= nil
        if isClass and className then error(`Only one export class is allowed per module (already exported '{className}', found '{name}')`) end
        if seen[name] then error(`Duplicate export '{name}'`) end
        if (isClass and #names > 0) or (not isClass and className ~= nil) then error("An exported class must be the only export in its module") end
        if isClass then className = name end
        seen[name] = true
        table.insert(names, name)
        table.insert(rows, indent .. rest)
    end
    return table.concat(rows, "\n"), names, className
end

local function transpileImports(source: string): string
    local result = {}
    for _, row in splitLines(source) do
        local raw = row.Text
        local line = trim(raw)
        if not raw:find("import", 1, true) or not trim(maskNonCode(raw)):match("^import%f[%W]") then
            table.insert(result, raw)
            continue
        end
        local name, alias, path = line:match('^import%s+([%a_][%w_]*)%s+as%s+([%a_][%w_]*)%s+from%s+"([^"\n]+)"%s*$')
        if not name then name, alias, path = line:match("^import%s+([%a_][%w_]*)%s+as%s+([%a_][%w_]*)%s+from%s+'([^'\n]+)'%s*$") end
        if not name then name, path = line:match('^import%s+([%a_][%w_]*)%s+from%s+"([^"\n]+)"%s*$') end
        if not name then name, path = line:match("^import%s+([%a_][%w_]*)%s+from%s+'([^'\n]+)'%s*$") end
        local named, namedPath = line:match('^import%s+[{](.-)[}]%s+from%s+"([^"\n]+)"%s*$')
        if not named then named, namedPath = line:match("^import%s+[{](.-)[}]%s+from%s+'([^'\n]+)'%s*$") end
        if not name and not named then error("Expected import Name [as Alias] or import {Name} from \"./Module\"") end
        path = path or namedPath
        if path:sub(1, 2) ~= "./" and path:sub(1, 3) ~= "../" then error("Import path must be relative to script: ./ or ../") end
        local current = "script.Parent"
        local rest = path
        while rest:sub(1, 3) == "../" do
            current ..= ".Parent"
            rest = rest:sub(4)
        end
        if rest:sub(1, 2) == "./" then rest = rest:sub(3) end
        if rest == "" then error("Import must name a ModuleScript") end
        for segment in rest:gmatch("[^/]+") do
            if not segment:match("^[%a_][%w_]*$") then error(`Invalid module path segment '{segment}'`) end
            current ..= `:WaitForChild("{segment}")`
        end
        local indent = raw:match("^[ \t]*") or ""
        if named then
            local locals = {}
            local used = {}
            for segment in named:gmatch("[^,]+") do
                local external, alias = trim(segment):match("^([%a_][%w_]*)%s+as%s+([%a_][%w_]*)$")
                if not external then external = trim(segment); alias = external end
                if not external:match("^[%a_][%w_]*$") or used[alias] then error(`Invalid or duplicate import '{segment}'`) end
                used[alias] = true
                table.insert(locals, {External = external, Local = alias})
            end
            if #locals == 0 then error("Named import cannot be empty") end
            local temporary = `__lauaImported{#result + 1}`
            table.insert(result, indent .. `local {temporary} = require({current})`)
            for _, entry in locals do table.insert(result, indent .. `local {entry.Local} = {temporary}.{entry.External}`) end
        else
            table.insert(result, indent .. `local {alias or name} = require({current})`)
        end
    end
    return table.concat(result, "\n")
end

local function transpileDestructuring(source: string): string
    local result = {}
    local serial = 0
    for _, row in splitLines(source) do
        local raw = row.Text
        if not trim(maskNonCode(raw)):match("^local%s*[{]") then
            table.insert(result, raw)
            continue
        end
        local indent, names, expression = raw:match("^([ \t]*)local%s*[{]([^{}]+)[}]%s*=%s*(.-)%s*$")
        if not names or trim(expression) == "" then error("Expected local {a, b} = tableExpression") end
        serial += 1
        local temporary = `__lauaDestructure{serial}`
        table.insert(result, indent .. `local {temporary} = {expression}`)
        local found = {}
        for segment in names:gmatch("[^,]+") do
            local key, alias = trim(segment):match("^([%a_][%w_]*)%s*:%s*([%a_][%w_]*)$")
            if not key then key = trim(segment); alias = key end
            if not key:match("^[%a_][%w_]*$") or found[alias] then error(`Invalid or duplicate destructured name '{segment}'`) end
            found[alias] = true
            table.insert(result, indent .. `local {alias} = {temporary}.{key}`)
        end
    end
    return table.concat(result, "\n")
end

local function splitPatternFields(source: string): {string}
    local fields = {}
    local depth = 0
    local start = 1
    local masked = maskNonCode(source)
    for index = 1, #masked do
        local char = masked:sub(index, index)
        if char == "{" then depth += 1 end
        if char == "}" then depth -= 1 end
        if depth < 0 then error("Invalid match table pattern") end
        if char == "," and depth == 0 then
            table.insert(fields, trim(source:sub(start, index - 1)))
            start = index + 1
        end
    end
    if depth ~= 0 then error("Unclosed match table pattern") end
    table.insert(fields, trim(source:sub(start)))
    return fields
end

local function matchPatternCondition(value: string, pattern: string): string
    pattern = trim(pattern)
    if pattern:sub(1, 1) ~= "{" then return `{value} == {pattern}` end
    if pattern:sub(-1) ~= "}" then error("Unclosed match table pattern") end
    local parts = {`type({value}) == "table"`}
    local contents = trim(pattern:sub(2, -2))
    if contents == "" then return `({table.concat(parts, " and ")})` end
    local fields = splitPatternFields(contents)
    local seen = {}
    for _, part in fields do
        local name, expected = part:match("^([%a_][%w_]*)%s*=%s*(.+)$")
        if not name then error(`Invalid match table pattern field: {part}`) end
        if seen[name] then error(`Duplicate match table field '{name}'`) end
        seen[name] = true
        table.insert(parts, matchPatternCondition(value .. "." .. name, expected))
    end
    return "(" .. table.concat(parts, " and ") .. ")"
end

local function matchBranchCondition(value: string, expression: string): string
    local pattern, guard = expression:match("^(.-)%s+if%s+(.+)$")
    if not pattern then pattern = expression end
    local condition = matchPatternCondition(value, pattern)
    if guard then condition ..= " and (" .. guard .. ")" end
    return condition
end

local function transpileMatches(source: string): string
    local serial = 0
    local lookupDefinitions = {}
    while true do
        local masked = maskNonCode(source)
        local start = nil
        local from = 1
        while true do
            local position = findKeyword(source:sub(from), "match")
            if not position then break end
            position += from - 1
            local lineStart = (source:sub(1, position - 1):match(".*()\n") or 0) + 1
            if trim(masked:sub(lineStart, position - 1)) == "" then start = position end
            from = position + 5
        end
        if not start then
            if #lookupDefinitions == 0 then return source end
            -- Keep leading Luau --! directives before generated declarations.
            local prefixEnd = 0
            local cursor = 1
            while true do
                local lineEnd = source:find("\n", cursor, true)
                if not lineEnd or not source:sub(cursor, lineEnd - 1):match("^%s*%-%-!") then break end
                prefixEnd = lineEnd
                cursor = lineEnd + 1
            end
            return source:sub(1, prefixEnd) .. table.concat(lookupDefinitions, "\n") .. "\n" .. source:sub(prefixEnd + 1)
        end
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then error("match needs case branches") end
        local expression = trim(source:sub(start + 5, headerEnd - 1))
        if expression == "" then error("match requires an expression") end
        local closing = findBlock(source, start)
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local branches = {}
        local active = nil
        local depth = 0
        for _, row in splitLines(body) do
            local code = trim(maskNonCode(row.Text))
            local case = trim(row.Text):match("^case%s+(.+)$")
            local isDefault = code:match("^default%s*$") ~= nil
            if depth == 0 and (code:match("^case%f[%W]") or isDefault) then
                if code:match("^case%f[%W]") and (not case or trim(case) == "") then error("case requires a value") end
                if isDefault and #branches == 0 then error("default must follow a case") end
                if isDefault then
                    for _, branch in branches do if branch.Default then error("Duplicate default branch") end end
                elseif active and active.Default then error("case cannot follow default") end
                active = {Value = case, Default = isDefault, Lines = {}}
                table.insert(branches, active)
            elseif active then
                table.insert(active.Lines, row.Text)
            elseif code ~= "" then error("match body requires case or default") end
            if blockStart(code) then depth += 1 end
            if code:match("^end%s*;?%s*$") or code:match("^until%s+") then depth -= 1 end
        end
        if #branches == 0 then error("match requires at least one case") end
        -- Literal-only match branches that return constants can be dispatched
        -- through a module-level lookup table, avoiding an elseif chain.
        local lookupEntries = {}
        local seenKeys = {}
        local lookupDefault = nil
        local canLookup = #branches >= 3 and branches[#branches].Default
        if canLookup then
            for _, branch in branches do
                local value = trim(table.concat(branch.Lines, "\n")):match("^return%s+(.+)$")
                if not value or not (value:match("^%-?%d+%.?%d*$") or value == "true" or value == "false" or value == "nil" or value:match('^"[^"\\\n]*"$') or value:match("^'[^'\\\n]*'$") ) then
                    canLookup = false
                    break
                end
                if branch.Default then
                    lookupDefault = value
                else
                    local key = trim(branch.Value):match('^"([%w_]+)"$') or trim(branch.Value):match("^'([%w_]+)'$")
                    if not key or seenKeys[key] or value == "nil" then
                        canLookup = false
                        break
                    end
                    seenKeys[key] = true
                    table.insert(lookupEntries, `["{key}"] = {value}`)
                end
            end
        end
        if canLookup then
            serial += 1
            local tableName = `__lauaStaticMatch{serial}`
            while source:find(tableName, 1, true) do
                serial += 1
                tableName = `__lauaStaticMatch{serial}`
            end
            table.insert(lookupDefinitions, "local " .. tableName .. " = {" .. table.concat(lookupEntries, ", ") .. "}")
            local keyName, resultName = tableName .. "_key", tableName .. "_result"
            local lines = {"do", `    local {keyName} = {expression}`, `    local {resultName} = {tableName}[{keyName}]`, `    if {resultName} ~= nil then return {resultName} end`, `    return {lookupDefault}`, "end"}
            source = replaceRange(source, start, closing.Finish, table.concat(lines, "\n"))
            continue
        end
        serial += 1
        local variable = `__lauaMatch{serial}`
        local generated = {"do", `    local {variable} = {expression}`}
        for index, branch in branches do
            if branch.Default then
                table.insert(generated, "    else")
            else
                table.insert(generated, `    {index == 1 and "if" or "elseif"} {matchBranchCondition(variable, branch.Value)} then`)
            end
            local content = normalized(table.concat(branch.Lines, "\n"), "        ")
            if content ~= "" then table.insert(generated, content) end
        end
        table.insert(generated, "    end")
        table.insert(generated, "end")
        source = replaceRange(source, start, closing.Finish, table.concat(generated, "\n"))
    end
end

local function expressionLeft(masked: string, endAt: number): number?
    local cursor = endAt
    while cursor > 0 and masked:sub(cursor, cursor):match("%s") do cursor -= 1 end
    if cursor == 0 then return nil end
    local endChar = masked:sub(cursor, cursor)
    if endChar == ")" or endChar == "]" then
        local opener = endChar == ")" and "(" or "["
        local depth = 1
        cursor -= 1
        while cursor >= 1 do
            local char = masked:sub(cursor, cursor)
            if char == endChar then depth += 1 end
            if char == opener then depth -= 1 end
            if depth == 0 then break end
            cursor -= 1
        end
        if cursor < 1 then return nil end
        local prev = cursor - 1
        while prev > 0 and masked:sub(prev, prev):match("[ \t]") do prev -= 1 end
        if masked:sub(prev, prev):match("[%w_]") then return expressionLeft(masked, prev) end
        return cursor
    end
    if not endChar:match("[%w_]") then return nil end
    while cursor > 0 and masked:sub(cursor, cursor):match("[%w_]") do cursor -= 1 end
    local beginning = cursor + 1
    if beginning > 1 and (masked:sub(beginning - 1, beginning - 1) == "." or masked:sub(beginning - 1, beginning - 1) == ":") then
        local previous = expressionLeft(masked, beginning - 2)
        if previous then return previous end
    end
    return beginning
end

local function expressionRight(source: string, startAt: number): number?
    local cursor = startAt
    while cursor <= #source and source:sub(cursor, cursor):match("[ \t]") do cursor += 1 end
    local first = source:sub(cursor, cursor)
    if first == "'" or first == '"' then
        local quote = first
        cursor += 1
        while cursor <= #source do
            local char = source:sub(cursor, cursor)
            if char == "\\" then cursor += 2 elseif char == quote then cursor += 1; break else cursor += 1 end
        end
    elseif first == "(" then
        local depth = 1
        cursor += 1
        while cursor <= #source and depth > 0 do
            local char = source:sub(cursor, cursor)
            if char == "(" then depth += 1 elseif char == ")" then depth -= 1 end
            cursor += 1
        end
        if depth ~= 0 then return nil end
    else
        local prefix = source:sub(cursor):match("^[%a_][%w_]*") or source:sub(cursor):match("^%-?[%d%.]+")
        if not prefix then return nil end
        cursor += #prefix
    end
    while cursor <= #source do
        local suffix = source:sub(cursor):match("^%s*[%.:]([%a_][%w_]*)")
        local spaces = source:sub(cursor):match("^[ \t]*") or ""
        if suffix then
            cursor += #spaces + 1 + #suffix
        elseif source:sub(cursor + #spaces, cursor + #spaces) == "(" then
            cursor += #spaces + 1
            local depth = 1
            while cursor <= #source and depth > 0 do
                local char = source:sub(cursor, cursor)
                if char == "(" then depth += 1 elseif char == ")" then depth -= 1 end
                cursor += 1
            end
            if depth ~= 0 then return nil end
        else
            break
        end
    end
    return cursor - 1
end

local function transpileOptional(source: string): (string, boolean)
    if source:find("\n", 1, true) and source:find("?.", 1, true) and not source:find("??", 1, true) and not source:find("--", 1, true) and not source:find("[\"'`]", 1) and not source:find("\r", 1, true) then
        local lines = splitLines(source)
        local eligible = true
        for _, line in lines do
            if line.Text:find("?.", 1, true) and not line.Text:match("^[ \t]*local%s+[%a_][%w_]*%s*=%s*[%a_][%w_]*%?%.[%a_][%w_]*[ \t]*$") then
                eligible = false
                break
            end
        end
        if eligible then
            local output = {}
            for _, line in lines do
                table.insert(output, line.Text:find("?.", 1, true) and (transpileOptional(line.Text)) or line.Text)
            end
            return table.concat(output, "\n"), true
        end
    end
    local changed = false
    local masked = maskNonCode(source)
    local function rewrite(first: number, last: number, replacement: string)
        source = replaceRange(source, first, last, replacement)
        masked = replaceRange(masked, first, last, maskNonCode(replacement))
    end
    while true do
        local pos = masked:find("?.", 1, true)
        if not pos then return source, changed end
        local left = expressionLeft(masked, pos - 1)
        local member = masked:sub(pos + 2):match("^([%a_][%w_]*)")
        if not left then error("Optional chaining requires a receiver") end
        if masked:sub(pos+2,pos+2) == "(" then
            local depth, closing = 1, nil
            for i = pos+3, #masked do
                local char = masked:sub(i,i)
                if char == "(" then depth += 1 elseif char == ")" then depth -= 1 end
                if depth == 0 then closing = i; break end
            end
            if not closing then error("Unclosed optional function call") end
            local receiver = trim(source:sub(left,pos-1))
            local args = source:sub(pos+3,closing-1)
            rewrite(left,closing,"__lauaCore.optionalCall(" .. receiver .. ", function(__lauaReceiver) return __lauaReceiver(" .. args .. ") end)")
            changed = true
            continue
        end
        if masked:sub(pos+2,pos+2) == "[" then
            local depth, closing = 1, nil
            for i = pos+3, #masked do
                local char = masked:sub(i,i)
                if char == "[" then depth += 1 elseif char == "]" then depth -= 1 end
                if depth == 0 then closing = i; break end
            end
            if not closing then error("Unclosed optional index") end
            local key = trim(source:sub(pos+3,closing-1))
            if key == "" then error("Optional index requires a key") end
            local receiver = trim(source:sub(left,pos-1))
            rewrite(left,closing,'__lauaCore.optionalIndex(' .. receiver .. ', function() return ' .. key .. ' end)')
            changed = true
            continue
        end
        local colon = masked:sub(pos+2,pos+2) == ":"
        if colon then member = masked:sub(pos+3):match("^([%a_][%w_]*)") end
        if not member then error("Optional chaining expects a property, index, or method") end
        local memberEnd = pos + 1 + #member + (colon and 1 or 0)
        local gap = masked:sub(memberEnd + 1):match("^[ \t]*") or ""
        local openAt = memberEnd + 1 + #gap
        if masked:sub(openAt,openAt) == "(" then
            local depth, closing = 1, nil
            for i = openAt+1, #masked do
                local char = masked:sub(i,i)
                if char == "(" then depth += 1 elseif char == ")" then depth -= 1 end
                if depth == 0 then closing = i; break end
            end
            if not closing then error("Unclosed optional method call") end
            local receiver = trim(source:sub(left,pos-1))
            local args = source:sub(openAt+1,closing-1)
            local invocation = "(__lauaMethod :: ((...any) -> any))(" .. (colon and ("__lauaReceiver" .. (trim(args) ~= "" and ", " or "")) or "") .. args .. ")"
            local lookup = "local __lauaMethod = __lauaCore.optional(__lauaReceiver, \"" .. member .. "\"); if __lauaMethod == nil then return nil end; "
            rewrite(left,closing,"__lauaCore.optionalCall(" .. receiver .. ", function(__lauaReceiver) " .. lookup .. "return " .. invocation .. " end)")
            changed = true
            continue
        end
        if colon then error("Optional colon access requires a method call") end
        local base = trim(source:sub(left, pos - 1))
        local replacement = `__lauaCore.optional({base}, "{member}")`
        rewrite( left, pos + 1 + #member, replacement)
        changed = true
    end
end

local function transpileCoalescingAssign(source: string): string
    local output = {}
    local serial = 0
    for _, row in splitLines(source) do
        local raw = row.Text
        local masked = maskNonCode(raw)
        local at = masked:find("??=", 1, true)
        if not at then
            table.insert(output, raw)
            continue
        end
        local indent = raw:match("^[ \t]*") or ""
        local target = trim(raw:sub(1, at - 1))
        local fallback = trim(raw:sub(at + 3))
        if fallback == "" then error("??= requires a fallback value") end
        local closure = fallback:find("--", 1, true) and ("\n" .. indent .. "end") or " end"
        if target:match("^[%a_][%w_]*$") then
            table.insert(output, indent .. `if {target} == nil then {target} = {fallback}{closure}`)
        else
            serial += 1
            local receiver, member = target:match("^(.-)%.([%a_][%w_]*)$")
            local key = nil
            if not receiver then receiver, key = target:match("^(.-)%[([^%[%]]+)%]$") end
            if not receiver or trim(receiver) == "" then error("??= expects a variable, property or indexed target") end
            local temporary = `__lauaAssignTarget{serial}`
            local index = member and ("." .. member) or (`[{key}]`)
            if key then
                local keyTemp = `__lauaAssignKey{serial}`
                table.insert(output, indent .. `do local {temporary} = {receiver}; local {keyTemp} = {key}; if {temporary}[{keyTemp}] == nil then {temporary}[{keyTemp}] = {fallback}{closure} end`)
            else
                table.insert(output, indent .. `do local {temporary} = {receiver}; if {temporary}{index} == nil then {temporary}{index} = {fallback}{closure} end`)
            end
        end
    end
    return table.concat(output, "\n")
end

local function transpileCoalescing(source: string): (string, boolean)
    if source:find("\n", 1, true) and source:find("??", 1, true) and not source:find("--", 1, true) and not source:find("[\"'`]", 1) and not source:find("\r", 1, true) then
        local lines = splitLines(source)
        local eligible = true
        for _, line in lines do
            if line.Text:find("??", 1, true)
               and not line.Text:match("^[ \t]*local%s+[%a_][%w_]*%s*=%s*[%a_][%w_]*%s*%?%?%s*[%a_][%w_]*[ \t]*$")
               and not line.Text:match("^[ \t]*local%s+[%a_][%w_]*%s*=%s*[%a_][%w_]*%s*%?%?%s*%d+%.?%d*[ \t]*$") then
                eligible = false
                break
            end
        end
        if eligible then
            local output = {}
            for _, line in lines do
                table.insert(output, line.Text:find("??", 1, true) and (transpileCoalescing(line.Text)) or line.Text)
            end
            return table.concat(output, "\n"), true
        end
    end
    local changed = false
    local masked = maskNonCode(source)
    while true do
        local pos = nil
        local cursor = 1
        while true do
            local nextPos = masked:find("??", cursor, true)
            if not nextPos then break end
            pos = nextPos
            cursor = nextPos + 2
        end
        if not pos then return source, changed end
        local left = expressionLeft(masked, pos - 1)
        local right = expressionRight(source, pos + 2)
        local preceding = masked:sub(1, pos - 1)
        local lineStart = (preceding:match(".*()\n") or 0) + 1
        local continuation = trim(masked:sub(lineStart, pos - 1)) == ""
        if continuation and right then
            local endAt = masked:find("\n", pos + 2, true) or (#masked + 1)
            local visible = masked:sub(pos + 2, endAt - 1):gsub("%s+$", "")
            if visible ~= "" then right = pos + 1 + #visible end
        end
        if not left or not right then error("Nil coalescing expects value ?? fallback") end
        local before = trim(masked:sub(math.max(1, left - 8), left - 1))
        local after = trim(masked:sub(right + 1):match("^[^\n]*") or "")
        if before:match("[%+%-%*/%%%^<>~&|]$") or (before:match("%f[%a]and$") or before:match("%f[%a]or$")) then
            error("Wrap compound ?? left operands in parentheses")
        end
        if after:match("^[%+%-%*/%%%^<>=~&|]") or after:match("^%.%.") or (after:match("^and%f[%W]") or after:match("^or%f[%W]")) then
            error("Wrap compound ?? fallbacks in parentheses")
        end
        local a = trim(source:sub(left, pos - 1))
        local b = trim(source:sub(pos + 2, right))
        -- Simple identifiers can use a lazy Luau if-expression without
        -- allocating a closure or loading the coalesce runtime helper.
        -- Keep the helper for complex left operands to evaluate them once.
        local replacement: string
        if b == "nil" and a:match("^[%a_][%w_]*$") then
            replacement = a
        elseif a:match("^[%a_][%w_]*$") and (b:match("^[%a_][%w_]*$") or (b:match("^%d[%d_]*$") or b:match("^%d[%d_]*%.%d[%d_]*$")) or b:match("^0[xX][%da-fA-F_]+$") or b:match("^0[bB][01_]+$")) and a ~= "true" and a ~= "false" and a ~= "nil" then
            replacement = `(if {a} ~= nil then {a} else {b})`
        else
            replacement = `__lauaCore.coalesce({a}, function() return {b} end)`
        end
        source = replaceRange(source, left, right, replacement)
        masked = replaceRange(masked, left, right, maskNonCode(replacement))
        changed = true
    end
end


-- Transform only non-comment/non-string tokens, so keywords in user data are not rewritten.
local function transpileIsOperator(source: string): string
    local position = 1
    while true do
        local masked = maskNonCode(source)
        local first, last = masked:find('%f[%w]is%f[%W]', position)
        if not first then return source end
        local before = masked:sub(first - 1, first - 1)
        local linePrefix = masked:sub((masked:sub(1,first-1):match('.*()\n') or 0) + 1, first-1)
        if before == '.' or before == ':' or linePrefix:match('function%s+$') or linePrefix:match('local%s+$') or linePrefix:match('const%s+$') then position = last + 1; continue end
        local rightText = masked:sub(last + 1)
        local spacing, className = rightText:match('^([ \t]+)([%a_][%w_]*)')
        if not className or className == "then" or className == "and" or className == "or" or className == "end" then position = last + 1; continue end
        local left = expressionLeft(masked, first - 1)
        if not left then position = last + 1; continue end
        local after = last + #spacing + #className
        local beforeValue = trim(source:sub(left, first - 1))
        source = replaceRange(source, left, after, '__lauaCore.is(' .. beforeValue .. ', ' .. className .. ')')
        position = left + 15
    end
end

-- Pipeline stages must be named functions. Side effects in the input run once.
local function transpilePipelines(source: string): string
    local result = {}
    for _, line in splitLines(source) do
        local raw = line.Text
        if not raw:find('|>', 1, true) then table.insert(result, raw); continue end
        local masked = maskNonCode(raw)
        if not masked:find('|>', 1, true) then table.insert(result, raw); continue end
        local separators = {}
        local cursor = 1
        while true do
            local at = masked:find('|>', cursor, true)
            if not at then break end
            table.insert(separators, at)
            cursor = at + 2
        end
        local before = raw:sub(1, separators[1] - 1)
        local assignment, initial = before:match('^(.-=%s*)(.+)$')
        if not assignment then
            assignment = before:match('^(%s*return%s+)')
            initial = assignment and before:sub(#assignment + 1) or nil
        end
        if not assignment then error('Pipeline requires assignment or return: local x = value |> Function') end
        local value = trim(initial or '')
        if value == '' then error('Pipeline input is empty') end
        for index, at in separators do
            local ending = separators[index + 1] and separators[index + 1] - 1 or #raw
            local stage = trim(raw:sub(at + 2, ending))
            if not stage:match('^[%a_][%w_%.]*$') then error('Pipeline stages must be function names') end
            value = stage .. '(' .. value .. ')'
        end
        table.insert(result, assignment .. value)
    end
    return table.concat(result, '\n')
end

-- Memoized functions use the bundled LauaCore runtime.
local function transpileMemo(source: string): string
    local position = 1
    while true do
        local masked = maskNonCode(source)
        local first = masked:find('%f[%w]memo%f[%W]', position)
        if not first then return source end
        local lineStart = (source:sub(1, first-1):match('.*()\n') or 0) + 1
        local previous = masked:sub(first-1, first-1)
        local headerEnd = source:find('\n', first, true)
        if previous == '.' or previous == ':' or trim(source:sub(lineStart, first-1)) ~= '' or not headerEnd then
            position = first + 4
            continue
        end
        local header = trim(source:sub(first, headerEnd-1))
        local funcName = header:match('^memo%s+function%s+([%a_][%w_]*)%s*%(')
            or header:match('^memo%s+local%s+function%s+([%a_][%w_]*)%s*%(')
        if not funcName then position = first + 4; continue end
        local standardHeader = header:gsub('^memo%s+', '', 1)
        local rewritten = source:sub(1, first-1) .. standardHeader .. source:sub(headerEnd)
        local finish = findBlock(rewritten, first)
        local indent = source:sub(lineStart, first-1)
        local wrapper = '\n' .. indent .. funcName .. ' = __lauaCore.memo(' .. funcName .. ')'
        local tail = rewritten:sub(finish.Finish + 1)
        if #tail > 0 and tail:sub(1, 1) ~= "\n" then wrapper ..= "\n" end
        source = rewritten:sub(1, finish.Finish) .. wrapper .. tail
        position = first + #funcName
    end
end

-- Convert Laua's cache-control operator without touching strings/comments.
local function transpileMemoClear(source: string): string
    local position = 1
    while true do
        local masked = maskNonCode(source)
        local first, last = masked:find("memo%s*%.%s*clear%s*%(", position)
        if not first then return source end
        local before = masked:sub(first - 1, first - 1)
        if before:match("[%w_%.:]") then
            position = last + 1
            continue
        end
        local replacement = "__lauaCore.clearMemo("
        source = source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
        position = first + #replacement
    end
end

-- Parameter defaults must split only on top-level commas, not table/call/type commas.
local function splitDefaultParameters(params: string): {string}
    local masked = maskNonCode(params)
    local pieces = {}
    local stack = {}
    local start = 1
    local typeArguments = 0
    local inType = false
    for i = 1, #masked do
        local char = masked:sub(i, i)
        if char == "(" then table.insert(stack, ")")
        elseif char == "{" then table.insert(stack, "}")
        elseif char == "[" then table.insert(stack, "]")
        elseif char == ")" or char == "}" or char == "]" then
            if table.remove(stack) ~= char then error("Unbalanced default parameter expression") end
        elseif #stack == 0 then
            if char == ":" and typeArguments == 0 then inType = true
            elseif char == "=" and typeArguments == 0 then inType = false
            elseif char == "<" and inType then typeArguments += 1
            elseif char == ">" and typeArguments > 0 then typeArguments -= 1
            elseif char == "," and typeArguments == 0 then
                table.insert(pieces, params:sub(start, i - 1))
                start = i + 1
                inType = false
            end
        end
    end
    if #stack > 0 or typeArguments ~= 0 then error("Unclosed default parameter expression") end
    table.insert(pieces, params:sub(start))
    return pieces
end

local function transpileParameterDefaults(source: string): string
    local rows = {}
    for _, row in splitLines(source) do
        local raw = row.Text
        if not raw:find("function", 1, true) or not raw:find("=", 1, true) then table.insert(rows, raw); continue end
        local masked = maskNonCode(raw)
        local openAt = masked:find('%f[%w]function%f[%W]')
        if not openAt then table.insert(rows, raw); continue end
        local parenAt = masked:find('(', openAt, true)
        if not parenAt then table.insert(rows, raw); continue end
        local closeAt = nil
        local depth = 0
        for i = parenAt, #masked do
            local char = masked:sub(i, i)
            if char == "(" then depth += 1
            elseif char == ")" then
                depth -= 1
                if depth == 0 then closeAt = i; break end
            end
        end
        if not closeAt then error("Unclosed function parameter list") end
        local params = raw:sub(parenAt + 1, closeAt - 1)
        if not params:find('=', 1, true) then table.insert(rows, raw); continue end
        local parsed, initializers = {}, {}
        for _, part in splitDefaultParameters(params) do
            local code = maskNonCode(part)
            local equals = code:find("=", 1, true)
            if not equals then table.insert(parsed, trim(part)); continue end
            local original = trim(part:sub(1, equals - 1))
            local default = trim(part:sub(equals + 1))
            local name, annotation = original:match('^([%a_][%w_]*)%s*:%s*(.+)$')
            if not name then name = original:match('^([%a_][%w_]*)$') end
            if not name or default == "" then error('Invalid default parameter') end
            local inferred = default:match("^%-?%d+%.?%d*$") and "number?"
                or (default:match('^".*"$') or default:match("^'.*'$") or default:match('^`.*`$')) and "string?"
                or (default == "true" or default == "false") and "boolean?" or "any"
            table.insert(parsed, annotation and original or (name .. ": " .. inferred))
            table.insert(initializers, (`if {name} == nil then {name} = {default} end`))
        end
        if #initializers == 0 then table.insert(rows, raw); continue end
        table.insert(rows, raw:sub(1, parenAt) .. table.concat(parsed, ', ') .. raw:sub(closeAt))
        local indent = (raw:match('^[ \t]*') or '') .. '    '
        for _, statement in initializers do table.insert(rows, indent .. statement) end
    end
    return table.concat(rows, "\n")
end

-- Compile-time branch selection; only these explicit directives have special meaning.
local function preprocessMode(source: string, mode: string): string
    local out, stack = {}, {}
    local active = true
    for _, row in splitLines(source) do
        local line = row.Text
        local flag = line:match('^%s*%-%-#if%s+(%u+)%s*$')
        if flag then
            if flag ~= 'DEBUG' and flag ~= 'RELEASE' and flag ~= 'DEVELOPMENT' then error('Unknown --#if mode ' .. flag) end
            table.insert(stack, {Parent=active, Matched=mode:upper()==flag, Else=false})
            active = active and mode:upper()==flag
            table.insert(out, string.rep(' ', #line))
        elseif line:match('^%s*%-%-#else%s*$') then
            local top = stack[#stack]
            if not top or top.Else then error('Unexpected --#else') end
            top.Else = true
            active = top.Parent and not top.Matched
            table.insert(out, string.rep(' ', #line))
        elseif line:match('^%s*%-%-#end%s*$') then
            local top = table.remove(stack)
            if not top then error('Unexpected --#end') end
            active = top.Parent
            table.insert(out, string.rep(' ', #line))
        else
            table.insert(out,active and line or string.rep(' ', #line))
        end
    end
    if #stack > 0 then error('Missing --#end for compile-time branch') end
    return table.concat(out,'\n')
end

-- Laua: source-level sugar. Only fully supported forms are lowered.
-- Keep unsupported proposals from leaking malformed syntax into generated Luau.
local LAUA_PENDING_REASONS = {
            {"^[%a_][%w_]*:%s*(for|while|repeat)%s", "Labeled loop exits"},
            {"^break%s+[%a_][%w_]*$", "Labeled break"},
            {"^continue%s+[%a_][%w_]*$", "Labeled continue"},
            {"^unique%s+type%s+", "Nominal/unique types"},
            {"^type%s+[%a_][%w_]*%s*=%s*%[", "Typed positional tables"},
            {"^type%s+[%a_][%w_]*%s*=%s*truthy%s*$", "Truthy type aliases"},
            {"^type%s+[%a_][%w_]*%s*=%s*falsy%s*$", "Falsy type aliases"},
}

local function validatePendingFeatures(source: string)
    for _, row in splitLines(source) do
        local raw = row.Text
        if not (raw:find("for", 1, true) or raw:find("while", 1, true) or raw:find("repeat", 1, true) or raw:find("break", 1, true) or raw:find("continue", 1, true) or raw:find("unique", 1, true) or raw:find("type", 1, true) or raw:find("regex.", 1, true) or (raw:find("function", 1, true) and raw:find("<", 1, true))) then continue end
        local line = trim(maskNonCode(raw))
        local reasons = LAUA_PENDING_REASONS
        for _, entry in reasons do
            -- Plain pattern alternatives are handled explicitly below.
            if entry[2] ~= "Labeled loop exits" and line:match(entry[1]) then
                error(entry[2] .. " are specified for Laua but not yet implemented in the transpiler")
            end
        end
        if line:match("^[%a_][%w_]*:%s*for%s") or line:match("^[%a_][%w_]*:%s*while%s") or line:match("^[%a_][%w_]*:%s*repeat%s") then
            error("Labeled loop exits are specified for Laua but not yet implemented")
        end
        if line:match("^function%s+[%a_][%w_%.:]*%s*<[^>]*:%s*[%a_][%w_]*[^>]*>") then
            error("Constrained generics need a real type checker and are not yet implemented")
        end
        if line:find("regex.match", 1, true) or line:find("regex.find", 1, true) then
            error("Full regular expressions need a regex runtime and are not yet implemented")
        end
    end
end

local function transpileAdditionalSyntax(source: string): string
    local rows = {}
    local sequence = 0
    for _, row in splitLines(source) do
        local original = row.Text
        if not original:find("=>", 1, true) and not original:find("...", 1, true) and not original:find("[", 1, true) and not original:find("table.", 1, true) and not original:find("import", 1, true) and not original:find("@nolint", 1, true) then
            table.insert(rows, original)
            continue
        end
        local stripped = trim(original)
        local masked = trim(maskNonCode(original))
        local indent = original:match("^[ \t]*") or ""

        -- Editor-only @nolint is consumed here, not passed to Roblox.
        if stripped:match("^@nolint%s*%(") and masked:match("^@nolint%s*%(") then
            local names = stripped:match('^@nolint%s*%(%s*"([%w_, ]+)"%s*%)%s*$')
            if not names then error('Expected @nolint("WarningName")') end
            table.insert(rows, indent .. "-- Laua lint suppression: " .. names)
            continue
        end

        -- Single-expression lambda, with ordinary identifier parameters.
        if masked:find("=>", 1, true) then
            local prefix, params, expression = original:match("^(.-)(%b())%s*=>%s*(.-)%s*$")
            if not prefix or expression == "" then error("Arrow functions require (parameters) => expression on one line") end
            local inside = params:sub(2, -2)
            for item in inside:gmatch("[^,]+") do
                if not trim(item):match("^[%a_][%w_]*%s*:?%s*[%w_%.%?]*$") then error("Invalid arrow function parameter") end
            end
            original = prefix .. "function" .. params .. " return " .. expression .. " end"
        end

        -- The v22 spread form accepts spreads-only table literals on the RHS.
        if masked:find("%.%.%.[%a_]") and original:find("{", 1, true) then
            local prefix, values = original:match("^(.-)[{]%s*(%.%.%.[^{}]-)%s*[}]%s*$")
            if prefix and values then
                local parts = {}
                for part in values:gmatch("[^,]+") do
                    local variable = trim(part):match("^%.%.%.%s*([%a_][%w_%.]*)$")
                    if not variable then error('Spread literal expects {...first, ...second}') end
                    table.insert(parts, variable)
                end
                original = prefix .. '__lauaCore.spread(' .. table.concat(parts, ', ') .. ')'
            end
        end

        -- Slice supports a simple variable/property expression, with optional bounds.
        local before, owner, first, last, suffix = original:match("^(.-)([%a_][%w_%.]*)%[([%-%d]*)%s*:%s*([%-%d]*)%](.*)$")
        if owner and maskNonCode(original):find("%[%s*%-?%d*%s*:%s*%-?%d*%s*%]") then
            if first == "" and last == "" then error("Slice requires at least one bound") end
            original = before .. "__lauaCore.slice(" .. owner .. ", " .. (first ~= "" and first or "nil") .. ", " .. (last ~= "" and last or "nil") .. ")" .. suffix
        end

        -- Methods in the core runtime rather than mutating the built-in table library.
        for _, method in {"filter", "map", "reduce", "findWhere"} do
            if not original:find("table." .. method, 1, true) then continue end
            local maskedOriginal = maskNonCode(original)
            local search = 1
            while true do
                local found = maskedOriginal:find("table%." .. method .. "%s*%(", search)
                if not found then break end
                local before = found > 1 and maskedOriginal:sub(found - 1, found - 1) or ""
                if before:match("[%w_%.:]") then search = found + 1; continue end
                original = original:sub(1, found - 1) .. "__lauaCore." .. original:sub(found)
                maskedOriginal = maskNonCode(original)
                search = found + #"__lauaCore.table." + #method
            end
        end

        -- Explicit lazy import: require is delayed until the proxy is used.
        local alias, path = trim(original):match('^import%s+lazy%s+([%a_][%w_]*)%s+from%s+"([^"]+)"%s*$')
        if alias then
            if path:sub(1, 2) ~= "./" and path:sub(1, 3) ~= "../" then error("Lazy import paths must start with ./ or ../") end
            local target = "script.Parent"
            local rest = path
            while rest:sub(1, 3) == "../" do
                target ..= ".Parent"
                rest = rest:sub(4)
            end
            if rest:sub(1, 2) == "./" then rest = rest:sub(3) end
            if rest == "" then error("Lazy import path must name a ModuleScript") end
            for segment in rest:gmatch("[^/]+") do
                if not segment:match("^[%a_][%w_]*$") then error(`Invalid lazy import path segment '{segment}'`) end
                target ..= ':WaitForChild("' .. segment .. '")'
            end
            table.insert(rows, indent .. 'local ' .. alias .. ' = __lauaCore.lazyModule(function() return require(' .. target .. ') end)')
            continue
        end

        table.insert(rows, original)
    end
    return table.concat(rows, "\n")
end

local function transpileExtensions(source: string): string
    source = transpileImports(source)
    source = transpileDestructuring(source)
    source = transpileMatches(source)
    source = (transpileOptional(source))
    source = (transpileCoalescing(source))
    return source
end

local function transpileDefers(source: string): string
    local functionLines = {}
    for _, line in splitLines(source) do
        local code = trim(maskNonCode(line.Text))
        if code:match("^function%s+") or code:match("^local%s+function%s+") or code:match("^async%s+function%s+") or code:match("^local%s+async%s+function%s+") or code:match("=%s*function%s*%(") then
            local at = line.Start + (line.Text:find("function", 1, true) or 1) - 1
            table.insert(functionLines, at)
        end
    end

    for index = #functionLines, 1, -1 do
        local start = functionLines[index]
        local closing = findBlock(source, start)
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then continue end
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local deferBlocks = {}
        for _, line in splitLines(body) do
            if trim(maskNonCode(line.Text)) == "defer" then
                local at = line.Start + (line.Text:find("defer", 1, true) or 1) - 1
                local done = findBlock(body, at)
                local codeStart = body:find("\n", at, true)
                local content = codeStart and body:sub(codeStart + 1, done.Start - 1) or ""
                local replacement = `table.insert(__lauaDefers, function()\n{normalized(content, "    ")}\nend)`
                table.insert(deferBlocks, {Start = at, Finish = done.Finish, Replacement = replacement})
            end
        end
        if #deferBlocks == 0 then continue end
        for blockIndex = #deferBlocks, 1, -1 do
            local block = deferBlocks[blockIndex]
            body = body:sub(1, block.Start - 1) .. block.Replacement .. body:sub(block.Finish + 1)
        end
        local wrapped = table.concat({
            "local __lauaDefers: {() -> ...any} = {}",
            "local __lauaResult = table.pack(xpcall(function()",
            normalized(body, "    "),
            "end, function(err) return err end))",
            "local __lauaCleanupError = nil",
            "for __lauaIndex = #__lauaDefers, 1, -1 do",
            "    local __lauaOK, __lauaError = pcall(__lauaDefers[__lauaIndex])",
            "    if not __lauaOK and not __lauaCleanupError then __lauaCleanupError = __lauaError end",
            "end",
            "if __lauaCleanupError then error(__lauaCleanupError, 0) end",
            "if not __lauaResult[1] then error(__lauaResult[2], 0) end",
            "return table.unpack(__lauaResult, 2, __lauaResult.n)",
        }, "\n")
        source = source:sub(1, headerEnd) .. wrapped .. "\n" .. source:sub(closing.Start)
    end
    if maskNonCode(source):match("%f[%w]defer%f[%W]") then error("defer must be inside a function") end
    return source
end

local function transpileUsing(source: string): string
    local output = {}
    local rows = splitLines(source)
    local index = 1
    while index <= #rows do
        local raw = rows[index].Text
        local masked = trim(maskNonCode(raw))
        if masked:match("^using%f[%W]") then
            local name, expression = trim(raw):match("^using%s+([%a_][%w_]*)%s*=%s*(.+)$")
            if not name then error("using requires exactly one named resource: using name = expression") end
            local indent = raw:match("^[ \t]*") or ""
            local function openDelimiters(text: string): number
                local depth = 0
                for character in maskNonCode(text):gmatch(".") do
                    if character == "(" or character == "[" or character == "{" then depth += 1 end
                    if character == ")" or character == "]" or character == "}" then depth -= 1 end
                end
                return depth
            end
            while openDelimiters(expression) > 0 and index < #rows do
                index += 1
                expression ..= "\n" .. rows[index].Text
            end
            if openDelimiters(expression) ~= 0 then error("Unclosed using resource expression") end
            local code = {
                indent .. "local " .. name .. " = " .. expression,
                indent .. "defer",
                indent .. "    local __lauaResource: any = " .. name,
                indent .. "    if __lauaResource ~= nil then",
                indent .. "        if typeof(" .. "__lauaResource" .. ') == "RBXScriptConnection" then',
                indent .. "            " .. "(__lauaResource :: RBXScriptConnection):Disconnect()",
                indent .. "        elseif typeof(" .. "__lauaResource" .. ') == "Instance" then',
                indent .. "            " .. "(__lauaResource :: Instance):Destroy()",
                indent .. "        elseif type(" .. "__lauaResource" .. ') == "table" then',
                indent .. "            if type(" .. "__lauaResource" .. '.Dispose) == "function" then',
                indent .. "                local __lauaInvoke: (any) -> () = (__lauaResource.Dispose :: any)",
                indent .. "                __lauaInvoke(__lauaResource)",
                indent .. "            elseif type(" .. "__lauaResource" .. '.Disconnect) == "function" then',
                indent .. "                local __lauaInvoke: (any) -> () = (__lauaResource.Disconnect :: any)",
                indent .. "                __lauaInvoke(__lauaResource)",
                indent .. "            elseif type(" .. "__lauaResource" .. '.Destroy) == "function" then',
                indent .. "                local __lauaInvoke: (any) -> () = (__lauaResource.Destroy :: any)",
                indent .. "                __lauaInvoke(__lauaResource)",
                indent .. "            else",
                indent .. '                error("using resource has no Dispose, Disconnect, or Destroy method")',
                indent .. "            end",
                indent .. "        else",
                indent .. '            error("using cannot clean up this resource type")',
                indent .. "        end",
                indent .. "    end",
                indent .. "end",
            }
            table.insert(output, table.concat(code, "\n"))
        else
            table.insert(output, raw)
        end
        index += 1
    end
    return table.concat(output, "\n")
end

local function transpileAsyncFunctions(source: string): (string, number)
    local starts = {}
    for _, row in splitLines(source) do
        local masked = trim(maskNonCode(row.Text))
        if masked:match("^async%s+function%s+") or masked:match("^local%s+async%s+function%s+") then
            local at = row.Start + (row.Text:find("async", 1, true) or 1) - 1
            table.insert(starts, at)
        end
    end

    for index = #starts, 1, -1 do
        local at = starts[index]
        local closing = findBlock(source, at)
        local headerEnd = source:find("\n", at, true)
        if not headerEnd then error("async function needs a body") end
        local lineStart = (source:sub(1, at - 1):match(".*()\n") or 0) + 1
        local header = source:sub(lineStart, headerEnd - 1)
        local modified, replaced = header:gsub("%f[%w]async%s+function%s+", "function ", 1)
        if replaced ~= 1 then error("Malformed async function declaration") end
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local newBody = table.concat({
            "    return __lauaAsync.run(function()",
            normalized(body, "        "),
            "    end)",
        }, "\n")
        source = source:sub(1, lineStart - 1) .. modified .. "\n" .. newBody .. "\n" .. source:sub(closing.Start)
    end
    return source, #starts
end

local function findCloseParen(masked: string, at: number): number?
    local depth = 0
    for i = at, #masked do
        local char = masked:sub(i, i)
        if char == "(" then depth += 1 end
        if char == ")" then
            depth -= 1
            if depth == 0 then return i end
        end
    end
    return nil
end

local function transpileAwaits(source: string): (string, number)
    local occurrences = {}
    local masked = maskNonCode(source)
    local from = 1
    while true do
        local pos = masked:find("await", from, true)
        if not pos then break end
        local before = masked:sub(pos - 1, pos - 1)
        local after = masked:sub(pos + 5, pos + 5)
        if not before:match("[%w_%.:]") and not after:match("[%w_]") then
            local rest = masked:sub(pos + 5)
            local candidate = rest:match("^[ \t]*([%a_][%w_]*)")
            if rest:match("^[ \t]*%(") or (candidate and candidate ~= "local" and candidate ~= "const" and candidate ~= "if" and candidate ~= "then" and candidate ~= "end" and candidate ~= "else" and candidate ~= "return") then
                table.insert(occurrences, pos)
            end
        end
        from = pos + 5
    end
    for index = #occurrences, 1, -1 do
        local start = occurrences[index]
        masked = maskNonCode(source)
        local cursor = start + 5
        while masked:sub(cursor, cursor):match("%s") do cursor += 1 end
        local operandStart = cursor
        local last = cursor - 1
        if masked:sub(cursor, cursor) == "(" then
            last = findCloseParen(masked, cursor) or error("Unclosed await expression")
        else
            local identifier = masked:sub(cursor):match("^([%a_][%w_]*)")
            if not identifier then error("await needs an expression") end
            cursor += #identifier
            last = cursor - 1
            while cursor <= #masked do
                local gap = masked:sub(cursor):match("^[ \t]*") or ""
                local afterGap = cursor + #gap
                local separator = masked:sub(afterGap, afterGap)
                if separator == "." or separator == ":" then
                    local name = masked:sub(afterGap + 1):match("^[ \t]*([%a_][%w_]*)")
                    if not name then break end
                    local nameStart = masked:find(name, afterGap + 1, true) or (afterGap + 1)
                    cursor = nameStart + #name
                    last = cursor - 1
                elseif separator == "(" then
                    local closing = findCloseParen(masked, afterGap)
                    if not closing then error("Unclosed call after await") end
                    cursor = closing + 1
                    last = closing
                else
                    break
                end
            end
        end
        local operand = source:sub(operandStart, last)
        source = source:sub(1, start - 1) .. "__lauaAsync.await(" .. operand .. ")" .. source:sub(last + 1)
    end
    return source, #occurrences
end

-- Only embed LauaCore functions that the generated source actually calls.
-- Keep the original helper implementations intact to preserve their behavior.
local CORE_RUNTIME_DECLARATIONS: {{Start: number, Name: string}}? = nil
local CORE_RUNTIME_AVAILABLE: {[string]: boolean}? = nil

local function compactCoreRuntime(source: string): string
    local masked = maskNonCode(source)
    if masked:find("__lauaCore%s*%[") then return LAUA_CORE_RUNTIME_SOURCE end

    local requested = {}
    for name in masked:gmatch("__lauaCore%.([%a_][%w_%.]*)") do
        requested[name] = true
    end

    if not CORE_RUNTIME_DECLARATIONS then
        local declarations = {}
        local available = {}
        for start, name in LAUA_CORE_RUNTIME_SOURCE:gmatch("()function LauaCore%.([%a_][%w_%.]*)[<(]") do
            table.insert(declarations, {Start = start, Name = name})
            available[name] = true
        end
        CORE_RUNTIME_DECLARATIONS = declarations
        CORE_RUNTIME_AVAILABLE = available
    end
    local declarations = CORE_RUNTIME_DECLARATIONS :: {{Start: number, Name: string}}
    local available = CORE_RUNTIME_AVAILABLE :: {[string]: boolean}
    for name in requested do
        if not available[name] then return LAUA_CORE_RUNTIME_SOURCE end
    end

    local pieces = {"local LauaCore = {}"}
    local usesTable = false
    for name in requested do
        if name:sub(1, 6) == "table." then usesTable = true end
    end
    if usesTable then table.insert(pieces, "LauaCore.table = {}") end

    for index, declaration in declarations do
        if not requested[declaration.Name] then continue end
        local nextDeclaration = declarations[index + 1]
        local last = nextDeclaration and nextDeclaration.Start - 1 or #LAUA_CORE_RUNTIME_SOURCE
        local body = LAUA_CORE_RUNTIME_SOURCE:sub(declaration.Start, last)
        body = body:gsub("\nLauaCore%.table%s*=%s*[{][}]", "")
        body = body:gsub("\nreturn LauaCore%s*$", "")
        table.insert(pieces, trim(body))
    end
    table.insert(pieces, "return LauaCore")
    return table.concat(pieces, "\n\n")
end

-- Initialize runtime tables directly and isolate private bindings with do blocks.
-- This avoids the one-shot function allocation/call without exposing internals.
local function runtimeDoBlock(name: string, alias: string, body: string): string
    local oldDeclaration = alias == "Async" and "local Async: any = {}" or "local LauaCore = {}"
    local newDeclaration = "local " .. alias .. ": {[string]: any} = " .. name
    local declarationAt = body:find(oldDeclaration, 1, true)
    assert(declarationAt == 1 or (declarationAt ~= nil and body:sub(1, declarationAt - 1):find("^type ")), "Missing runtime library declaration")
    body = body:gsub(oldDeclaration:gsub("(%W)", "%%%1"), newDeclaration, 1)
    body = body:gsub("%s*return " .. alias .. "%s*$", "")
    return "local " .. name .. ": {[string]: any} = {}\ndo\n" .. body .. "\nend"
end

-- Embedded runtimes are inserted once, after header directives. Generated
-- scripts do not depend on separate Laua runtime ModuleScripts.
local function insertEmbeddedRuntimes(source: string): string
    local masked = maskNonCode(source)
    local fragments = {}
    if masked:find("__lauaAsync.", 1, true) and not masked:find("local%s+__lauaAsync%f[%W]") then
        table.insert(fragments, runtimeDoBlock("__lauaAsync", "Async", LAUA_ASYNC_RUNTIME_SOURCE))
    end
    if masked:find("__lauaCore.", 1, true) and not masked:find("local%s+__lauaCore%f[%W]") then
        table.insert(fragments, runtimeDoBlock("__lauaCore", "LauaCore", compactCoreRuntime(source)))
    end
    if #fragments == 0 then return source end

    local lines = splitLines(source)
    local index = 1
    while index <= #lines do
        local line = trim(lines[index].Text)
        if line:match("^%-%-!") or line == "" then
            index += 1
        else
            break
        end
    end
    local at = index <= #lines and lines[index].Start or (#source + 1)
    return source:sub(1, at - 1) .. table.concat(fragments, "\n\n") .. "\n\n" .. source:sub(at)
end

local function validateKnownVisibility(source: string)
    if not source:find("private",1,true) and not source:find("protected",1,true) then return end
    local masked = maskNonCode(source)
    local blockLines = splitLines(masked)
    local classes = {}
    for start, name, base in masked:gmatch("()class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_]*)") do
        classes[name] = {Base = base, Start = start, Finish = #source, Members = {}}
    end
    for start, name in masked:gmatch("()class%s+([%a_][%w_]*)") do
        if not classes[name] then classes[name] = {Start = start, Finish = #source, Members = {}} end
    end
    for name, info in classes do
        local ok, block = pcall(findBlock, source, info.Start, blockLines)
        if not ok or not block then continue end
        info.Finish = block.Finish
        local headerEnd = source:find("\n", info.Start, true)
        if not headerEnd then continue end
        local body = maskNonCode(source:sub(headerEnd + 1, block.Start - 1))
        for line in body:gmatch("[^\n]+") do
            local kind, field = line:match("^%s*(private)%s+([%a_][%w_]*)")
            if not kind then kind, field = line:match("^%s*(protected)%s+([%a_][%w_]*)") end
            if not kind then
                kind, field = line:match("^%s*(private)%s+function%s+([%a_][%w_]*)")
                if not kind then kind, field = line:match("^%s*(protected)%s+function%s+([%a_][%w_]*)") end
            end
            if kind and field then
                if field == "function" then
                    local actual = line:match("^%s*" .. kind .. "%s+function%s+([%a_][%w_]*)")
                    if actual then field = actual end
                end
                info.Members[field] = kind
            end
        end
    end
    local variables = {}
    for variable, class in masked:gmatch("local%s+([%a_][%w_]*)%s*=%s*new%s+([%a_][%w_]*)") do
        if classes[class] then variables[variable] = class end
    end
    for variable, class in masked:gmatch("local%s+([%a_][%w_]*)%s*:%s*([%a_][%w_]*)") do
        if classes[class] and not variables[variable] then variables[variable] = class end
    end
    for start, owner, member in masked:gmatch("()([%a_][%w_]*)%s*[%.:]%s*([%a_][%w_]*)") do
        local class = variables[owner]
        if not class then continue end
        local seen = {}
        local defining, access = nil, nil
        while class and classes[class] and not seen[class] do
            seen[class] = true
            access = classes[class].Members[member]
            if access then defining = class; break end
            class = classes[class].Base
        end
        if not access then continue end
        local ownerClass = nil
        for candidate, info in classes do
            if start > info.Start and start < info.Finish then ownerClass = candidate; break end
        end
        local allowed = ownerClass == defining
        if ownerClass and not allowed and access == "protected" then
            local parent, visited = ownerClass, {}
            while parent and classes[parent] and not visited[parent] do
                if parent == defining then allowed = true; break end
                visited[parent] = true
                parent = classes[parent].Base
            end
        end
        if not allowed then
            local prefix = source:sub(1,start - 1)
            local _, lineCount = prefix:gsub("\n", "")
            error(`Cannot access {access} member '{defining}.{member}' (line {lineCount + 1}).`)
        end
    end
end

local function compactGeneratedOutput(source: string): string
    if source:find("[[]=*[[]") or source:find("`",1,true) then return source end
    local result = {}
    for row in source:gmatch("([^\n]*)\n?") do
        local commentOnly = row:match("^%s*%-%-") and not row:match("^%s*%-%-[!#]")
        if row ~= "" and row:match("%S") and not commentOnly then table.insert(result,trim(row)) end
    end
    return table.concat(result,"\n")
end

-- Compile-time inlining is explicit. Preserve ordinary dynamic function calls.
-- Only a single pure return with zero/one argument can be substituted safely.
local function transpileInlineFunctions(source: string): string
    if source:find("[[]=*[[]") or source:find("`", 1, true) then return source end
    local cursor = 1
    while true do
        local masked = maskNonCode(source)
        local start = masked:find("inline", cursor, true)
        if not start then return source end
        local lineStart = (source:sub(1, start - 1):match(".*()\n") or 0) + 1
        local beforeInline = trim(source:sub(lineStart, start - 1))
        if (beforeInline ~= "" and beforeInline ~= "local") or (beforeInline == "" and masked:sub(start - 1, start - 1):match("[%w_%.:]")) or masked:sub(start + 6, start + 6):match("[%w_]") then
            cursor = start + 6
            continue
        end
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then error("inline function needs a body") end
        local header = source:sub(start, headerEnd - 1)
        local signature = header:gsub("%)%s*:%s*[%a_][%w_]*%s*$", ")")
        local name, parameters = signature:match("^inline%s+function%s+([%a_][%w_]*)%s*%((.-)%)%s*$")
        local parameterName = parameters:match("^([%a_][%w_]*)%s*:%s*[%a_][%w_]*%??$") or parameters
        if not name or (parameters ~= "" and not parameterName:match("^[%a_][%w_]*$")) then
            error("inline supports top-level functions with zero or one parameter (optionally typed)")
        end
        local adjusted = source:sub(1, start - 1) .. header:gsub("^inline%s+", "", 1) .. source:sub(headerEnd)
        local adjustedHeaderEnd = adjusted:find("\n", start, true)
        local closing = findBlock(adjusted, start)
        if parameters:find(":", 1, true) or header:match("%)%s*:%s*[%a_][%w_]*%s*$") then
            source = adjusted
            cursor = closing.Finish + 1
            continue
        end
        local body = trim(adjusted:sub(adjustedHeaderEnd + 1, closing.Start - 1))
        local operator, number = nil, nil
        if parameters ~= "" then operator, number = body:match("^return%s+" .. parameterName .. "%s*([+*/%-])%s*(%-?%d+%.?%d*)%s*$") end
        local identity = parameters ~= "" and body == "return " .. parameterName
        local constant = parameters == "" and (body:match("^return%s+%-?%d+%.?%d*$") or body:match("^return%s+true$") or body:match("^return%s+false$") or body:match("^return%s+nil$") or body:match('^return%s+"[^"\\\n]*"$') or body:match("^return%s+'[^'\\\n]*'$") ) ~= nil
        if not operator and not identity and not constant then
            error("inline function '" .. name .. "' must return a literal, its parameter, or parameter arithmetic with a number")
        end
        local suffix = adjusted:sub(closing.Finish + 1)
        local suffixMasked = maskNonCode(suffix)
        -- Fall back to regular calls when a later binding might replace the function.
        if suffixMasked:find("%f[%w]" .. name .. "%s*=") or suffixMasked:find("%f[%w]local%s+" .. name .. "%f[%W]") or suffixMasked:find("%f[%w]function%s+" .. name .. "%s*%(") then
            source = adjusted
            cursor = closing.Finish + 1
            continue
        end
        local offset = 1
        while true do
            local code = maskNonCode(suffix)
            local found = code:find(name, offset, true)
            if not found then break end
            local before = code:sub(found - 1, found - 1)
            local after = code:sub(found + #name, found + #name)
            if before:match("[%w_%.:]") or after:match("[%w_]") then offset = found + #name; continue end
            local opening = code:find("%S", found + #name)
            if not opening or code:sub(opening, opening) ~= "(" then offset = found + #name; continue end
            local depth, closingCall = 0, nil
            for pos = opening, #code do
                local char = code:sub(pos, pos)
                if char == "(" then depth += 1 end
                if char == ")" then
                    depth -= 1
                    if depth == 0 then closingCall = pos; break end
                end
            end
            if not closingCall then error("Unclosed inline call to " .. name) end
            local argument = trim(suffix:sub(opening + 1, closingCall - 1))
            local simple = argument:match("^[%a_][%w_%.]*$") or argument:match("^%-?%d+%.?%d*$") or argument:match("^[%a_][%w_]*%(%s*%)$")
            if (parameters ~= "" and not simple) or (parameters == "" and argument ~= "") then
                offset = closingCall + 1
                continue
            end
            local replacement
            if constant then replacement = "(" .. trim(body:sub(7)) .. ")"
            elseif identity then replacement = "(" .. argument .. ")"
            else replacement = "((" .. argument .. ") " .. operator .. " " .. number .. ")" end
            suffix = suffix:sub(1, found - 1) .. replacement .. suffix:sub(closingCall + 1)
            offset = found + #replacement
        end
        source = adjusted:sub(1, closing.Finish) .. suffix
        cursor = closing.Finish + 1
    end
end

-- A postfix ? on a single-variable declaration returns on nil, but not false.
-- Only the guarded declaration form is recognized; optional type annotations
-- and non-declaration expressions keep their existing meaning.
local function transpileEarlyReturn(source: string): string
    local lines = {}
    for _, row in splitLines(source) do
        local raw = row.Text
        if not raw:find("?", 1, true) then
            table.insert(lines, raw)
            continue
        end
        local masked = trim(maskNonCode(raw))
        if masked:sub(-1) ~= "?" or masked:sub(-2) == "??" then
            table.insert(lines, raw)
            continue
        end
        local indent, name, annotation, expression
        for _, keyword in {"local", "const"} do
            -- Capture all fields from the declaration; do not confuse `?` in
            -- optional type annotations with the postfix nil guard.
            indent, name, annotation, expression = raw:match("^([ \t]*)" .. keyword .. "%s+([%a_][%w_]*)(.-)%s*=%s*(.-)%?%s*$")
            if name then
                if annotation == "" or annotation:match("^%s*:%s*[^=]+$") then break end
                name = nil
            end
        end
        if not name or trim(expression) == "" or trim(expression):sub(-1) == "?" then
            table.insert(lines, raw)
            continue
        end
        table.insert(lines, indent .. "local " .. name .. annotation .. " = " .. trim(expression))
        table.insert(lines, indent .. "if " .. name .. " == nil then return end")
    end
    return table.concat(lines, "\n")
end

-- Semantic checks for statically known Laua declarations. Dynamic Roblox values,
-- external imports and untyped tables remain governed by Luau at runtime.
-- v3.37 syntax validation. This guards source-level token relationships
-- before the transformation passes; it does not replace Roblox's Luau parser.
local function validateExpressionSyntax(source: string)
    local masked = maskNonCode(source)
    local tokens = {}
    local index = 1
    local lineNumber = 1
    local length = #source
    local multiOperators = {"...", "??=", "//=" , "..=", "?.", "??", "==", "~=", "<=", ">=", "=>", "->", "::", "+=", "-=", "*=", "/=", "%=", "^=", "..", "//"}
    local function add(kind: string, value: string, at: number)
        table.insert(tokens, {kind = kind, value = value, line = lineNumber, at = at})
    end
    while index <= length do
        local char = source:sub(index, index)
        local visible = masked:sub(index, index)
        if (char == '"' or char == "'" or char == "`") and visible == " " then
            local start = index
            local quote = char
            index += 1
            while index <= length do
                local current = source:sub(index, index)
                if current == "\\" then
                    index += 2
                elseif current == quote then
                    index += 1
                    break
                else
                    if current == "\n" then lineNumber += 1 end
                    index += 1
                end
            end
            add("literal", "<string>", start)
        elseif char == "[" and visible == " " then
            local equalSigns = source:sub(index):match("^%[(=*)%[")
            if equalSigns then
                local start = index
                local closing = "]" .. equalSigns .. "]"
                local openingLength = #equalSigns + 2
                local closeAt = source:find(closing, index + openingLength, true)
                local finish = closeAt and closeAt + #closing or length + 1
                local chunk = source:sub(index, finish - 1)
                local _, breaks = chunk:gsub("\n", "")
                lineNumber += breaks
                index = finish
                add("literal", "<string>", start)
            else
                index += 1
            end
        elseif visible == " " or visible == "\t" or visible == "\r" or visible == "\n" then
            if char == "\n" then lineNumber += 1 end
            index += 1
        elseif char:match("[%a_]") then
            local start = index
            repeat
                index += 1
            until index > length or not masked:sub(index, index):match("[%w_]")
            add("word", masked:sub(start, index - 1), start)
        elseif char:match("%d") then
            local start = index
            repeat
                index += 1
            until index > length or not masked:sub(index, index):match("[%w_]")
            if source:sub(index, index) == "." and source:sub(index + 1, index + 1) ~= "." then
                index += 1
                while index <= length and masked:sub(index, index):match("%d") do index += 1 end
            end
            add("number", masked:sub(start, index - 1), start)
        else
            local start = index
            local operator = nil
            for _, candidate in multiOperators do
                if masked:sub(index, index + #candidate - 1) == candidate then
                    operator = candidate
                    break
                end
            end
            if operator then
                index += #operator
                add("symbol", operator, start)
            else
                index += 1
                add("symbol", char, start)
            end
        end
    end
    local openers = {["("] = ")", ["["] = "]", ["{"] = "}"}
    local stack = {}
    local binary = {["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["//"] = true, ["%"] = true, ["^"] = true, [".."] = true, ["??"] = true, ["and"] = true, ["or"] = true, ["=="] = true, ["~="] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true}
    local badAfter = {["*"] = true, ["/"] = true, ["//"] = true, ["%"] = true, ["^"] = true, [".."] = true, ["??"] = true, ["and"] = true, ["or"] = true, ["=="] = true, ["~="] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true, [","] = true, [";"] = true, [")"] = true, ["]"] = true, ["}"] = true, ["then"] = true, ["else"] = true, ["elseif"] = true, ["end"] = true}
    local assignments = {["="] = true, ["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true, ["//="] = true, ["%="] = true, ["^="] = true, ["..="] = true, ["??="] = true}
    local function fail(message: string, token: any)
        error("Laua syntax error (line " .. tostring(token.line) .. "): " .. message, 0)
    end
    for position, token in tokens do
        local prev = tokens[position - 1]
        local nextToken = tokens[position + 1]
        local word = token.value
        if openers[word] then
            table.insert(stack, {closing = openers[word], opener = token})
        elseif word == ")" or word == "]" or word == "}" then
            local top = stack[#stack]
            if not top or top.closing ~= word then fail("Unexpected '" .. word .. "'.", token) end
            table.remove(stack)
        end
        if prev then
            if word == "," and prev.value == "," then fail("Missing expression between commas.", token) end
            if assignments[prev.value] and (word == "," or word == ";" or word == ")" or word == "]" or word == "}" or word == "end" or word == "else" or word == "elseif") then
                fail("Missing expression after '" .. prev.value .. "'.", token)
            end
            if binary[prev.value] and badAfter[word] then fail("Missing operand after '" .. prev.value .. "'.", token) end
            if assignments[word] and (prev.kind == "number" or prev.kind == "literal" or prev.value == "true" or prev.value == "false" or prev.value == "nil") then
                fail("Assignment requires a variable or property.", token)
            end
            if (prev.value == ")" or prev.value == "]" or prev.value == "}") and (token.kind == "number" or token.kind == "literal") and prev.line == token.line then
                fail("Missing separator after '" .. prev.value .. "'.", token)
            end
            if prev.kind == "number" and (token.kind == "number" or token.kind == "literal") and prev.line == token.line then
                fail("Missing operator between values.", token)
            end
            if prev.value == "=" and word == "*" then fail("Unexpected '*' after '='.", token) end
        end
        if word == "do" and prev and prev.value == "," then
            for n = math.max(1, position - 12), position - 1 do
                if tokens[n].value == "for" then fail("Missing range value before do.", token) end
            end
        end
        if prev and prev.value == "then" and word == "else" and prev.line == token.line then
            fail("Conditional expression may be missing a value.", token)
        end
    end
    local top = stack[#stack]
    if top then fail("Unclosed '" .. top.opener.value .. "'.", top.opener) end
    local last = tokens[#tokens]
    if last and (assignments[last.value] or binary[last.value]) then fail("Missing expression after '" .. last.value .. "'.", last) end
end

-- Verify contracts between classes declared in this compilation unit.
-- Imported/dynamic parents still retain runtime guards in transpileClasses.
local function validateClassContracts(source: string)
    if not source:find("class", 1, true) then return end
    local masked = maskNonCode(source)
    local lines = splitLines(masked)
    local classes = {}
    local function fail(message: string, at: number)
        local line, column = 1, 1
        for i = 1, at - 1 do
            if source:sub(i, i) == "\n" then line += 1; column = 1 else column += 1 end
        end
        error(`Laua class error (line {line}, column {column}): {message}`, 2)
    end
    for _, row in lines do
        local header = trim(row.Text)
        local classModifier, className, base = header:match("^(final)%s+class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_%.]*)%s*$")
        if not className then classModifier, className, base = header:match("^(abstract)%s+class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_%.]*)%s*$") end
        if not className then className, base = header:match("^class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_%.]*)%s*$") end
        if not className then classModifier, className = header:match("^(final)%s+class%s+([%a_][%w_]*)%s*$") end
        if not className then classModifier, className = header:match("^(abstract)%s+class%s+([%a_][%w_]*)%s*$") end
        if not className then className = header:match("^class%s+([%a_][%w_]*)%s*$") end
        if not className then continue end
        local ending = findBlock(source, row.Start, lines)
        if classes[className] then fail(`Duplicate class '{className}'.`, row.Start) end
        local body = source:sub(row.Finish + 1, ending.Start - 1)
        local bodyLines = splitLines(maskNonCode(body))
        local members = {}
        local properties = {}
        local nextAllowed = 1
        for _, memberRow in bodyLines do
            if memberRow.Start < nextAllowed then continue end
            local text = trim(memberRow.Text)
            local modifiers = {}
            for _ = 1, 7 do
                local prefix = text:match("^([%a_]+)%s+")
                if prefix ~= "final" and prefix ~= "override" and prefix ~= "static" and prefix ~= "public" and prefix ~= "private" and prefix ~= "protected" and prefix ~= "abstract" then break end
                modifiers[prefix] = true
                text = trim(text:sub(#prefix + 1))
            end
            local memberName = text:match("^function%s+([%a_][%w_]*)%s*%(") or text:match("^async%s+function%s+([%a_][%w_]*)%s*%(")
            if memberName then
                members[memberName] = {Final = modifiers.final == true, Override = modifiers.override == true, Static = modifiers.static == true, At = row.Finish + memberRow.Start}
            end
            local getter = text:match("^get%s+([%a_][%w_]*)%s*%(")
            local setter = text:match("^set%s+([%a_][%w_]*)%s*%(")
            if getter or setter then
                local propertyName = getter or setter
                properties[propertyName] = {At = row.Finish + memberRow.Start, Kind = getter and "getter" or "setter"}
            end
            if memberName or text:match("^constructor%s*%(") or text:match("^watch%s+[%a_][%w_]*%s*%(") or text:match("^get%s+[%a_][%w_]*%s*%(") or text:match("^set%s+[%a_][%w_]*%s*%(") or text:match("^operator%s+") then
                local at = memberRow.Start + (memberRow.Text:find("%S") or 1) - 1
                local ok, closing = pcall(findBlock, body, at, bodyLines)
                if ok then nextAllowed = closing.Finish + 1 end
            end
        end
        classes[className] = {Base = base, Final = classModifier == "final", Methods = members, Properties = properties, At = row.Start}
    end
    for className, info in classes do
        local baseInfo = info.Base and classes[info.Base]
        if baseInfo and baseInfo.Final then fail(`Cannot extend final class '{info.Base}'.`, info.At) end
        local seen = {[className] = true}
        local parent = info.Base
        while parent and classes[parent] do
            if seen[parent] then fail(`Circular class inheritance involving '{className}'.`, info.At) end
            seen[parent] = true
            parent = classes[parent].Base
        end
        for memberName, member in info.Methods do
            local ancestor = info.Base
            local visited = {}
            local inherited = nil
            while ancestor and classes[ancestor] and not visited[ancestor] do
                visited[ancestor] = true
                local record = classes[ancestor]
                if record.Methods[memberName] then inherited = record.Methods[memberName]; break end
                ancestor = record.Base
            end
            if not member.Static then
                local ancestorName = info.Base
                local propertySeen = {}
                while ancestorName and classes[ancestorName] and not propertySeen[ancestorName] do
                    propertySeen[ancestorName] = true
                    if classes[ancestorName].Properties[memberName] then
                        fail(`Method '{className}.{memberName}' conflicts with inherited getter/setter '{ancestorName}.{memberName}'. Rename one member.`, member.At)
                    end
                    ancestorName = classes[ancestorName].Base
                end
            end
            if inherited and inherited.Final then fail(`Cannot override final method '{memberName}' in class '{className}'.`, member.At) end
            if member.Override and not inherited and (not info.Base or classes[info.Base]) then
                fail(`Method '{className}.{memberName}' is marked override but no ancestor defines it.`, member.At)
            end
            if member.Override and inherited and member.Static ~= inherited.Static then
                fail(`Override '{className}.{memberName}' changes static/instance method kind.`, member.At)
            end
        end
        for propertyName, property in info.Properties do
            local own = info.Methods[propertyName]
            if own and not own.Static then
                fail(`Getter/setter '{className}.{propertyName}' conflicts with a same-name instance method.`, property.At)
            end
            local ancestorName = info.Base
            local visited = {}
            while ancestorName and classes[ancestorName] and not visited[ancestorName] do
                visited[ancestorName] = true
                local inherited = classes[ancestorName].Methods[propertyName]
                if inherited and not inherited.Static then
                    fail(`Getter/setter '{className}.{propertyName}' conflicts with inherited method '{ancestorName}.{propertyName}'. Rename one member.`, property.At)
                end
                ancestorName = classes[ancestorName].Base
            end
        end
    end
end

local function validateLauaSemantics(source: string): {any}
    if source:find("local __laua", 1, true) then return {} end
    local masked = maskNonCode(source)
    local getterRewrites = {}
    local classes: {[string]: any} = {}
    local enums: {[string]: {[string]: boolean}} = {}
    local namespaces: {[string]: {[string]: boolean}} = {}
    local knownVariables: {[string]: string} = {}
    local functions: {[string]: string} = {}
    local importedSymbols = {}
    for _, importLine in splitLines(masked) do
        local text = trim(importLine.Text)
        local named = text:match('^import%s+%{(.-)%}%s+from%s+')
        local importedDefault, importedAlias = text:match('^import%s+([%a_][%w_]*)%s+as%s+([%a_][%w_]*)%s+from%s+')
        if not importedDefault then importedDefault = text:match('^import%s+([%a_][%w_]*)%s+from%s+') end
        if importedDefault then importedSymbols[importedAlias or importedDefault] = true end
        if named then
            for piece in named:gmatch('[^,]+') do
                local original, replacement = trim(piece):match('^([%a_][%w_]*)%s+as%s+([%a_][%w_]*)$')
                if original then importedSymbols[replacement]=true
                else
                    local name=trim(piece):match('^([%a_][%w_]*)$')
                    if name then importedSymbols[name]=true end
                end
            end
        end
    end
    local globals = {}
    for word in ("assert error getfenv getmetatable ipairs loadstring newproxy next pairs pcall print rawequal rawget rawlen rawset select setfenv setmetatable tonumber tostring type typeof unpack xpcall require warn tick time elapsedTime gcinfo settings UserSettings plugin delay spawn wait collectgarbage debug vector _G _VERSION shared game workspace script Enum Instance CFrame Vector2 Vector3 UDim UDim2 Color3 BrickColor NumberRange NumberSequence ColorSequence Rect Ray Region3 PhysicalProperties Random DateTime TweenInfo OverlapParams RaycastParams Axes Faces Font math table string task coroutine utf8 os bit32 buffer nil true false"):gmatch("[%a_][%w_]*") do
        globals[word] = true
    end
    local function fail(message: string, at: number)
        local line = 1
        for _ in source:sub(1, at - 1):gmatch("\n") do line += 1 end
        error(`Laua semantic error (line {line}): {message}`, 2)
    end
    local function paramParts(raw: string): {string}
        local result = {}
        local start, depth = 1, 0
        local maskedArguments = maskNonCode(raw)
        for i = 1, #raw + 1 do
            local ch = maskedArguments:sub(i, i)
            if i > #raw or (ch == "," and depth == 0) then
                local part = trim(raw:sub(start, i - 1))
                if part ~= "" then table.insert(result, part) end
                start = i + 1
            elseif ch == "(" or ch == "{" or ch == "[" or ch == "<" then
                depth += 1
            elseif ch == ")" or ch == "}" or ch == "]" or ch == ">" then
                depth = math.max(0, depth - 1)
            end
        end
        return result
    end
    local function checkCall(label: string, params: string?, arguments: string, at: number)
        if not params then return end
        local declarations = paramParts(params)
        local passed = paramParts(arguments)
        local required, rest = 0, false
        for _, part in declarations do
            if part:find("...", 1, true) then rest = true end
            if not part:find("=", 1, true) and not part:find("...", 1, true) then required += 1 end
        end
        if #passed < required or (not rest and #passed > #declarations) then
            fail(`'{label}' expects {required} argument(s), received {#passed}.`, at)
        end
        for i, value in passed do
            local annotation = declarations[i] and declarations[i]:match("^%s*[%a_][%w_]*%s*:%s*([%a_][%w_]*%??)")
            if annotation then
                local actual = value:match("^%d+%.?%d*$") and "number" or (value == "true" or value == "false") and "boolean" or value:match("^[\"'`]") and "string" or nil
                if actual and (annotation == "number" or annotation == "string" or annotation == "boolean") and annotation ~= actual then
                    fail(`Argument {i} of '{label}' expects {annotation}, received {actual}.`, at)
                end
            end
        end
    end
    local lines = splitLines(masked)
    for _, line in lines do
        local code = trim(line.Text)
        local name, base = code:match("^class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_%.]*)%s*$")
        if not name then name, base = code:match("^final%s+class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_%.]*)%s*$") end
        if not name then name, base = code:match("^abstract%s+class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_%.]*)%s*$") end
        if not name then name = code:match("^class%s+([%a_][%w_]*)%s*$") end
        if not name then name = code:match("^final%s+class%s+([%a_][%w_]*)%s*$") end
        if not name then name = code:match("^abstract%s+class%s+([%a_][%w_]*)%s*$") end
        if name then
            local ending = findBlock(source, line.Start, lines)
            local info = {Base = base, Start = line.Start, Finish = ending.Finish, Instance = {}, Static = {}, Constructor = nil}
            classes[name] = info
            for _, row in lines do
                if row.Start <= line.Start or row.Start >= ending.Start then continue end
                local body = trim(row.Text)
                local isStatic = body:match("^static%s+") ~= nil
                local clean = body
                for _ = 1, 7 do
                    local prefix = clean:match("^([%a_]+)%s+")
                    if prefix ~= "public" and prefix ~= "private" and prefix ~= "protected" and prefix ~= "static" and prefix ~= "override" and prefix ~= "abstract" and prefix ~= "final" then break end
                    if prefix == "static" then isStatic = true end
                    clean = trim(clean:sub(#prefix + 1))
                end
                for dynamicField in body:gmatch("self%.([%a_][%w_]*)%s*=") do
                    if not info.Instance[dynamicField] then info.Instance[dynamicField] = {Kind = "field"} end
                end
                local ctor = clean:match("^constructor%s*%(([^)]*)%)")
                if ctor then info.Constructor = ctor end
                local getter = clean:match("^get%s+([%a_][%w_]*)%s*%(")
                local setter = clean:match("^set%s+([%a_][%w_]*)%s*%(")
                if getter then info.Instance[getter] = {Kind = "getter"} end
                if setter and not info.Instance[setter] then info.Instance[setter] = {Kind = "setter"} end
                local methodName, params = clean:match("^function%s+([%a_][%w_]*)%s*%(([^)]*)%)")
                if not methodName then methodName, params = clean:match("^async%s+function%s+([%a_][%w_]*)%s*%(([^)]*)%)") end
                if methodName then
                    local target = isStatic and info.Static or info.Instance
                    target[methodName] = {Kind = "method", Params = params}
                else
                    local field = clean:match("^([%a_][%w_]*)%s*:%s*.+%s*=") or clean:match("^([%a_][%w_]*)%s*:%s*%S.-%s*$") or clean:match("^([%a_][%w_]*)%s*=")
                    if field then
                        local target = isStatic and info.Static or info.Instance
                        target[field] = {Kind = "field"}
                    end
                end
            end
        end
        local enumName = code:match("^enum%s+([%a_][%w_]*)%s*$")
        if enumName then
            local ending = findBlock(source, line.Start, lines)
            local members = {}
            for _, row in lines do
                if row.Start > line.Start and row.Start < ending.Start then
                    local member = trim(row.Text):match("^([%a_][%w_]*)%s*[=,]?")
                    if member then members[member] = true end
                end
            end
            enums[enumName] = members
        end
        local namespaceName = code:match("^namespace%s+([%a_][%w_]*)%s*$")
        if namespaceName then
            local ending = findBlock(source, line.Start, lines)
            local members = {}
            for _, row in lines do
                if row.Start > line.Start and row.Start < ending.Start then
                    local member = trim(row.Text):match("^function%s+([%a_][%w_]*)") or trim(row.Text):match("^([%a_][%w_]*)%s*=")
                    if member then members[member] = true end
                end
            end
            namespaces[namespaceName] = members
        end
        local func, params = code:match("^local%s+function%s+([%a_][%w_]*)%s*%(([^)]*)%)")
        if not func then func, params = code:match("^local%s+function%s+([%a_][%w_]*)%s*%b<>%s*%(([^)]*)%)") end
        if not func then func, params = code:match("^function%s+([%a_][%w_]*)%s*%(([^)]*)%)") end
        if not func then func, params = code:match("^function%s+([%a_][%w_]*)%s*%b<>%s*%(([^)]*)%)") end
        if func then functions[func] = params end
    end
    local function memberOf(name: string, member: string, isStatic: boolean): any
        local seen = {}
        while name and not seen[name] do
            seen[name] = true
            local info = classes[name]
            if not info then return nil end
            local result = (isStatic and info.Static or info.Instance)[member]
            if result then return result end
            name = info.Base
        end
        return nil
    end
    for _, line in lines do
        local code = line.Text
        local name, className, arguments = code:match("local%s+([%a_][%w_]*)%s*=%s*new%s+([%a_][%w_]*)%s*%(([^)]*)%)")
        if not name then name, className, arguments = code:match("local%s+([%a_][%w_]*)%s*:%s*[%a_][%w_]*%s*=%s*new%s+([%a_][%w_]*)%s*%(([^)]*)%)") end
        if name and className then
            if not classes[className] then
                if not importedSymbols[className] then fail(`Unknown class '{className}'.`, line.Start) end
            end
            if classes[className] then knownVariables[name] = className end
            local raw = source:sub(line.Start, line.Finish)
            local open = code:find("new%s+[%a_][%w_]*%s*%(")
            local rawArguments = arguments
            if open then
                local startAt = code:find("%(", open)
                local closeAt = code:find("%)", startAt or open)
                if startAt and closeAt then rawArguments = raw:sub(startAt + 1, closeAt - 1) end
            end
            if classes[className] then checkCall(className .. " constructor", classes[className].Constructor or "", rawArguments, line.Start) end
        end
        local typedName, typedClass = code:match("local%s+([%a_][%w_]*)%s*:%s*([%a_][%w_]*)")
        if typedName and classes[typedClass] then knownVariables[typedName] = typedClass end
        local var, reference = code:match("local%s+([%a_][%w_]*)%s*=%s*([%a_][%w_]*)%s*$")
        if var and reference and not globals[reference] and not classes[reference] and not enums[reference] and not namespaces[reference] and not functions[reference] and not knownVariables[reference] then
            local declaredBefore = masked:sub(1, line.Start - 1):find("local%s+" .. reference .. "%f[%W]") or masked:sub(1, line.Start - 1):find("function%s+" .. reference .. "%f[%W]")
            if not declaredBefore then fail(`Unknown variable '{reference}'.`, line.Start) end
        end
    end
    -- Lexically scoped instance inference, so a local variable inside a
    -- do/function/if block does not change an outer class binding.
    local typedBindings = {}
    local frames = {{} }
    local function addBinding(name: string, className: string?, at: number)
        local slot = {Name = name, Class = className, First = at, Last = math.huge}
        if not typedBindings[name] then typedBindings[name] = {} end
        table.insert(typedBindings[name], slot)
        table.insert(frames[#frames], slot)
    end
    local function closeFrame(at: number)
        if #frames <= 1 then return end
        local frame = table.remove(frames)
        for _, slot in frame do slot.Last = at end
    end
    for _, line in lines do
        local code = trim(line.Text)
        if code == "" then continue end
        if code:match("^end%f[%W]") or code:match("^until%f[%W]") then
            closeFrame(line.Start)
            continue
        end
        if code:match("^else%f[%W]") or code:match("^elseif%f[%W]") then
            closeFrame(line.Start)
            table.insert(frames, {})
        end
        if blockStart(code) then table.insert(frames, {}) end
        local params = code:match("^%s*function%s+[%w_%.:]+%s*%(([^)]*)%)") or code:match("^local%s+function%s+[%w_%.:]+%s*%(([^)]*)%)") or code:match("^constructor%s*%(([^)]*)%)")
        if params then
            for _, part in paramParts(params) do
                local pname = part:match("^([%a_][%w_]*)")
                if pname then addBinding(pname, nil, line.Start) end
            end
        end
        local declaration, declaredType, inferredType = code:match("^local%s+([%a_][%w_]*)%s*:%s*([%a_][%w_]*)%s*=%s*new%s+([%a_][%w_]*)")
        if not declaration then declaration, inferredType = code:match("^local%s+([%a_][%w_]*)%s*=%s*new%s+([%a_][%w_]*)") end
        if not declaration then declaration, declaredType = code:match("^local%s+([%a_][%w_]*)%s*:%s*([%a_][%w_]*)") end
        if not declaration then declaration = code:match("^local%s+([%a_][%w_]*)%f[%W]") end
        if not declaration then declaration = code:match("^const%s+([%a_][%w_]*)%f[%W]") end
        if declaration and declaration ~= "function" then
            local className = inferredType and classes[inferredType] and inferredType or declaredType and classes[declaredType] and declaredType or nil
            addBinding(declaration, className, line.Start)
        end
    end
    local function resolveTypedOwner(name: string, at: number): string?
        local bindings = typedBindings[name]
        if not bindings then return knownVariables[name] end
        local best = nil
        for _, record in bindings do
            if record.First <= at and at < record.Last and (not best or record.First > best.First) then best = record end
        end
        return best and best.Class or nil
    end
    local knownCalls = {}
    for word in ("if while for until repeat return function constructor get set new super async await select continue else elseif then do end not and or"):gmatch("[%a_][%w_]*") do knownCalls[word] = true end
    knownCalls.cancelScope = true
    for name in globals do knownCalls[name] = true end
    for name in functions do knownCalls[name] = true end
    for name in classes do knownCalls[name] = true end
    for name in namespaces do knownCalls[name] = true end
    for name in enums do knownCalls[name] = true end
    for name in knownVariables do knownCalls[name] = true end
    for _, line in lines do
        for name in line.Text:gmatch("%f[%w_]local%s+([%a_][%w_]*)") do knownCalls[name] = true end
        for name in line.Text:gmatch("%f[%w_]const%s+([%a_][%w_]*)") do knownCalls[name] = true end
        for name in line.Text:gmatch("%f[%w_]for%s+([%a_][%w_]*)") do knownCalls[name] = true end
        for name in line.Text:gmatch("%f[%w_]function%s+([%a_][%w_]*)") do knownCalls[name] = true end
        for name in line.Text:gmatch("%f[%w_]import%s+([%a_][%w_]*)") do knownCalls[name] = true end
        local _, importedAlias = line.Text:match("^%s*import%s+([%a_][%w_]*)%s+as%s+([%a_][%w_]*)%s+from%s+")
        if importedAlias then knownCalls[importedAlias] = true end
        for _, pattern in {"function%s+[%a_][%w_]*%s*%(([^)]*)%)", "function%s+[%a_][%w_]*%s*%b<>%s*%(([^)]*)%)"} do
            for params in line.Text:gmatch(pattern) do
                for _, part in paramParts(params) do
                    local name = part:match("^([%a_][%w_]*)")
                    if name then knownCalls[name] = true end
                end
            end
        end
        for params in line.Text:gmatch("constructor%s*%(([^)]*)%)") do
            for _, part in paramParts(params) do
                local name = part:match("^([%a_][%w_]*)")
                if name then knownCalls[name] = true end
            end
        end
    end
    for _, line in lines do
        local code = line.Text
        for startPos, name in code:gmatch("()([%a_][%w_]*)%s*%(") do
            local before = code:sub(1, startPos - 1)
            local prev = before:match("(%S)%s*$")
            if prev ~= "." and prev ~= ":" and not before:match("function%s*$") and not before:match("new%s*$") and not before:match("constructor%s*$") and not before:match("watch%s*$") and not before:match("get%s*$") and not before:match("set%s*$") then
                if not knownCalls[name] then fail(`Unknown function '{name}'.`, line.Start + startPos - 1) end
            end
        end
        local declaredType, declaredValue = code:match("local%s+[%a_][%w_]*%s*:%s*(number)%s*=%s*(.+)$")
        if not declaredType then declaredType, declaredValue = code:match("local%s+[%a_][%w_]*%s*:%s*(string)%s*=%s*(.+)$") end
        if not declaredType then declaredType, declaredValue = code:match("local%s+[%a_][%w_]*%s*:%s*(boolean)%s*=%s*(.+)$") end
        if declaredType then
            local raw = trim(source:sub(line.Start, line.Finish):match("=%s*(.-)%s*$") or "")
            local actual = raw:match("^%d+%.?%d*$") and "number" or (raw == "true" or raw == "false") and "boolean" or raw:match("^[\"'`]") and "string" or nil
            if actual and actual ~= declaredType then fail(`Expected {declaredType}, received {actual}.`, line.Start) end
        end
    end
    for _, line in lines do
        local code = line.Text
        for className in code:gmatch("%f[%w_]new%s+([%a_][%w_]*)%s*%(") do
            if not classes[className] and not knownCalls[className] and not importedSymbols[className] then fail(`Unknown class '{className}'.`, line.Start) end
        end
        for _, pattern in {
            "^%s*return%s+([%a_][%w_]*)%s*$",
            "^%s*if%s+([%a_][%w_]*)%s+then%s*$",
            "^%s*while%s+([%a_][%w_]*)%s+do%s*$",
            "local%s+[%a_][%w_]*%s*=%s*([%a_][%w_]*)%s*[%+%-%*/]",
            "print%s*%(%s*([%a_][%w_]*)%s*%)",
            "warn%s*%(%s*([%a_][%w_]*)%s*%)",
            "assert%s*%(%s*([%a_][%w_]*)%s*%)",
        } do
            local ref = code:match(pattern)
            if ref and not knownCalls[ref] and ref ~= "self" and ref ~= "nil" and ref ~= "true" and ref ~= "false" then
                fail(`Unknown variable '{ref}'.`, line.Start)
            end
        end
    end
    for _, line in lines do
        local code = line.Text
        for owner, delimiter, member in code:gmatch("([%a_][%w_]*)%s*([%.:])%s*([%a_][%w_]*)") do
            local className = resolveTypedOwner(owner, line.Start)
            local isStatic = false
            if classes[owner] then className = owner; isStatic = true end
            if owner == "self" then
                for cls, info in classes do
                    if line.Start > info.Start and line.Start < info.Finish then className = cls; break end
                end
            end
            if enums[owner] and not enums[owner][member] then fail(`Enum '{owner}' has no member '{member}'.`, line.Start) end
            if namespaces[owner] and not namespaces[owner][member] then fail(`Namespace '{owner}' has no exported member '{member}'.`, line.Start) end
            if className then
                local found = memberOf(className, member, isStatic)
                if not found and isStatic and delimiter == "." then found = memberOf(className, member, false) end
                if not found and owner == "self" and code:find("self%." .. member .. "%s*=") then continue end
                if not found then fail(`Instance '{className}' has no member '{member}'.`, line.Start) end
                if delimiter == ":" and found.Kind ~= "method" and found.Kind ~= "getter" then fail(`'{className}.{member}' is not a method.`, line.Start) end
            end
        end
        -- Instance-method dot calls require an explicit first argument for self.
        -- This is source Laua preflight only; unknown/dynamic receivers are not guessed.
        for startAt, owner, member in code:gmatch("()([%a_][%w_]*)%s*%.%s*([%a_][%w_]*)%s*%(") do
            local className = resolveTypedOwner(owner, line.Start)
            local fromClass = classes[owner] ~= nil
            if fromClass then className = owner end
            if owner == "self" then
                for cls, info in classes do
                    if line.Start > info.Start and line.Start < info.Finish then className = cls; break end
                end
            end
            local instanceMember = className and memberOf(className, member, false)
            local staticMember = className and memberOf(className, member, true)
            if instanceMember and instanceMember.Kind == "method" and (not fromClass or not staticMember) then
                local open = code:find("%(", startAt)
                local close = open and findCloseParen(code, open)
                if open and close then
                    local raw = source:sub(line.Start, line.Finish)
                    local args = raw:sub(open + 1, close - 1)
                    if trim(args) == "" then
                        fail(`Instance method '{className}.{member}' called with '.' without self. Use {owner}:{member}(...) or pass an explicit first argument.`, line.Start + startAt - 1)
                    end
                    local parts = paramParts(args)
                    if #parts == 0 or trim(parts[1]) == "" then
                        fail(`Instance method '{className}.{member}' needs a first self argument.`, line.Start + startAt - 1)
                    end
                    table.remove(parts, 1)
                    checkCall(className .. "." .. member, instanceMember.Params, table.concat(parts, ", "), line.Start + startAt - 1)
                end
            end
        end
        for startAt, owner, member in code:gmatch("()([%a_][%w_]*)%s*:%s*([%a_][%w_]*)%s*%(") do
            local className = resolveTypedOwner(owner, line.Start)
            if owner == "self" then
                for cls, info in classes do
                    if line.Start > info.Start and line.Start < info.Finish then className = cls; break end
                end
            end
            local info = className and memberOf(className, member, false)
            if info and info.Kind == "getter" then
                local opening = code:find("%(", startAt)
                local closing = opening and findCloseParen(code, opening)
                if not closing then fail(`Unclosed getter access '{className}.{member}'.`, line.Start + startAt - 1) end
                local raw = source:sub(line.Start, line.Finish)
                if trim(raw:sub(opening + 1, closing - 1)) ~= "" then fail(`Getter '{className}.{member}' takes no arguments.`, line.Start + startAt - 1) end
                table.insert(getterRewrites, {First = line.Start + startAt - 1, Last = line.Start + closing - 1, Text = owner .. "." .. member})
            elseif info and info.Kind == "method" then
                local opening = code:find("%(", startAt)
                local closing = opening and findCloseParen(code, opening)
                if opening and closing then
                    local raw = source:sub(line.Start, line.Finish)
                    checkCall(className .. "." .. member, info.Params, raw:sub(opening + 1, closing - 1), line.Start + startAt - 1)
                end
            end
        end
        for fname, args in code:gmatch("([%a_][%w_]*)%s*%(([^)]*)%)") do
            if functions[fname] and not code:match("^%s*local%s+function%s+" .. fname) and not code:match("^%s*function%s+" .. fname) then
                checkCall(fname, functions[fname], args, line.Start)
            end
        end
    end
    return getterRewrites
end

-- v3.40 conservative native checks. Do not invent types for dynamic expressions.
local function validateTypedSemantics(source: string)
    if source:find("local __laua", 1, true) then return end
    local masked = maskNonCode(source)
    local lines = splitLines(masked)
    local types: {[string]: string} = {}
    local instances: {[string]: string} = {}
    local classFields: {[string]: {[string]: string}} = {}
    local classBases: {[string]: string} = {}
    local parameters: {[string]: string} = {}
    local functions: {[string]: {Params: string, Result: string}} = {}
    local aliases: {[string]: string} = {}
    local function fail(message: string, at: number)
        local line = 1
        local column = 1
        for index = 1, math.max(0, at - 1) do
            if source:sub(index, index) == "\n" then line += 1; column = 1 else column += 1 end
        end
        error(`Laua semantic error (line {line}, column {column}): {message}`, 2)
    end
    local function normalType(raw: string?): string
        if not raw then return "any" end
        local clean = trim(raw)
        if aliases[clean] then return aliases[clean] end
        if clean:match("^{[%a_][%w_]*}$") then return clean end
        return clean
    end
    local function infer(raw: string): string
        local clean = trim(raw)
        if clean:match("^%-?%d[%d_]*%.?[%d_]*$") then return "number" end
        if clean == "true" or clean == "false" then return "boolean" end
        if clean == "nil" then return "nil" end
        if clean:match("^[\"'`]") then return "string" end
        if clean:match("^new%s+[%a_][%w_]*%s*%(") then return clean:match("^new%s+([%a_][%w_]*)") or "any" end
        if clean:match("^%b{}$") then return "table" end
        if clean:match("^[%a_][%w_]*$") then return types[clean] or parameters[clean] or instances[clean] or "any" end
        local fname = clean:match("^([%a_][%w_]*)%s*%(")
        if fname and functions[fname] then return functions[fname].Result end
        local owner, field = clean:match("^([%a_][%w_]*)%.([%a_][%w_]*)$")
        if owner and field then
            local className = instances[owner]
            local seen = {}
            while className and not seen[className] do
                seen[className] = true
                if classFields[className] and classFields[className][field] then return classFields[className][field] end
                className = classBases[className]
            end
        end
        return "any"
    end
    local function compatible(actual: string, expected: string): boolean
        if actual == "any" or expected == "any" or actual == expected then return true end
        if expected:sub(-1) == "?" and (actual == "nil" or actual == expected:sub(1, -2)) then return true end
        if actual == "table" and expected:sub(1, 1) == "{" then return true end
        return false
    end
    local function check(actual: string, expected: string, at: number, context: string)
        if compatible(actual, expected) then return end
        fail(`{context} expects {expected}, received {actual}.`, at)
    end
    -- Register type names, class fields, and return signatures before checking uses.
    for _, line in lines do
        local code = trim(line.Text)
        local alias, primitive = code:match("^type%s+([%a_][%w_]*)%s*=%s*([%a_][%w_]*%??)%s*$")
        if alias and primitive then aliases[alias] = primitive end
        local classname, base = code:match("^class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_]*)%s*$")
        if not classname then classname, base = code:match("^final%s+class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_]*)%s*$") end
        if not classname then classname, base = code:match("^abstract%s+class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_]*)%s*$") end
        if not classname then classname = code:match("^class%s+([%a_][%w_]*)%s*$") end
        if not classname then classname = code:match("^final%s+class%s+([%a_][%w_]*)%s*$") end
        if not classname then classname = code:match("^abstract%s+class%s+([%a_][%w_]*)%s*$") end
        if classname then
            classFields[classname] = classFields[classname] or {}
            if base then classBases[classname] = base end
            local ending = findBlock(source, line.Start, lines)
            for _, child in lines do
                if child.Start <= line.Start or child.Start >= ending.Start then continue end
                local row = trim(child.Text)
                local field, annotation = row:match("^([%a_][%w_]*)%s*:%s*([%a_][%w_]*%??)%s*=")
                if not field then field, annotation = row:match("^([%a_][%w_]*)%s*:%s*([%a_][%w_]*%??)%s*$") end
                if field and annotation then classFields[classname][field] = normalType(annotation) end
            end
        end
        local fn, args, result = code:match("^function%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*:%s*([%a_][%w_]*%??)")
        if not fn then fn, args = code:match("^function%s+([%a_][%w_]*)%s*%(([^)]*)%)") end
        if not fn then fn, args, result = code:match("^local%s+function%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*:%s*([%a_][%w_]*%??)") end
        if not fn then fn, args = code:match("^local%s+function%s+([%a_][%w_]*)%s*%(([^)]*)%)") end
        if fn and args then functions[fn] = {Params = args, Result = normalType(result)} end
    end
    local activeReturn: string? = nil
    local activeName: string? = nil
    local activeStart = 0
    local returned = false
    local sawReturnAny = false
    local hasElse = false
    local nested = 0
    local functionStack: {any} = {}
    for _, line in lines do
        local code = trim(line.Text)
        if code == "" then continue end
        local fn, args, result = code:match("^function%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*:%s*([%a_][%w_]*%??)")
        if not fn then fn, args, result = code:match("^local%s+function%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*:%s*([%a_][%w_]*%??)") end
        if not fn then fn, args = code:match("^function%s+([%a_][%w_]*)%s*%(([^)]*)%)") end
        if not fn then fn, args = code:match("^local%s+function%s+([%a_][%w_]*)%s*%(([^)]*)%)") end
        if fn and args then
            table.insert(functionStack, {Result = activeReturn, Name = activeName, Start = activeStart, Returned = returned, SawReturn = sawReturnAny, HasElse = hasElse, Depth = nested, Parameters = parameters})
            activeReturn = normalType(result)
            activeName = fn
            activeStart = line.Start
            returned = false
            sawReturnAny = false
            hasElse = false
            nested = 0
            parameters = {}
            for param, annotation in args:gmatch("([%a_][%w_]*)%s*:%s*([%a_][%w_]*%??)") do parameters[param] = normalType(annotation) end
        elseif activeReturn and code:match("^end%s*$") then
            if nested > 0 then
                nested -= 1
            else
                if not returned and not (sawReturnAny and hasElse) and activeReturn ~= "any" and activeReturn ~= "nil" then
                    fail(`Function '{activeName}' may finish without returning {activeReturn}.`, line.Start)
                end
                local previous = table.remove(functionStack)
                if previous then
                    activeReturn, activeName, activeStart, returned, sawReturnAny, hasElse, nested, parameters = previous.Result, previous.Name, previous.Start, previous.Returned, previous.SawReturn, previous.HasElse, previous.Depth, previous.Parameters
                else
                    activeReturn = nil
                end
            end
        elseif activeReturn and code:match("^if%s+.+%sthen%s+return%s+.+%selse%s+return%s+.+%send%s*$") then
            returned = true; sawReturnAny = true; hasElse = true
        elseif activeReturn and (code:match("^if%s+.*%sthen%s*$") or code:match("^for%s+.*%sdo%s*$") or code:match("^while%s+.*%sdo%s*$")) then
            nested += 1
        end
        if activeReturn and code:match("^else%s*$") then hasElse = true end
        local localName, annotation, initial = code:match("^local%s+([%a_][%w_]*)%s*:%s*([%a_][%w_]*%??)%s*=%s*(.+)$")
        if localName and annotation then
            local typed = normalType(annotation)
            local actual = infer(source:sub(line.Start, line.Finish):match("=%s*(.-)%s*$") or initial)
            check(actual, typed, line.Start, "Assignment")
            types[localName] = typed
            if classFields[typed] then instances[localName] = typed end
        else
            local inferredName, inferredClass = code:match("^local%s+([%a_][%w_]*)%s*=%s*new%s+([%a_][%w_]*)")
            if inferredName and inferredClass and classFields[inferredClass] then instances[inferredName] = inferredClass end
            local name, expression = code:match("^local%s+([%a_][%w_]*)%s*=%s*(.+)$")
            if name and expression then types[name] = infer(source:sub(line.Start, line.Finish):match("=%s*(.-)%s*$") or expression) end
        end
        local owner, member, value = code:match("^([%a_][%w_]*)%.([%a_][%w_]*)%s*=%s*(.+)$")
        if owner and member and value then
            local className = instances[owner]
            local seen = {}
            while className and not seen[className] do
                seen[className] = true
                local fieldType = classFields[className] and classFields[className][member]
                if fieldType then
                    local actual = source:sub(line.Start, line.Finish):match("=%s*(.-)%s*$") or value
                    check(infer(actual), fieldType, line.Start, "Assignment")
                    break
                end
                className = classBases[className]
            end
        end
        local assigned, operator, rhs = code:match("^([%a_][%w_]*)%s*([%+%-%*/])=%s*(.+)$")
        if assigned and operator and rhs then
            check(types[assigned] or parameters[assigned] or "any", "number", line.Start, "Left operand")
            local actual = source:sub(line.Start, line.Finish):match("=%s*(.-)%s*$") or rhs
            check(infer(actual), "number", line.Start, "Right operand")
        else
            local assignedName, assignedValue = code:match("^([%a_][%w_]*)%s*=%s*(.+)$")
            if assignedName and assignedValue then
                local expected = parameters[assignedName] or types[assignedName]
                if expected then
                    local actual = source:sub(line.Start, line.Finish):match("=%s*(.-)%s*$") or assignedValue
                    check(infer(actual), expected, line.Start, "Assignment")
                end
            end
        end
        local ret = code:match("^return%s+(.+)$")
        if activeReturn and ret then
            local original = trim(source:sub(line.Start, line.Finish):match("return%s+(.+)$") or ret)
            check(infer(original), activeReturn, line.Start, "Return")
            sawReturnAny = true
            if nested == 0 then returned = true end
        end
    end
end

-- Laua v3.41 experimental native parity for opt-in declarations.
local function contractPredicate(expression: string, name: string): string
    if name == "any" then return "true" end
    if name == "Instance" then return `typeof({expression}) == "Instance"` end
    local known = {string = true, number = true, boolean = true, table = true, Vector3 = true, CFrame = true, Color3 = true}
    if known[name] then return `typeof({expression}) == "{name}"` end
    local array = name:match("^{([%a_][%w_]*)}$")
    if array then
        local predicate = contractPredicate("item", array)
        return `(type({expression}) == "table" and (function() for _, item in {expression} do if not ({predicate}) then return false end end return true end)())`
    end
    if not name:match("^[%a_][%w_]*$") then error(`Unsupported contract type '{name}'`) end
    return `(type({name}) == "table" and type({name}.Validate) == "function" and {name}.Validate({expression}))`
end

local function contractParams(raw: string): {any}
    local fields = {}
    local seen = {}
    if trim(raw) == "" then return fields end
    for part in raw:gmatch("[^,]+") do
        local name, annotation = trim(part):match("^([%a_][%w_]*)%s*:%s*(.-)%s*$")
        if not name or seen[name] then error(`Invalid or duplicate contract parameter '{trim(part)}'`) end
        seen[name] = true
        local isOptional = annotation:sub(-1) == "?"
        if isOptional then annotation = annotation:sub(1,-2) end
        if not annotation:match("^[%a_][%w_]*$") and not annotation:match("^{[%a_][%w_]*}$") then error(`Invalid contract type '{annotation}'`) end
        table.insert(fields, {Name = name, Type = annotation, Optional = isOptional})
    end
    return fields
end

local function nativeTranspileContracts(source: string): string
    local lines = splitLines(maskNonCode(source))
    local replacements = {}
    for _, line in lines do
        local kind, name = trim(line.Text):match("^(schema)%s+([%a_][%w_]*)$")
        if not kind then continue end
        local closing = findBlock(source, line.Start, lines)
        local rows = splitLines(source:sub(line.Finish + 2, closing.Start - 1))
        local out = {}
        if kind == "schema" then
            table.insert(out, "local " .. name .. " = {}")
            table.insert(out, `function {name}.Validate(value: any): (boolean, string?)`)
            table.insert(out, '    if type(value) ~= "table" then return false, "Expected table" end')
            local seen = {}
            for _, row in rows do
                local original = trim(row.Text)
                if original == "" or original:match("^%-%-") then continue end
                local field, annotation = original:match("^([%a_][%w_]*)%s*:%s*([^,%s]+)%s*,?$")
                if not field or seen[field] then error(`Invalid or duplicate schema field '{original}'`) end
                seen[field] = true
                local optional = annotation:sub(-1) == "?"
                if optional then annotation = annotation:sub(1,-2) end
                local value = `value["{field}"]`
                local predicate = contractPredicate(value, annotation)
                local guard = optional and `{value} ~= nil and ` or ""
                table.insert(out, `    if {guard}not ({predicate}) then return false, "Invalid field {field}: expected {annotation}" end`)
            end
            table.insert(out,'    return true, nil')
            table.insert(out,'end')
            table.insert(out,`function {name}.Assert(value: any): any`)
            table.insert(out,`    local ok, message = {name}.Validate(value)`)
            table.insert(out,'    if not ok then error(message, 2) end')
            table.insert(out,'    return value')
            table.insert(out,'end')
        end
        table.insert(replacements, {First=line.Start, Last=closing.Finish, Text=table.concat(out,'\n')})
    end
    for index = #replacements, 1, -1 do
        local r = replacements[index]
        source = replaceRange(source,r.First,r.Last,r.Text)
    end
    return source
end

local function nativeExhaustiveMatches(source: string): string
    local masked = maskNonCode(source)
    local classes, typeNames = {}, {}
    for _, line in splitLines(masked) do
        local name = trim(line.Text):match('^enum%s+([%a_][%w_]*)$')
        if name then
            local closing = findBlock(source,line.Start)
            local members = {}
            for _, row in splitLines(source:sub(line.Finish+2,closing.Start-1)) do
                local member = trim(row.Text):match('^([%a_][%w_]*)%s*=?')
                if member then members[member]=true end
            end
            classes[name]=members
        end
    end
    for name, annotation in masked:gmatch('local%s+([%a_][%w_]*)%s*:%s*([%a_][%w_]*)') do typeNames[name]=annotation end
    local replacements = {}
    for _, line in splitLines(masked) do
        local subject = trim(line.Text):match('^match%s+exhaustive%s+(.+)$')
        if not subject then continue end
        local closing = findBlock(source,line.Start)
        local kind = typeNames[subject]
        local matched,default,guard = {},false,false
        for _, row in splitLines(source:sub(line.Finish+2,closing.Start-1)) do
            local code = trim(row.Text)
            if code=='default' then default=true end
            local c = code:match('^case%s+(.+)$')
            if c then
                if c:find(' if ',1,true) then guard=true;c=c:match('^(.-)%s+if%s+') end
                if matched[c] then error(`Duplicate exhaustive match case '{c}'`) end
                matched[c]=true
                local enum = c:match('^([%a_][%w_]*)%.')
                if enum and classes[enum] then
                    if kind and kind~=enum then error('Exhaustive match mixes enum types') end
                    kind=enum
                end
            end
        end
        if not default then
            if guard then error('Guarded exhaustive match requires default') end
            local expected = {}
            if kind=='boolean' then expected={'true','false'}
            elseif classes[kind or ''] then for member in classes[kind] do table.insert(expected,kind..'.'..member) end
            else error('Exhaustive match needs an enum/boolean-typed subject or default') end
            for _, item in expected do if not matched[item] then error(`Non-exhaustive match: missing {item}`) end end
        end
        local start=line.Start + (line.Text:find('exhaustive',1,true) or 1)-1
        table.insert(replacements,{First=start,Last=start+#'exhaustive ',Text=''})
    end
    for index=#replacements,1,-1 do
        local r=replacements[index]
        source=source:sub(1,r.First-1)..source:sub(r.Last)
    end
    return source
end

local NATIVE_CANCELLATION_RUNTIME = [==[
local __lauaCancelScope = {}
function __lauaCancelScope.new()
    local scope = {_cancelled = false, _jobs = {}, _cleanups = {}}
    function scope:OnCancel(callback)
        assert(type(callback) == "function", "OnCancel expects function")
        if self._cancelled then callback(); return end
        table.insert(self._cleanups, callback)
    end
    function scope:Spawn(callback)
        assert(type(callback) == "function", "Spawn expects function")
        if self._cancelled then return nil end
        local thread = task.spawn(function() if not self._cancelled then callback(self) end end)
        table.insert(self._jobs, thread)
        return thread
    end
    function scope:Cancel()
        if self._cancelled then return end
        self._cancelled = true
        for _, thread in self._jobs do pcall(task.cancel, thread) end
        table.clear(self._jobs)
        for i = #self._cleanups, 1, -1 do pcall(self._cleanups[i]) end
        table.clear(self._cleanups)
    end
    scope.Dispose = scope.Cancel
    return scope
end
]==]
local function nativeCancelScopes(source: string): string
    local masked=maskNonCode(source)
    local locations = {}
    local from=1
    while true do
        local start,finish=masked:find('%f[%w]cancelScope%s*%(%s*%)',from)
        if not start then break end
        local previous=masked:sub(start-1,start-1)
        if previous~='.' and previous~=':' then table.insert(locations,{Start=start,Finish=finish}) end
        from=finish+1
    end
    if #locations==0 then return source end
    for index=#locations,1,-1 do
        local match=locations[index]
        source=replaceRange(source,match.Start,match.Finish,'__lauaCancelScope.new()')
    end
    local header = source:match('^(%s*%-%-![^\n]*\n)') or ''
    return header..NATIVE_CANCELLATION_RUNTIME..'\n'..source:sub(#header+1)
end

local function nativeMaskContractBodies(source: string): string
    local masked=maskNonCode(source)
    local ranges={}
    local lines=splitLines(masked)
    for _,line in lines do
        local code=trim(line.Text)
        if not code:match('^schema%s+[%a_][%w_]*$') then continue end
        local ending=findBlock(source,line.Start,lines)
        table.insert(ranges,{First=line.Start,Last=ending.Finish})
    end
    for index=#ranges,1,-1 do
        local r=ranges[index]
        local section=source:sub(r.First,r.Last):gsub('[^\n\r]',' ')
        source=replaceRange(source,r.First,r.Last,section)
    end
    return source
end

-- Guard generated implementation names against user declarations, including
-- nested scopes. Deliberately inspect declarations only, not field access or
-- string/comment contents.
local LAUA_RESERVED_SYMBOLS = {
    Promise = true, Promises = true, LauaPromiseStatus = true,
    LauaPackedValues = true, LauaPromiseState = true,
    LauaCore = true,
}

local function validateReservedBindings(source: string)
    local masked = maskNonCode(source)
    local function check(name: string?, at: number?)
        if not name or not at then return end
        if not (name:sub(1, 6) == "__laua" or LAUA_RESERVED_SYMBOLS[name]) then return end
        local prefix = source:sub(1, at - 1)
        local _, lineCount = prefix:gsub("\n", "\n")
        local column = at - (prefix:match(".*()\n") or 0)
        error(`Laua semantic error (line {lineCount + 1}, column {column}): '{name}' is reserved for Laua internals. Rename the declared symbol.`)
    end
    local position = 1
    while position <= #masked do
        local ending = masked:find("\n", position, true) or (#masked + 1)
        local row = masked:sub(position, ending - 1)
        local function checkCaptured(pattern: string)
            local before, name = row:match(pattern)
            if name then
                local at = row:find(name, #before + 1, true)
                if at then check(name, position + at - 1) end
            end
        end
        for _, pattern in {
            "^(.-)%f[%w]local%s+function%s+([%a_][%w_]*)",
            "^(.-)%f[%w]function%s+([%a_][%w_]*)%s*%(",
            "^(.-)%f[%w]class%s+([%a_][%w_]*)",
            "^(.-)%f[%w]namespace%s+([%a_][%w_]*)",
            "^(.-)%f[%w]enum%s+([%a_][%w_]*)",
            "^(.-)%f[%w]schema%s+([%a_][%w_]*)",
            "^(.-)%f[%w]type%s+([%a_][%w_]*)",
            "^(.-)%f[%w]import%s+([%a_][%w_]*)%s+from",
            "^(.-)%f[%w]as%s+([%a_][%w_]*)",
            "^(.-)%f[%w]for%s+([%a_][%w_]*)",
        } do checkCaptured(pattern) end
        -- Local/const/using declarations can contain multiple names.
        for _, decl in {"local", "const", "using"} do
            local restStart, restEnd = row:find("%f[%w]" .. decl .. "%s+")
            if restEnd then
                local tail = row:sub(restEnd + 1)
                if tail:sub(1, 8) ~= "function" then
                    local names = tail:match("^([%a_][%w_]*[%s,%w_]*)") or ""
                    for token in names:gmatch("[%a_][%w_]*") do
                        local at = row:find(token, restEnd + 1, true)
                        if at then check(token, position + at - 1) end
                    end
                end
            end
        end
        -- Function/constructor parameters, excluding annotations.
        local params = row:match("%f[%w]function%s*[%w_%.:]*%s*%(([^)]*)")
            or row:match("%f[%w]constructor%s*%(([^)]*)")
        if params then
            local open = row:find("%(", 1)
            local at = (open or 0) + 1
            for argument in (params .. ","):gmatch("(.-),") do
                local name = argument:match("^%s*([%a_][%w_]*)")
                if name then
                    local index = row:find(name, at, true)
                    if index then check(name, position + index - 1) end
                end
                at += #argument + 1
            end
        end
        position = ending + 1
    end
end

-- Export syntax is lowered after semantic validation. Mask only the export
-- prefix of class headers, keeping offsets identical to the original source.
local function maskExportedClassDeclarations(source: string): string
    return (source:gsub("[^\n]+", function(row: string): string
        local indentation, spacing, header = row:match("^([ \t]*)export([ \t]+)(.*)$")
        if not header then return row end
        if not (header:match("^class%s+") or header:match("^final%s+class%s+") or header:match("^abstract%s+class%s+")) then return row end
        return indentation .. string.rep(" ", #"export" + #spacing) .. header
    end))
end

function Transpiler.Transpile(source: string, options: any?): string
    assert(type(source) == "string", "Expected Laua source string")
    local mode = type(options) == "table" and options.Mode or "Development"
    if mode ~= "Development" and mode ~= "Release" and mode ~= "Debug" then error("Invalid Laua compile mode") end
    local style = type(options) == "table" and options.OutputStyle or "Readable"
    if style ~= "Readable" and style ~= "Compact" then error("Invalid Laua output style") end

    if source:find("--#", 1, true) then source = preprocessMode(source, mode) end
    validateExpressionSyntax(source)
    local checkSource = (source:find('schema', 1, true)) and nativeMaskContractBodies(source) or source
    checkSource = maskExportedClassDeclarations(checkSource)
    local getterRewrites = {}
    if type(options) ~= "table" or options.SemanticCheck ~= false then
        validateReservedBindings(source)
        validateClassContracts(checkSource)
        getterRewrites = validateLauaSemantics(checkSource)
        validateTypedSemantics(checkSource)
    end
    for index = #getterRewrites, 1, -1 do
        local edit = getterRewrites[index]
        source = replaceRange(source, edit.First, edit.Last, edit.Text)
    end
    -- Earlier passes may introduce syntax for later passes. Inspect current text.
    if source:find("match exhaustive", 1, true) then source = nativeExhaustiveMatches(source) end
    if source:find("schema", 1, true) then source = nativeTranspileContracts(source) end
    if source:find("cancelScope", 1, true) then source = nativeCancelScopes(source) end
    if source:find("inline", 1, true) then source = transpileInlineFunctions(source) end
    validateKnownVisibility(source)
    validatePendingFeatures(source)
    if source:find("|>", 1, true) then source = transpilePipelines(source) end
    if source:find("memo", 1, true) then source = transpileMemo(source) end
    if source:find("memo", 1, true) then source = transpileMemoClear(source) end
    if source:find("%f[%w]is%f[%W]") then source = transpileIsOperator(source) end
    if source:find("=>", 1, true) or source:find("...", 1, true) or source:find("[", 1, true) or source:find("table.", 1, true) or source:find("import", 1, true) or source:find("@nolint", 1, true) then
        source = transpileAdditionalSyntax(source)
    end
    local exportedNames = {}
    local exportedClassName: string? = nil
    if source:find("export", 1, true) then source, exportedNames, exportedClassName = transpileExports(source) end
    if source:find("??=", 1, true) then source = transpileCoalescingAssign(source) end
    if source:find("using", 1, true) then source = transpileUsing(source) end
    source = transpileSource(source)
    if source:find("import", 1, true) then source = transpileImports(source) end
    if source:find("local", 1, true) and source:find("{", 1, true) then source = transpileDestructuring(source) end
    if source:find("match", 1, true) then source = transpileMatches(source) end
    if source:find("?.", 1, true) then source = (transpileOptional(source)) end
    if source:find("??", 1, true) then source = (transpileCoalescing(source)) end
    if source:find("?", 1, true) then source = transpileEarlyReturn(source) end
    if source:find("defer", 1, true) then source = transpileDefers(source) end
    local asyncCount = 0
    if source:find("async", 1, true) then source, asyncCount = transpileAsyncFunctions(source) end
    local awaitCount = 0
    if source:find("await", 1, true) then source, awaitCount = transpileAwaits(source) end
    if awaitCount > 0 and asyncCount == 0 then error("await requires an async function") end
    if source:find("function", 1, true) and source:find("=", 1, true) then source = transpileParameterDefaults(source) end
    if source:find("__laua", 1, true) then source = insertEmbeddedRuntimes(source) end
    if exportedClassName then
        source ..= "\nreturn " .. exportedClassName
    elseif #exportedNames > 0 then
        local values = {}
        for _, name in exportedNames do table.insert(values, `{name} = {name}`) end
        source ..= "\nreturn {" .. table.concat(values, ", ") .. "}"
    end
    source = source:gsub("[ \t]+\n", "\n")
    -- Narrow generated-syntax preflight. Roblox Studio remains the final parser.
    if not source:find("[[", 1, true) then
        local masked = maskNonCode(source)
        if masked:find("}%d") or masked:find("%)%d") then
            error("Generated Luau contains an expression immediately followed by a number without a separator")
        end
    end
    local generated = style == "Compact" and compactGeneratedOutput(source) or source
    local header = "-- Transpiled with laua v" .. Transpiler.Version
    if generated:sub(1, #header + 1) == header .. "\n" or generated == header then return generated end
    return header .. "\n" .. generated
end

return Transpiler
