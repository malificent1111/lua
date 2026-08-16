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

-- Chest used for selecting source items.
-- Put the desired item into this chest, slot 1.

local SOURCE_SCAN_SIDE = sides.north
local SOURCE_SCAN_SLOT = 1


-- ME Interface output.
-- The target chest is below the ME Interface.

local EXPORT_DIRECTION = "DOWN"
local EXPORT_SLOT = 1


-- ============================================================
-- GENERAL CONFIG
-- ============================================================

local CONFIG_FILE = "/home/essentia_manager.cfg"

-- getFluidsInNetwork() returns values in 128-unit blocks
-- for the essentia representation used in this setup.

local ESSENTIA_SCALE = 128


local DEFAULT_TARGET = 2048
local DEFAULT_TRIGGER = 512
local DEFAULT_YIELD = 1


-- How often the whole ME network is refreshed.

local REFRESH_INTERVAL = 1.0


-- How often we are allowed to submit another crafting request
-- for the same source item.

local CRAFT_RECHECK_INTERVAL = 10


-- Safety limit for a single export operation.

local MAX_EXPORT_PER_RUN = 4096


-- ============================================================
-- SCREEN
-- ============================================================

local width, height = gpu.getResolution()

local ROWS =
    math.max(
        5,
        height - 8
    )


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

-- Whole ME item index.
-- key = "name|damage"
-- value = total amount

local allItemsIndex = {}

local sourceAmounts = {}

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

    return
        aspect:sub(1, 1):upper()
        .. aspect:sub(2)
end


local function numberString(value)

    value =
        math.floor(
            safeNumber(
                value,
                0
            )
        )


    local textValue =
        tostring(value)


    while true do

        local replaced, count =
            textValue:gsub(
                "^(-?%d+)(%d%d%d)",
                "%1 %2"
            )


        if count == 0 then
            break
        end


        textValue = replaced
    end


    return textValue
end


local function realEssentiaAmount(value)

    return math.floor(
        safeNumber(
            value,
            0
        )
        / ESSENTIA_SCALE
    )
end


-- ============================================================
-- ITEM IDENTIFIERS
-- ============================================================

-- Internal key used by the complete ME item index.

local function itemKey(name, damage)

    return
        tostring(name or "")
        .. "|"
        .. tostring(
            safeNumber(
                damage,
                0
            )
        )
end


-- ME search filter.

local function makeItemFilter(fingerprint)

    return {
        name = fingerprint.id,
        damage = fingerprint.dmg
    }
end


-- exportItem() fingerprint.

local function makeExportFingerprint(
    name,
    damage
)

    return {
        id = name,
        dmg = safeNumber(
            damage,
            0
        )
    }
end


-- ============================================================
-- CONFIGURATION
-- ============================================================

local function defaultConfig()

    return {
        enabled = false,

        target = DEFAULT_TARGET,

        trigger = DEFAULT_TRIGGER,

        sourceFingerprint = nil,

        essentiaPerItem = DEFAULT_YIELD
    }
end


local function ensureConfig(aspect)

    if not config[aspect] then
        config[aspect] =
            defaultConfig()
    end


    local current =
        config[aspect]


    if current.enabled == nil then
        current.enabled = false
    end


    if current.target == nil then
        current.target =
            DEFAULT_TARGET
    end


    if current.trigger == nil then
        current.trigger =
            DEFAULT_TRIGGER
    end


    if current.essentiaPerItem == nil then
        current.essentiaPerItem =
            DEFAULT_YIELD
    end


    -- --------------------------------------------------------
    -- Backward compatibility with the previous config format.
    -- --------------------------------------------------------

    if not current.sourceFingerprint then

        if current.sourceId
            and current.sourceId ~= "" then

            current.sourceFingerprint =
                makeExportFingerprint(
                    current.sourceId,
                    current.sourceDamage
                )
        end
    end


    return current
end


