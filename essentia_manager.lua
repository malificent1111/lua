local component = require("component")
local event = require("event")
local computer = require("computer")
local filesystem = require("filesystem")
local serialization = require("serialization")
local term = require("term")
local sides = require("sides")


-- ============================================================
-- LOG
-- ============================================================

local function log(...)
    print(...)
end


-- ============================================================
-- COMPONENTS
-- ============================================================

assert(component.isAvailable("gpu"),
    "GPU component not found.")

assert(component.isAvailable("me_controller"),
    "ME Controller component not found.")

assert(component.isAvailable("me_interface"),
    "ME Interface component not found.")

assert(component.isAvailable("inventory_controller"),
    "Inventory Controller component not found.")

local gpu = component.gpu
local me = component.me_controller
local interface = component.me_interface
local inventory = component.inventory_controller


-- ============================================================
-- PHYSICAL CONFIGURATION
-- ============================================================
--
-- Scanner chest:
--
--        [Scanner Chest]
--               |
--             NORTH
--               |
--              OC
--
-- Put the source item into slot 1 of this chest.
--
-- The ME Interface exports source items into another chest.
--
-- ============================================================

local SOURCE_SCAN_SIDE = sides.north
local SOURCE_SCAN_SLOT = 1

local EXPORT_SIDE = sides.down
local EXPORT_SLOT = 1


-- ============================================================
-- GENERAL CONFIG
-- ============================================================

local CONFIG_FILE = "/home/essentia_manager.cfg"

local ESSENTIA_SCALE = 128

local DEFAULT_TARGET = 2048
local DEFAULT_TRIGGER = 512
local DEFAULT_YIELD = 1

local REFRESH_INTERVAL = 1.0

local SOURCE_SCAN_REFRESH = 1.0

local CRAFT_RECHECK_INTERVAL = 30

local MAX_EXPORT_PER_RUN = 4096


-- ============================================================
-- SCREEN CONFIG
-- ============================================================

local width, height = gpu.getResolution()

local ROWS = math.max(5, height - 8)

local page = 1
local selected = nil

local uiDirty = true
local fullRedraw = true

local lastRefresh = 0


-- ============================================================
-- COLORS
-- ============================================================

local COLOR_BG = 0x202020
local COLOR_HEADER = 0x303030
local COLOR_SELECTED = 0x304060
local COLOR_BUTTON = 0x404040

local COLOR_WHITE = 0xFFFFFF
local COLOR_GREY = 0x909090
local COLOR_GREEN = 0x55FF55
local COLOR_YELLOW = 0xFFFF55
local COLOR_RED = 0xFF5555
local COLOR_BLUE = 0x55AAFF


-- ============================================================
-- DATA
-- ============================================================

local config = {}

local fluids = {}

local currentEssentia = {}

local allItems = {}

local allItemsIndex = {}

local sourceAmounts = {}

local craftStatus = {}

local craftAttemptTime = {}

local status = {}

local aspects = {}

local lastRows = {}

local scannerItem = nil

local lastScannerScan = 0


-- ============================================================
-- UTILITY
-- ============================================================

local function safeNumber(value, fallback)
    local number = tonumber(value)

    if number == nil then
        return fallback
    end

    return number
end


local function normalizeAspect(value)
    if not value then
        return nil
    end

    return tostring(value):lower()
end


local function prettyAspect(aspect)
    if not aspect then
        return "?"
    end

    aspect = tostring(aspect)

    return aspect:sub(1, 1):upper() .. aspect:sub(2)
end


local function numberString(value)
    value = math.floor(safeNumber(value, 0))

    local valueString = tostring(value)

    while true do
        local replaced, count =
            valueString:gsub(
                "^(-?%d+)(%d%d%d)",
                "%1 %2"
            )

        if count == 0 then
            break
        end

        valueString = replaced
    end

    return valueString
end


local function realEssentiaAmount(value)
    return math.floor(
        safeNumber(value, 0) / ESSENTIA_SCALE
    )
end


local function fingerprintKey(name, damage)
    return tostring(name or "")
        .. "|"
        .. tostring(safeNumber(damage, 0))
end


-- ============================================================
-- CONFIGURATION
-- ============================================================

local function defaultConfig()
    return {
        enabled = false,

        target = DEFAULT_TARGET,

        trigger = DEFAULT_TRIGGER,

        sourceId = "",

        sourceDamage = 0,

        essentiaPerItem = DEFAULT_YIELD
    }
end


local function ensureConfig(aspect)

    if not config[aspect] then
        config[aspect] = defaultConfig()
    end

    local current = config[aspect]

    if current.enabled == nil then
        current.enabled = false
    end

    if current.target == nil then
        current.target = DEFAULT_TARGET
    end

    if current.trigger == nil then
        current.trigger = DEFAULT_TRIGGER
    end

    if current.sourceId == nil then
        current.sourceId = ""
    end

    if current.sourceDamage == nil then
        current.sourceDamage = 0
    end

    if current.essentiaPerItem == nil then
        current.essentiaPerItem = DEFAULT_YIELD
    end

    return current
end


local function loadConfig()

    if not filesystem.exists(CONFIG_FILE) then
        config = {}
        return
    end

    local file = io.open(CONFIG_FILE, "r")

    if not file then
        config = {}
        return
    end

    local data = file:read("*a")

    file:close()

    local ok, result =
        pcall(
            serialization.unserialize,
            data
        )

    if ok and type(result) == "table" then
        config = result
    else
        config = {}
    end
end


local function saveConfig()

    local file = io.open(CONFIG_FILE, "w")

    if not file then
        return false
    end

    file:write(
        serialization.serialize(config)
    )

    file:close()

    return true
end


-- ============================================================
-- FLUID SCAN
-- ============================================================

local function parseEssentiaFluid(name)

    if type(name) ~= "string" then
        return nil
    end

    local lowerName = name:lower()

    if lowerName:sub(1, 7) ~= "gaseous" then
        return nil
    end

    if lowerName:sub(-8) ~= "essentia" then
        return nil
    end

    local aspect =
        lowerName:sub(8, -9)

    if aspect == "" then
        return nil
    end

    return aspect
end


local function scanFluids()

    local result = {}

    local ok, rawFluids =
        pcall(
            me.getFluidsInNetwork
        )

    if not ok or type(rawFluids) ~= "table" then
        return result
    end

    for _, fluid in pairs(rawFluids) do

        local aspect =
            parseEssentiaFluid(
                fluid.name
            )

        if aspect then

            result[aspect] = {
                amount = realEssentiaAmount(
                    fluid.amount
                ),

                rawAmount = safeNumber(
                    fluid.amount,
                    0
                ),

                name = fluid.name,

                label =
                    fluid.label
                    or prettyAspect(aspect)
            }
        end
    end

    return result
end


-- ============================================================
-- ITEM SCAN
-- ============================================================
--
-- One complete ME item query.
--
-- Everything else uses the local index.
-- ============================================================

local function scanAllItems()

    local result = {}

    local ok, rawItems =
        pcall(
            me.getItemsInNetwork,
            {}
        )

    if not ok or type(rawItems) ~= "table" then
        return result
    end

    for _, item in pairs(rawItems) do

        local name =
            item.name

        local damage =
            safeNumber(
                item.damage,
                0
            )

        if name then

            local key =
                fingerprintKey(
                    name,
                    damage
                )

            result[key] =
                (
                    result[key]
                    or 0
                )
                + safeNumber(
                    item.size,
                    0
                )
        end
    end

    return result
end


-- ============================================================
-- SOURCE SCANNER
-- ============================================================

local function scanSourceChest()

    local ok, stack =
        pcall(
            inventory.getStackInSlot,
            SOURCE_SCAN_SIDE,
            SOURCE_SCAN_SLOT
        )

    if not ok or type(stack) ~= "table" then
        scannerItem = nil
        return nil
    end

    if not stack.name then
        scannerItem = nil
        return nil
    end

    scannerItem = {
        name = stack.name,

        damage =
            safeNumber(
                stack.damage,
                0
            ),

        size =
            safeNumber(
                stack.size,
                0
            ),

        label =
            stack.label
            or stack.name,

        hasTag =
            stack.hasTag
            or false
    }

    return scannerItem
end


-- ============================================================
-- SOURCE ITEM DATA
-- ============================================================