local function loadConfig()

    if not filesystem.exists(CONFIG_FILE) then

        config = {}

        return
    end


    local file =
        io.open(
            CONFIG_FILE,
            "r"
        )


    if not file then

        config = {}

        return
    end


    local data =
        file:read("*a")


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

    local file =
        io.open(
            CONFIG_FILE,
            "w"
        )


    if not file then
        return false
    end


    file:write(
        serialization.serialize(
            config
        )
    )


    file:close()

    return true
end


-- ============================================================
-- ESSENTIA DETECTION
-- ============================================================

local function parseEssentiaFluid(name)

    if type(name) ~= "string" then
        return nil
    end


    local lowerName =
        name:lower()


    if lowerName:sub(1, 7)
        ~= "gaseous" then

        return nil
    end


    if lowerName:sub(-8)
        ~= "essentia" then

        return nil
    end


    local aspect =
        lowerName:sub(
            8,
            -9
        )


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


    if not ok
        or type(rawFluids) ~= "table" then

        return result
    end


    for _, fluid in pairs(rawFluids) do

        local aspect =
            parseEssentiaFluid(
                fluid.name
            )


        if aspect then

            result[aspect] = {

                amount =
                    realEssentiaAmount(
                        fluid.amount
                    ),

                rawAmount =
                    safeNumber(
                        fluid.amount,
                        0
                    ),

                name =
                    fluid.name,

                label =
                    fluid.label
                    or prettyAspect(
                        aspect
                    )
            }
        end
    end


    return result
end


-- ============================================================
-- COMPLETE ME ITEM SCAN
-- ============================================================

local function scanAllItems()

    local result = {}


    local ok, rawItems =
        pcall(
            me.getItemsInNetwork,
            {}
        )


    if not ok
        or type(rawItems) ~= "table" then

        return result
    end


    for _, item in pairs(rawItems) do

        if item.name then

            local damage =
                safeNumber(
                    item.damage,
                    0
                )


            local key =
                itemKey(
                    item.name,
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


    if not ok
        or type(stack) ~= "table"
        or not stack.name then

        scannerItem = nil

        return nil
    end


    scannerItem = {

        name =
            stack.name,

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
-- SOURCE FINGERPRINT
-- ============================================================

local function getSourceFingerprint(aspect)

    local current =
        ensureConfig(aspect)


    if not current.sourceFingerprint then
        return nil
    end


    if type(
        current.sourceFingerprint
    ) ~= "table" then

        return nil
    end


    if not current.sourceFingerprint.id
        or current.sourceFingerprint.id == "" then

        return nil
    end


    return {

        id =
            current.sourceFingerprint.id,

        dmg =
            safeNumber(
                current.sourceFingerprint.dmg,
                0
            )
    }
end


-- ============================================================
-- SOURCE AMOUNT FROM LOCAL INDEX
-- ============================================================

local function getSourceAmount(aspect)

    local fingerprint =
        getSourceFingerprint(
            aspect
        )


    if not fingerprint then
        return 0
    end


    local key =
        itemKey(
            fingerprint.id,
            fingerprint.dmg
        )


    return safeNumber(
        allItemsIndex[key],
        0
    )
end


-- ============================================================
-- FIND SOURCE CRAFTABLE
-- ============================================================

local function findSourceCraftable(
    aspect
)

    local fingerprint =
        getSourceFingerprint(
            aspect
        )


    if not fingerprint then
        return nil
    end


    local ok, craftables =
        pcall(
            me.getCraftables,
            makeItemFilter(
                fingerprint
            )
        )


    if not ok
        or type(craftables) ~= "table" then

        return nil
    end


    for _, craft in pairs(craftables) do

        local okStack, stack =
            pcall(
                function()
                    return craft.getItemStack()
                end
            )


        if okStack
            and type(stack) == "table" then

            local stackDamage =
                safeNumber(
                    stack.damage,
                    0
                )


            if stack.name
                == fingerprint.id
                and stackDamage
                    == fingerprint.dmg then

                return craft
            end
        end
    end


    return nil
end


-- ============================================================
-- REQUEST SOURCE CRAFT
-- ============================================================

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

        status[aspect] =
            "CRAFTING SOURCE"

        return false
    end


    local craft =
        findSourceCraftable(
            aspect
        )


    if not craft then

        status[aspect] =
            "NO CRAFT"

        return false
    end


    amount =
        math.max(
            1,
            math.floor(
                amount
            )
        )


    local ok, request =
        pcall(
            function()

                return craft.request(
                    amount,
                    true
                )

            end
        )


    craftAttemptTime[aspect] =
        now


    if not ok then

        status[aspect] =
            "CRAFT ERROR"

        log(
            "[EssentiaManager] Craft request error for "
            .. prettyAspect(aspect)
            .. ": "
            .. tostring(request)
        )

        return false
    end


    if not request then

        status[aspect] =
            "CRAFT ERROR"

        return false
    end


    status[aspect] =
        "CRAFTING SOURCE"


    return true
end


-- ============================================================
-- EXPORT SOURCE
-- ============================================================

local function exportSource(
    aspect,
    amount
)

    local fingerprint =
        getSourceFingerprint(
            aspect
        )


    if not fingerprint then

        status[aspect] =
            "NO SOURCE"

        return 0
    end


    amount =
        math.floor(
            safeNumber(
                amount,
                0
            )
        )


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

                fingerprint,

                EXPORT_DIRECTION,

                remaining,

                EXPORT_SLOT
            )


        if not ok then

            status[aspect] =
                "EXPORT ERROR"


            log(
                "[EssentiaManager] Export error for "
                .. prettyAspect(aspect)
                .. ": "
                .. tostring(result)
            )


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
            "FEEDING"

    else

        status[aspect] =
            "EXPORT FAILED"
    end


    return movedTotal
end


-- ============================================================
-- MAINTAIN ONE ASPECT
-- ============================================================

local function maintainAspect(aspect)

    local current =
        ensureConfig(aspect)


    if not current.enabled then

        status[aspect] =
            "OFF"

        return
    end


    local fingerprint =
        getSourceFingerprint(
            aspect
        )


    if not fingerprint then

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


    if currentEss >= target then

        status[aspect] =
            "OK"

        return
    end


    local neededEssentia =
        target - currentEss


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
            neededEssentia
            / yield
        )


    -- --------------------------------------------------------
    -- First priority:
    -- use source items already in ME.
    -- --------------------------------------------------------

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


    -- --------------------------------------------------------
    -- Source is absent.
    --
    -- Request a source craft.
    -- We do not use CraftingStatus to determine success.
    -- The next network scan will tell us whether the item
    -- actually appeared in ME.
    -- --------------------------------------------------------

    requestSourceCraft(
        aspect,
        requiredItems
    )