local function getSourceConfig(aspect)

    local current =
        ensureConfig(aspect)

    if current.sourceId == "" then
        return nil
    end

    return {
        name = current.sourceId,

        damage =
            safeNumber(
                current.sourceDamage,
                0
            )
    }
end


local function getSourceAmount(aspect)

    local source =
        getSourceConfig(aspect)

    if not source then
        return 0
    end

    local key =
        fingerprintKey(
            source.name,
            source.damage
        )

    return safeNumber(
        allItemsIndex[key],
        0
    )
end


-- ============================================================
-- CRAFT SOURCE ITEM
-- ============================================================

local function sourceCraftable(aspect)

    local source =
        getSourceConfig(aspect)

    if not source then
        return false
    end

    local ok, craftables =
        pcall(
            me.getCraftables,
            {
                name = source.name,
                damage = source.damage
            }
        )

    if not ok or type(craftables) ~= "table" then
        return false
    end

    for _, craft in pairs(craftables) do

        local okStack, stack =
            pcall(
                function()
                    return craft.getItemStack()
                end
            )

        if okStack and type(stack) == "table" then

            if stack.name == source.name
                and safeNumber(
                    stack.damage,
                    0
                ) == source.damage then

                return craft
            end
        end
    end

    return false
end


local function requestSourceCraft(
    aspect,
    amount
)

    local now =
        computer.uptime()

    local previous =
        craftAttemptTime[aspect]

    if previous
        and now - previous
            < CRAFT_RECHECK_INTERVAL then

        status[aspect] = "CRAFTING"

        return false
    end


    local craft =
        sourceCraftable(aspect)


    if not craft then

        craftStatus[aspect] = false

        status[aspect] =
            "NO CRAFT"

        return false
    end


    amount =
        math.max(
            1,
            math.floor(amount)
        )


    local ok, request =
        pcall(
            function()
                return craft.request(amount)
            end
        )


    craftAttemptTime[aspect] = now


    if not ok or not request then

        status[aspect] =
            "CRAFT ERROR"

        return false
    end


    craftStatus[aspect] = true

    status[aspect] = "CRAFTING"

    return true
end


-- ============================================================
-- EXPORT
-- ============================================================

local function exportSource(
    aspect,
    amount
)

    local source =
        getSourceConfig(aspect)

    if not source then

        status[aspect] =
            "NO SOURCE"

        return 0
    end


    amount =
        math.floor(amount)


    if amount <= 0 then
        return 0
    end


    amount =
        math.min(
            amount,
            MAX_EXPORT_PER_RUN
        )


    local movedTotal = 0

    for _ = 1, 32 do

        local remaining =
            amount - movedTotal

        if remaining <= 0 then
            break
        end


        local ok, result =
            pcall(
                interface.exportItem,
                {
                    name = source.name,
                    dmg = source.damage
                },
                EXPORT_SIDE,
                remaining,
                EXPORT_SLOT
            )


        if not ok then

            status[aspect] =
                "EXPORT ERROR"

            break
        end


        local moved = 0

        if type(result) == "table" then

            moved =
                safeNumber(
                    result.size,
                    0
                )

        elseif type(result) == "number" then

            moved = result

        end


        if moved <= 0 then
            break
        end


        movedTotal =
            movedTotal + moved
    end


    if movedTotal > 0 then

        status[aspect] =
            "EXPORTED"

    elseif movedTotal == 0 then

        status[aspect] =
            "EXPORT FAILED"
    end


    return movedTotal
end


-- ============================================================
-- ASPECT MAINTENANCE
-- ============================================================

local function maintainAspect(aspect)

    local current =
        ensureConfig(aspect)


    if not current.enabled then

        status[aspect] =
            "OFF"

        return
    end


    if current.sourceId == "" then

        status[aspect] =
            "NO SOURCE"

        return
    end


    local currentEss =
        safeNumber(
            currentEssentia[aspect],
            0
        )


    local target =
        safeNumber(
            current.target,
            0
        )


    local trigger =
        safeNumber(
            current.trigger,
            0
        )


    local refillPoint =
        math.max(
            0,
            target - trigger
        )


    if currentEss > refillPoint then

        if craftStatus[aspect] then

            status[aspect] =
                "CRAFTING"

        else

            status[aspect] =
                "OK"
        end

        return
    end


    local neededEssentia =
        target - currentEss


    if neededEssentia <= 0 then

        status[aspect] =
            "OK"

        return
    end


    local yield =
        safeNumber(
            current.essentiaPerItem,
            1
        )


    if yield <= 0 then

        status[aspect] =
            "BAD YIELD"

        return
    end


    local requiredItems =
        math.ceil(
            neededEssentia / yield
        )


    local available =
        getSourceAmount(aspect)


    sourceAmounts[aspect] =
        available


    if available > 0 then

        local toExport =
            math.min(
                available,
                requiredItems
            )

        local moved =
            exportSource(
                aspect,
                toExport
            )

        if moved > 0 then
            return
        end
    end


    available =
        getSourceAmount(aspect)

    sourceAmounts[aspect] =
        available


    if available >= requiredItems then

        local moved =
            exportSource(
                aspect,
                requiredItems
            )

        if moved > 0 then
            return
        end
    end


    local missing =
        requiredItems - available


    if missing > 0 then

        requestSourceCraft(
            aspect,
            missing
        )

        return
    end
end


-- ============================================================
-- FULL REFRESH
-- ============================================================

local function refreshNetwork()

    local oldEssentia =
        currentEssentia

    local oldSourceAmounts =
        sourceAmounts


    fluids =
        scanFluids()


    allItemsIndex =
        scanAllItems()


    currentEssentia = {}

    for aspect, fluid in pairs(fluids) do

        currentEssentia[aspect] =
            safeNumber(
                fluid.amount,
                0
            )
    end


    sourceAmounts = {}


    local knownAspects = {}


    for aspect in pairs(fluids) do
        knownAspects[aspect] = true
    end


    for aspect in pairs(config) do
        knownAspects[aspect] = true
    end


    aspects = {}


    for aspect in pairs(knownAspects) do

        ensureConfig(aspect)

        table.insert(
            aspects,
            aspect
        )
    end


    table.sort(aspects)


    for _, aspect in ipairs(aspects) do

        sourceAmounts[aspect] =
            getSourceAmount(aspect)

        maintainAspect(aspect)
    end


    saveConfig()


    uiDirty = true
end


-- ============================================================
-- SCREEN DRAWING
-- ============================================================

local function setScreenColors()
    gpu.setBackground(COLOR_BG)
    gpu.setForeground(COLOR_WHITE)
end


local function clearScreen()
    setScreenColors()

    gpu.fill(
        1,
        1,
        width,
        height,
        " "
    )
end


local function drawText(
    x,
    y,
    value,
    color
)

    value =
        tostring(
            value or ""
        )


    if x > width then
        return
    end


    local maxLength =
        width - x + 1


    if #value > maxLength then
        value =
            value:sub(
                1,
                maxLength
            )
    end


    gpu.setForeground(
        color
        or COLOR_WHITE
    )

    gpu.set(
        x,
        y,
        value
    )
end