end


-- ============================================================
-- NETWORK REFRESH
-- ============================================================

local function refreshNetwork()

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


    table.sort(
        aspects
    )


    for _, aspect in ipairs(aspects) do

        sourceAmounts[aspect] =
            getSourceAmount(
                aspect
            )

        maintainAspect(
            aspect
        )
    end


    saveConfig()


    uiDirty = true
end


-- ============================================================
-- SCREEN
-- ============================================================

local function clearScreen()

    gpu.setBackground(
        COLOR_BG
    )

    gpu.setForeground(
        COLOR_WHITE
    )


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


    local maximum =
        width - x + 1


    if #value > maximum then

        value =
            value:sub(
                1,
                maximum
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
    widthValue,
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
        widthValue,
        1,
        " "
    )


    local textX =
        x
        + math.floor(
            (widthValue - #label) / 2
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
        "ESSENTIA MANAGER"
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
-- ROW
-- ============================================================

local function getRowSignature(aspect)

    local current =
        ensureConfig(
            aspect
        )


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


    local need =
        math.max(
            0,
            target - currentEss
        )


    local fingerprint =
        getSourceFingerprint(
            aspect
        )


    local sourceText =
        "-"


    if fingerprint then

        sourceText =
            fingerprint.id


        if #sourceText > 18 then

            sourceText =
                sourceText:sub(
                    1,
                    18
                )
        end
    end


    return table.concat(
        {
            prettyAspect(aspect),

            tostring(currentEss),

            tostring(target),

            tostring(need),

            sourceText,

            status[aspect] or "-",

            current.enabled
            and "ON"
            or "OFF"
        },
        "|"
    )
end


local function drawRow(
    aspect,
    rowIndex
)

    local rowY =
        4 + rowIndex - 1


    if selected == aspect then

        gpu.setBackground(
            COLOR_SELECTED
        )

    else

        gpu.setBackground(
            COLOR_BG
        )
    end


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


    local current =
        ensureConfig(
            aspect
        )


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


    local need =
        math.max(
            0,
            target - currentEss
        )


    local fingerprint =
        getSourceFingerprint(
            aspect
        )


    local sourceText =
        "-"


    if fingerprint then

        sourceText =
            fingerprint.id


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
        numberString(
            currentEss
        )
    )


    drawText(
        24,
        rowY,
        numberString(
            target
        )
    )


    drawText(
        34,
        rowY,
        numberString(
            need
        )
    )


    drawText(
        44,
        rowY,
        sourceText
    )


    local statusColor =
        COLOR_YELLOW


    if currentStatus == "OK"
        or currentStatus == "FEEDING" then

        statusColor =
            COLOR_GREEN

    elseif currentStatus
        == "CRAFTING SOURCE" then

        statusColor =
            COLOR_BLUE

    elseif currentStatus
        == "NO SOURCE"
        or currentStatus
        == "NO CRAFT"
        or currentStatus
        == "CRAFT ERROR"
        or currentStatus
        == "EXPORT ERROR"
        or currentStatus
        == "EXPORT FAILED" then

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
        current.enabled
        and "ON"
        or "OFF",

        current.enabled
        and COLOR_GREEN
        or COLOR_GREY
    )