local function drawButton(
    x,
    y,
    w,
    label,
    active
)

    gpu.setBackground(
        active
        and 0x356A35
        or COLOR_BUTTON
    )

    gpu.setForeground(
        COLOR_WHITE
    )

    gpu.fill(
        x,
        y,
        w,
        1,
        " "
    )


    local textX =
        x +
        math.floor(
            (w - #label) / 2
        )


    if textX < x + 1 then
        textX = x + 1
    end


    gpu.set(
        textX,
        y,
        label
    )

    gpu.setBackground(
        COLOR_BG
    )
end


local function drawFrame()

    clearScreen()


    gpu.setBackground(
        COLOR_HEADER
    )

    gpu.fill(
        1,
        1,
        width,
        2,
        " "
    )

    gpu.setBackground(
        COLOR_BG
    )


    drawText(
        2,
        1,
        "ESSENTIA MANAGER",
        COLOR_WHITE
    )


    local pageCount =
        math.max(
            1,
            math.ceil(
                #aspects / ROWS
            )
        )


    drawText(
        math.max(
            30,
            width - 18
        ),
        1,
        "PAGE "
        .. page
        .. "/"
        .. pageCount,
        COLOR_GREY
    )


    gpu.setBackground(
        COLOR_HEADER
    )

    gpu.fill(
        1,
        3,
        width,
        1,
        " "
    )

    gpu.setBackground(
        COLOR_BG
    )


    drawText(
        2,
        3,
        "ASPECT"
    )

    drawText(
        14,
        3,
        "CURRENT"
    )

    drawText(
        24,
        3,
        "TARGET"
    )

    drawText(
        34,
        3,
        "NEED"
    )

    drawText(
        44,
        3,
        "SOURCE"
    )

    drawText(
        math.max(
            60,
            width - 20
        ),
        3,
        "STATUS"
    )


    drawButton(
        1,
        height - 2,
        10,
        "< PREV",
        page > 1
    )

    drawButton(
        12,
        height - 2,
        10,
        "NEXT >",
        true
    )

    drawButton(
        23,
        height - 2,
        10,
        "RESCAN",
        false
    )


    drawText(
        2,
        height,
        "Click row = configure",
        COLOR_GREY
    )

    drawText(
        width - 8,
        height,
        "Q=quit",
        COLOR_GREY
    )


    fullRedraw = false
end


-- ============================================================
-- ROW DATA
-- ============================================================

local function getRowData(aspect)

    local c =
        ensureConfig(aspect)


    local current =
        safeNumber(
            currentEssentia[aspect],
            0
        )


    local target =
        safeNumber(
            c.target,
            0
        )


    local need =
        math.max(
            0,
            target - current
        )


    local sourceText =
        "-"


    if c.sourceId ~= "" then

        sourceText =
            c.sourceId

        if #sourceText > 18 then

            sourceText =
                sourceText:sub(
                    1,
                    18
                )
        end
    end


    local currentStatus =
        status[aspect]
        or "-"


    return table.concat(
        {
            prettyAspect(aspect),

            numberString(current),

            numberString(target),

            numberString(need),

            sourceText,

            currentStatus,

            c.enabled
                and "ON"
                or "OFF"
        },
        "|"
    )
end


-- ============================================================
-- DRAW ONE ROW
-- ============================================================

local function drawRow(
    aspect,
    rowIndex
)

    local rowY =
        4 + rowIndex - 1


    gpu.setBackground(
        selected == aspect
        and COLOR_SELECTED
        or COLOR_BG
    )


    gpu.fill(
        1,
        rowY,
        width,
        1,
        " "
    )


    gpu.setBackground(
        COLOR_BG
    )


    local c =
        ensureConfig(aspect)


    local current =
        safeNumber(
            currentEssentia[aspect],
            0
        )


    local target =
        safeNumber(
            c.target,
            0
        )


    local need =
        math.max(
            0,
            target - current
        )


    local sourceText = "-"


    if c.sourceId ~= "" then

        sourceText =
            c.sourceId

        if #sourceText > 18 then

            sourceText =
                sourceText:sub(
                    1,
                    18
                )
        end
    end


    local currentStatus =
        status[aspect]
        or "-"


    drawText(
        2,
        rowY,
        prettyAspect(aspect)
    )


    drawText(
        14,
        rowY,
        numberString(current)
    )


    drawText(
        24,
        rowY,
        numberString(target)
    )


    drawText(
        34,
        rowY,
        numberString(need)
    )


    drawText(
        44,
        rowY,
        sourceText
    )


    local statusColor =
        COLOR_YELLOW


    if currentStatus == "OK"
        or currentStatus == "EXPORTED" then

        statusColor =
            COLOR_GREEN

    elseif currentStatus == "CRAFTING" then

        statusColor =
            COLOR_BLUE

    elseif currentStatus == "NO SOURCE"
        or currentStatus == "NO CRAFT"
        or currentStatus == "EXPORT ERROR"
        or currentStatus == "EXPORT FAILED"
        or currentStatus == "CRAFT ERROR" then

        statusColor =
            COLOR_RED
    end


    drawText(
        math.max(
            60,
            width - 20
        ),
        rowY,
        currentStatus,
        statusColor
    )


    drawText(
        math.max(
            76,
            width - 6
        ),
        rowY,
        c.enabled
        and "ON"
        or "OFF",

        c.enabled
        and COLOR_GREEN
        or COLOR_GREY
    )
end


-- ============================================================
-- DRAW TABLE
-- ============================================================

local function drawTable()

    if fullRedraw then
        drawFrame()
    end


    local first =
        (page - 1)
        * ROWS
        + 1


    local last =
        math.min(
            #aspects,
            first + ROWS - 1
        )


    local currentRows = {}


    for index = first, last do

        local aspect =
            aspects[index]

        local rowIndex =
            index - first + 1


        currentRows[rowIndex] =
            getRowData(aspect)


        if
            lastRows[rowIndex]
            ~= currentRows[rowIndex]
            or fullRedraw
        then

            drawRow(
                aspect,
                rowIndex
            )
        end
    end


    for rowIndex = #currentRows + 1, ROWS do

        if lastRows[rowIndex] then

            local rowY =
                4 + rowIndex - 1

            gpu.setBackground(
                COLOR_BG
            )

            gpu.fill(
                1,
                rowY,
                width,
                1,
                " "
            )
        end
    end


    lastRows =
        currentRows
end


-- ============================================================
-- SOURCE EDITOR
-- ============================================================

local function readNumber(
    promptText,
    default
)

    term.clear()

    print(promptText)

    if default ~= nil then

        print(
            "Current: "
            .. tostring(default)
        )
    end

    io.write("> ")

    local raw =
        io.read()


    if not raw
        or raw == "" then

        return default
    end


    local value =
        tonumber(raw)


    if value == nil then

        return default
    end


    if value < 0 then
        value = 0
    end


    return math.floor(value)
end


local function scanSourceForAspect(
    aspect
)

    local stack =
        scanSourceChest()


    if not stack then

        status[aspect] =
            "NO SCAN ITEM"

        return false
    end


    local c =
        ensureConfig(aspect)


    c.sourceId =
        stack.name


    c.sourceDamage =
        stack.damage


    saveConfig()


    status[aspect] =
        "SOURCE SET"


    return true
end


local function editAspect(
    aspect
)

    local c =
        ensureConfig(aspect)


    while true do

        clearScreen()


        local current =
            safeNumber(
                currentEssentia[aspect],
                0
            )


        local available =
            safeNumber(
                sourceAmounts[aspect],
                0
            )


        drawText(
            2,
            2,
            "ESSENTIA CONFIGURATION",
            COLOR_BLUE
        )


        drawText(
            2,
            4,
            "Aspect: "
            .. prettyAspect(aspect)
        )


        drawText(
            2,
            6,
            "Current essentia: "
            .. numberString(current)
            .. " mB"
        )


        drawText(
            2,
            7,
            "Source in ME: "
            .. numberString(available)
        )


        drawText(
            2,
            9,
            "Source ID: "
            .. (
                c.sourceId ~= ""
                and c.sourceId
                or "NOT SET"
            )
        )


        drawText(
            2,
            10,
            "Damage: "
            .. tostring(
                c.sourceDamage
            )
        )


        drawText(
            2,
            11,
            "Essentia / item: "
            .. tostring(
                c.essentiaPerItem
            )
        )


        drawText(
            2,
            12,
            "Target: "
            .. tostring(
                c.target
            )
            .. " mB"
        )


        drawText(
            2,
            13,
            "Trigger: "
            .. tostring(
                c.trigger
            )
            .. " mB"
        )


        drawText(
            2,
            14,
            "Auto: "
            .. (
                c.enabled
                and "ON"
                or "OFF"
            ),
            c.enabled
            and COLOR_GREEN
            or COLOR_GREY
        )


        drawText(
            2,
            16,
            "Scanner chest: slot "
            .. SOURCE_SCAN_SLOT,
            COLOR_GREY
        )


        if scannerItem then

            drawText(
                2,
                17,
                "Scanner item: "
                .. scannerItem.name,
                COLOR_GREEN
            )

        else

            drawText(
                2,
                17,
                "Scanner item: empty",
                COLOR_RED
            )
        end


        drawButton(
            2,
            19,
            20,
            "SCAN SOURCE",
            false
        )


        drawButton(
            24,
            19,
            18,
            "SET TARGET",
            false
        )


        drawButton(
            44,
            19,
            18,
            "SET TRIGGER",
            false
        )


        drawButton(
            2,
            21,
            20,
            "SET YIELD",
            false
        )


        drawButton(
            24,
            21,
            18,
            "TOGGLE AUTO",
            c.enabled
        )


        drawButton(
            44,
            21,
            18,
            "BACK",
            false
        )


        local name, address, x, y =
            event.pull("touch")


        if y == 19
            and x >= 2
            and x <= 22 then

            scanSourceForAspect(
                aspect
            )


        elseif y == 19
            and x >= 24
            and x <= 42 then

            c.target =
                readNumber(
                    "Target essentia:",
                    c.target
                )

            saveConfig()


        elseif y == 19
            and x >= 44
            and x <= 62 then

            c.trigger =
                readNumber(
                    "Trigger deficit:",
                    c.trigger
                )

            saveConfig()


        elseif y == 21
            and x >= 2
            and x <= 22 then

            c.essentiaPerItem =
                readNumber(
                    "Essentia per source item:",
                    c.essentiaPerItem
                )

            if c.essentiaPerItem <= 0 then
                c.essentiaPerItem = 1
            end

            saveConfig()


        elseif y == 21
            and x >= 24
            and x <= 42 then

            c.enabled =
                not c.enabled

            saveConfig()


        elseif y == 21
            and x >= 44
            and x <= 62 then

            return
        end


        uiDirty = true
    end
end


-- ============================================================
-- INITIALIZATION
-- ============================================================

loadConfig()

scanSourceChest()

log(
    "[EssentiaManager] Starting..."
)

refreshNetwork()

drawFrame()

drawTable()

uiDirty = false


-- ============================================================
-- MAIN LOOP
-- ============================================================

while true do

    local now =
        computer.uptime()


    -- --------------------------------------------------------
    -- Refresh network
    -- --------------------------------------------------------

    if now - lastRefresh
        >= REFRESH_INTERVAL then

        local ok, errorMessage =
            pcall(
                refreshNetwork
            )


        if not ok then

            log(
                "[EssentiaManager] Refresh error: "
                .. tostring(errorMessage)
            )
        end


        lastRefresh =
            now

        uiDirty = true
    end


    -- --------------------------------------------------------
    -- Scanner chest
    -- --------------------------------------------------------

    if now - lastScannerScan
        >= SOURCE_SCAN_REFRESH then

        scanSourceChest()

        lastScannerScan =
            now
    end


    -- --------------------------------------------------------
    -- Update only changed GUI data.
    -- --------------------------------------------------------

    if uiDirty then

        drawTable()

        uiDirty = false
    end


    -- --------------------------------------------------------
    -- Input
    -- --------------------------------------------------------

    local name, address, a, b =
        event.pull(0.25)


    if name == "touch" then

        local x = a
        local y = b


        -- Previous page

        if y >= height - 2
            and x >= 1
            and x <= 10 then

            if page > 1 then

                page = page - 1

                lastRows = {}

                fullRedraw = true

                uiDirty = true
            end


        -- Next page

        elseif y >= height - 2
            and x >= 12
            and x <= 21 then

            local pageCount =
                math.max(
                    1,
                    math.ceil(
                        #aspects / ROWS
                    )
                )


            if page < pageCount then

                page = page + 1

                lastRows = {}

                fullRedraw = true

                uiDirty = true
            end


        -- Rescan

        elseif y >= height - 2
            and x >= 23
            and x <= 32 then

            lastRefresh = 0

            uiDirty = true


        -- Table

        elseif y >= 4
            and y < 4 + ROWS then

            local index =
                (page - 1)
                * ROWS
                + y - 3


            if aspects[index] then

                selected =
                    aspects[index]

                editAspect(
                    selected
                )

                selected = nil

                lastRows = {}

                fullRedraw = true

                uiDirty = true
            end
        end


    elseif name == "key_down" then

        local char = a


        if char == string.byte("q") then
            break
        end


        if char == string.byte("r") then

            lastRefresh = 0

            uiDirty = true
        end
    end
end


-- ============================================================
-- EXIT
-- ============================================================

clearScreen()

print(
    "Essentia Manager stopped."
)