end


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
            getRowSignature(
                aspect
            )


        if lastRows[rowIndex]
            ~= currentRows[rowIndex]
            or fullRedraw then

            drawRow(
                aspect,
                rowIndex
            )
        end
    end


    for rowIndex =
        #currentRows + 1,
        ROWS do

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
-- NUMBER INPUT
-- ============================================================

local function readNumber(
    promptText,
    default
)

    term.clear()


    print(
        promptText
    )


    if default ~= nil then

        print(
            "Current: "
            .. tostring(
                default
            )
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


    return math.floor(
        value
    )
end


-- ============================================================
-- SOURCE SCANNING
-- ============================================================

local function assignScannerSource(
    aspect
)

    local stack =
        scanSourceChest()


    if not stack then

        status[aspect] =
            "NO SCAN ITEM"

        return false
    end


    local current =
        ensureConfig(
            aspect
        )


    current.sourceFingerprint =
        makeExportFingerprint(
            stack.name,
            stack.damage
        )


    saveConfig()


    status[aspect] =
        "SOURCE SET"


    return true
end


-- ============================================================
-- ASPECT EDITOR
-- ============================================================

local function editAspect(
    aspect
)

    local current =
        ensureConfig(
            aspect
        )


    while true do

        clearScreen()


        local currentEss =
            safeNumber(
                currentEssentia[aspect],
                0
            )


        local available =
            safeNumber(
                sourceAmounts[aspect],
                0
            )


        local fingerprint =
            getSourceFingerprint(
                aspect
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
            .. prettyAspect(
                aspect
            )
        )


        drawText(
            2,
            6,
            "Current essentia: "
            .. numberString(
                currentEss
            )
            .. " mB"
        )


        drawText(
            2,
            7,
            "Source in ME: "
            .. numberString(
                available
            )
        )


        drawText(
            2,
            9,
            "Source:"
        )


        if fingerprint then

            drawText(
                10,
                9,
                fingerprint.id,
                COLOR_GREEN
            )


            drawText(
                10,
                10,
                "damage = "
                .. tostring(
                    fingerprint.dmg
                ),
                COLOR_GREY
            )

        else

            drawText(
                10,
                9,
                "NOT SET",
                COLOR_RED
            )
        end


        drawText(
            2,
            12,
            "Essentia / item: "
            .. tostring(
                current.essentiaPerItem
            )
        )


        drawText(
            2,
            13,
            "Target: "
            .. tostring(
                current.target
            )
            .. " mB"
        )


        drawText(
            2,
            14,
            "Trigger: "
            .. tostring(
                current.trigger
            )
            .. " mB"
        )


        drawText(
            2,
            15,
            "Auto refill: "
            .. (
                current.enabled
                and "ON"
                or "OFF"
            ),
            current.enabled
            and COLOR_GREEN
            or COLOR_GREY
        )


        drawText(
            2,
            17,
            "Scanner slot: "
            .. tostring(
                SOURCE_SCAN_SLOT
            ),
            COLOR_GREY
        )


        if scannerItem then

            drawText(
                2,
                18,
                "Scanner: "
                .. scannerItem.name
                .. " : "
                .. tostring(
                    scannerItem.damage
                ),
                COLOR_GREEN
            )

        else

            drawText(
                2,
                18,
                "Scanner: EMPTY",
                COLOR_RED
            )
        end


        drawButton(
            2,
            20,
            20,
            "SCAN SOURCE",
            false
        )


        drawButton(
            24,
            20,
            18,
            "SET TARGET",
            false
        )


        drawButton(
            44,
            20,
            18,
            "SET TRIGGER",
            false
        )


        drawButton(
            2,
            22,
            20,
            "SET YIELD",
            false
        )


        drawButton(
            24,
            22,
            18,
            "TOGGLE AUTO",
            current.enabled
        )


        drawButton(
            44,
            22,
            18,
            "BACK",
            false
        )


        local eventName,
              eventAddress,
              x,
              y =
            event.pull(
                "touch"
            )


        if y == 20
            and x >= 2
            and x <= 22 then

            assignScannerSource(
                aspect
            )


        elseif y == 20
            and x >= 24
            and x <= 42 then

            current.target =
                readNumber(
                    "Target essentia:",
                    current.target
                )

            saveConfig()


        elseif y == 20
            and x >= 44
            and x <= 62 then

            current.trigger =
                readNumber(
                    "Trigger deficit:",
                    current.trigger
                )

            saveConfig()


        elseif y == 22
            and x >= 2
            and x <= 22 then

            current.essentiaPerItem =
                readNumber(
                    "Essentia per source item:",
                    current.essentiaPerItem
                )


            if current.essentiaPerItem <= 0 then

                current.essentiaPerItem =
                    1
            end


            saveConfig()


        elseif y == 22
            and x >= 24
            and x <= 42 then

            current.enabled =
                not current.enabled


            saveConfig()


        elseif y == 22
            and x >= 44
            and x <= 62 then

            return
        end


        uiDirty = true
    end
end


-- ============================================================
-- START
-- ============================================================

loadConfig()

scanSourceChest()

log(
    "[EssentiaManager] Starting..."
)


local okStart, startError =
    pcall(
        refreshNetwork
    )


if not okStart then

    log(
        "[EssentiaManager] Initial refresh error: "
        .. tostring(startError)
    )
end


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
    -- Whole-network refresh.
    -- Two main ME queries:
    --
    -- getFluidsInNetwork()
    -- getItemsInNetwork({})
    --
    -- Individual craftable query only happens when a source
    -- item is actually missing and needs to be crafted.
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
                .. tostring(
                    errorMessage
                )
            )
        end


        lastRefresh =
            now


        uiDirty = true
    end


    -- --------------------------------------------------------
    -- Scanner chest.
    -- --------------------------------------------------------

    if now - lastScannerScan
        >= 1.0 then

        scanSourceChest()

        lastScannerScan =
            now
    end


    -- --------------------------------------------------------
    -- Draw only when needed.
    -- --------------------------------------------------------

    if uiDirty then

        drawTable()

        uiDirty = false
    end


    -- --------------------------------------------------------
    -- Input
    -- --------------------------------------------------------

    local name,
          address,
          a,
          b =
        event.pull(
            0.25
        )


    if name == "touch" then

        local x = a
        local y = b


        -- Previous page

        if y >= height - 2
            and x >= 1
            and x <= 10 then

            if page > 1 then

                page =
                    page - 1

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
                        #aspects
                        / ROWS
                    )
                )


            if page < pageCount then

                page =
                    page + 1

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


        -- Table row

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
