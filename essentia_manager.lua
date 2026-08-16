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

-- Put the source item into this chest, slot 1.
-- Inventory Controller must be able to see this side.

local SOURCE_SCAN_SIDE = sides.north
local SOURCE_SCAN_SLOT = 1


-- ME Interface output direction.
-- No destination slot is specified:
-- the interface may use any available slot.

local EXPORT_DIRECTION = "DOWN"


-- ============================================================
-- GENERAL CONFIGURATION
-- ============================================================

local CONFIG_FILE = "/home/essentia_manager.cfg"

-- In this setup one real essentia corresponds to 128 units
-- returned by getFluidsInNetwork().

local ESSENTIA_SCALE = 128


local DEFAULT_TARGET = 2048
local DEFAULT_TRIGGER = 512
local DEFAULT_YIELD = 1


-- Complete network scan interval.

local REFRESH_INTERVAL = 1.0


-- Minimum time before another request for the same source.

local CRAFT_RECHECK_INTERVAL = 10


-- Maximum amount exported in one logical operation.

local MAX_EXPORT_PER_RUN = 4096


-- ============================================================
-- UI CONFIGURATION
-- ============================================================

local width, height = gpu.getResolution()

local CARD_COLUMNS = 4
local CARD_HEIGHT = 4
local CARD_GAP = 1

local HEADER_HEIGHT = 4
local FOOTER_HEIGHT = 2

local availableCardHeight =
    height
    - HEADER_HEIGHT
    - FOOTER_HEIGHT

local CARD_ROWS =
    math.max(
        2,
        math.floor(
            availableCardHeight
            / (CARD_HEIGHT + 1)
        )
    )

local CARDS_PER_PAGE =
    CARD_COLUMNS * CARD_ROWS


-- ============================================================
-- COLORS
-- ============================================================

local COLOR_BG = 0x191919
local COLOR_PANEL = 0x252525
local COLOR_PANEL_2 = 0x303030
local COLOR_SELECTED = 0x344A63

local COLOR_WHITE = 0xFFFFFF
local COLOR_GREY = 0x888888

local COLOR_GREEN = 0x48C774
local COLOR_YELLOW = 0xE0C04C
local COLOR_BLUE = 0x4EA5D9
local COLOR_ORANGE = 0xE08A38
local COLOR_RED = 0xD94B4B
local COLOR_PURPLE = 0xA66DD4


-- ============================================================
-- STATE
-- ============================================================

local config = {}

local fluids = {}
local currentEssentia = {}

local allItemsIndex = {}
local sourceAmounts = {}

local craftAttemptTime = {}

local status = {}

local aspects = {}
local filteredAspects = {}

local scannerItem = nil

local selected = nil

local filterMode = "ALL"

local page = 1

local lastRefresh = 0
local lastScannerScan = 0

local uiDirty = true
local fullRedraw = true

local lastCardSignatures = {}


-- ============================================================
-- BASIC HELPERS
-- ============================================================

local function safeNumber(value, fallback)
    local number = tonumber(value)

    if number == nil then
        return fallback
    end

    return number
end


local function numberString(value)
    value = math.floor(
        safeNumber(value, 0)
    )

    local text = tostring(value)

    while true do
        local replaced, count =
            text:gsub(
                "^(-?%d+)(%d%d%d)",
                "%1 %2"
            )

        if count == 0 then
            break
        end

        text = replaced
    end

    return text
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


local function realEssentiaAmount(value)
    return math.floor(
        safeNumber(value, 0)
        / ESSENTIA_SCALE
    )
end


local function itemKey(name, damage)
    return
        tostring(name or "")
        .. "|"
        .. tostring(
            safeNumber(damage, 0)
        )
end


-- ============================================================
-- FINGERPRINT
-- ============================================================

local function makeExportFingerprint(name, damage)
    return {
        id = name,
        dmg = safeNumber(damage, 0)
    }
end


local function makeItemFilter(fingerprint)
    return {
        name = fingerprint.id,
        damage = fingerprint.dmg
    }
end


local function getSourceFingerprint(aspect)

    local current =
        config[aspect]

    if not current then
        return nil
    end

    if not current.sourceFingerprint then
        return nil
    end

    if type(current.sourceFingerprint) ~= "table" then
        return nil
    end

    if not current.sourceFingerprint.id then
        return nil
    end

    if current.sourceFingerprint.id == "" then
        return nil
    end

    return {
        id = current.sourceFingerprint.id,
        dmg = safeNumber(
            current.sourceFingerprint.dmg,
            0
        )
    }
end


-- ============================================================
-- CONFIG
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
        current.target = DEFAULT_TARGET
    end

    if current.trigger == nil then
        current.trigger = DEFAULT_TRIGGER
    end

    if current.essentiaPerItem == nil then
        current.essentiaPerItem =
            DEFAULT_YIELD
    end

    -- Convert old configuration format if necessary.

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
        serialization.serialize(config)
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
                    or prettyAspect(aspect)
            }
        end
    end

    return result
end


-- ============================================================
-- COMPLETE ITEM INDEX
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
            or stack.name
    }

    return scannerItem
end


-- ============================================================
-- SOURCE AMOUNT
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

local function findSourceCraftable(aspect)

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
-- SOURCE CRAFT REQUEST
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
            math.floor(amount)
        )

    local requestAmount =
        math.min(
            amount,
            8
        )

    local ok, request =
        pcall(
            function()

                return craft.request(
                    requestAmount,
                    true
                )

            end
        )

    craftAttemptTime[aspect] =
        now

    if not ok
        or not request then

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

        -- No destination slot:
        -- interface chooses a free slot.

        local ok, result =
            pcall(
                interface.exportItem,
                fingerprint,
                EXPORT_DIRECTION,
                remaining
            )

        if not ok then

            status[aspect] =
                "EXPORT ERROR"

            return movedTotal
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
        status[aspect] = "FEEDING"
    else
        status[aspect] = "EXPORT FAILED"
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

    -- Source already available.

    local available =
        getSourceAmount(
            aspect
        )

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

    -- Source missing:
    -- request a small craft batch.

    requestSourceCraft(
        aspect,
        requiredItems
    )
end


-- ============================================================
-- ASPECT FILTER HELPERS
-- ============================================================

local function isLow(aspect)

    local current =
        safeNumber(
            currentEssentia[aspect],
            0
        )

    local target =
        safeNumber(
            config[aspect]
            and config[aspect].target
            or 0,
            0
        )

    return current < target
end


local function isActive(aspect)

    local value =
        status[aspect]

    return
        value == "FEEDING"
        or value == "CRAFTING SOURCE"
end


local function isError(aspect)

    local value =
        status[aspect]

    return
        value == "NO SOURCE"
        or value == "NO CRAFT"
        or value == "CRAFT ERROR"
        or value == "EXPORT ERROR"
        or value == "EXPORT FAILED"
        or value == "BAD YIELD"
end


local function isNew(aspect)

    local fingerprint =
        getSourceFingerprint(
            aspect
        )

    return fingerprint == nil
end


-- ============================================================
-- REBUILD FILTER
-- ============================================================

local function rebuildFilteredAspects()

    filteredAspects = {}

    for _, aspect in ipairs(aspects) do

        local include = false

        if filterMode == "ALL" then

            include = true

        elseif filterMode == "LOW" then

            include =
                isLow(aspect)

        elseif filterMode == "ACTIVE" then

            include =
                isActive(aspect)

        elseif filterMode == "ERRORS" then

            include =
                isError(aspect)

        elseif filterMode == "NEW" then

            include =
                isNew(aspect)
        end

        if include then
            table.insert(
                filteredAspects,
                aspect
            )
        end
    end

    local pageCount =
        math.max(
            1,
            math.ceil(
                #filteredAspects
                / CARDS_PER_PAGE
            )
        )

    if page > pageCount then
        page = pageCount
    end
end


-- ============================================================
-- COUNTERS
-- ============================================================

local function getCounters()

    local counters = {
        total = #aspects,
        configured = 0,
        active = 0,
        low = 0,
        errors = 0,
        new = 0
    }

    for _, aspect in ipairs(aspects) do

        if not isNew(aspect) then
            counters.configured =
                counters.configured + 1
        else
            counters.new =
                counters.new + 1
        end

        if isActive(aspect) then
            counters.active =
                counters.active + 1
        end

        if isLow(aspect) then
            counters.low =
                counters.low + 1
        end

        if isError(aspect) then
            counters.errors =
                counters.errors + 1
        end
    end

    return counters
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

    rebuildFilteredAspects()

    saveConfig()

    uiDirty = true
end


-- ============================================================
-- DRAW HELPERS
-- ============================================================

local function setBackground(color)
    gpu.setBackground(color)
end


local function setForeground(color)
    gpu.setForeground(color)
end


local function fill(
    x,
    y,
    w,
    h,
    color
)

    gpu.setBackground(color)

    gpu.fill(
        x,
        y,
        w,
        h,
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

    setForeground(
        color
        or COLOR_WHITE
    )

    gpu.set(
        x,
        y,
        value
    )
end


local function drawCentered(
    x,
    y,
    w,
    value,
    color
)

    value =
        tostring(
            value or ""
        )

    if #value > w - 2 then

        value =
            value:sub(
                1,
                w - 2
            )
    end

    local startX =
        x
        + math.floor(
            (w - #value) / 2
        )

    drawText(
        startX,
        y,
        value,
        color
    )
end


local function drawButton(
    x,
    y,
    w,
    h,
    label,
    active,
    color
)

    local background =
        active
        and (color or COLOR_SELECTED)
        or COLOR_PANEL_2

    fill(
        x,
        y,
        w,
        h,
        background
    )

    drawCentered(
        x,
        y,
        w,
        label,
        COLOR_WHITE
    )
end


-- ============================================================
-- STATUS VISUALS
-- ============================================================

local function getStatusColor(value)

    if value == "OK" then
        return COLOR_GREEN
    end

    if value == "FEEDING" then
        return COLOR_ORANGE
    end

    if value == "CRAFTING SOURCE" then
        return COLOR_BLUE
    end

    if value == "OFF" then
        return COLOR_GREY
    end

    if value == "NO SOURCE"
        or value == "NO CRAFT"
        or value == "CRAFT ERROR"
        or value == "EXPORT ERROR"
        or value == "EXPORT FAILED"
        or value == "BAD YIELD" then

        return COLOR_RED
    end

    if value == "SOURCE SET" then
        return COLOR_GREEN
    end

    return COLOR_YELLOW
end


local function getStatusLabel(aspect)

    if isNew(aspect) then
        return "NEW"
    end

    return status[aspect] or "-"
end


-- ============================================================
-- FULL SCREEN
-- ============================================================

local function clearScreen()

    setBackground(
        COLOR_BG
    )

    setForeground(
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


-- ============================================================
-- HEADER
-- ============================================================

local function drawHeader()

    fill(
        1,
        1,
        width,
        2,
        COLOR_PANEL_2
    )

    drawText(
        2,
        1,
        "ESSENTIA MANAGER",
        COLOR_WHITE
    )

    local counters =
        getCounters()

    drawText(
        2,
        2,
        tostring(counters.total)
        .. " aspects",
        COLOR_GREY
    )

    drawText(
        17,
        2,
        tostring(counters.configured)
        .. " configured",
        COLOR_GREY
    )

    drawText(
        36,
        2,
        tostring(counters.active)
        .. " active",
        COLOR_ORANGE
    )

    drawText(
        49,
        2,
        tostring(counters.low)
        .. " low",
        COLOR_YELLOW
    )

    drawText(
        59,
        2,
        tostring(counters.errors)
        .. " errors",
        COLOR_RED
    )

    drawText(
        math.max(
            70,
            width - 10
        ),
        1,
        "AUTO",
        COLOR_GREY
    )
end


-- ============================================================
-- FILTER BAR
-- ============================================================

local function drawFilters()

    local counters =
        getCounters()

    local filterY = 3

    local buttonWidth = 11

    drawButton(
        1,
        filterY,
        buttonWidth,
        1,
        "ALL "
        .. counters.total,
        filterMode == "ALL",
        COLOR_SELECTED
    )

    drawButton(
        13,
        filterY,
        buttonWidth,
        1,
        "LOW "
        .. counters.low,
        filterMode == "LOW",
        COLOR_YELLOW
    )

    drawButton(
        25,
        filterY,
        buttonWidth,
        1,
        "ACTIVE "
        .. counters.active,
        filterMode == "ACTIVE",
        COLOR_ORANGE
    )

    drawButton(
        37,
        filterY,
        buttonWidth,
        1,
        "ERROR "
        .. counters.errors,
        filterMode == "ERRORS",
        COLOR_RED
    )

    drawButton(
        49,
        filterY,
        buttonWidth,
        1,
        "NEW "
        .. counters.new,
        filterMode == "NEW",
        COLOR_PURPLE
    )

    drawText(
        width - 13,
        filterY,
        "R=refresh",
        COLOR_GREY
    )
end


-- ============================================================
-- CARD GEOMETRY
-- ============================================================

local function getCardGeometry(
    cardIndex
)

    local column =
        (cardIndex - 1)
        % CARD_COLUMNS

    local row =
        math.floor(
            (cardIndex - 1)
            / CARD_COLUMNS
        )

    local totalGap =
        (CARD_COLUMNS - 1)
        * CARD_GAP

    local cardWidth =
        math.floor(
            (width - totalGap)
            / CARD_COLUMNS
        )

    local x =
        column
        * (cardWidth + CARD_GAP)
        + 1

    local y =
        HEADER_HEIGHT
        + 2
        + row
        * (CARD_HEIGHT + 1)

    return x, y, cardWidth
end


-- ============================================================
-- PROGRESS BAR
-- ============================================================

local function drawProgressBar(
    x,
    y,
    w,
    current,
    target,
    color
)

    local ratio = 0

    if target > 0 then

        ratio =
            current / target

        if ratio > 1 then
            ratio = 1
        end

        if ratio < 0 then
            ratio = 0
        end
    end

    local usableWidth =
        math.max(
            4,
            w - 2
        )

    local filled =
        math.floor(
            usableWidth
            * ratio
        )

    setBackground(
        COLOR_PANEL_2
    )

    gpu.fill(
        x,
        y,
        usableWidth,
        1,
        " "
    )

    if filled > 0 then

        setBackground(
            color
        )

        gpu.fill(
            x,
            y,
            filled,
            1,
            " "
        )
    end

    setBackground(
        COLOR_BG
    )
end


-- ============================================================
-- CARD SIGNATURE
-- ============================================================

local function getCardSignature(
    aspect
)

    local current =
        safeNumber(
            currentEssentia[aspect],
            0
        )

    local target =
        safeNumber(
            config[aspect]
            and config[aspect].target
            or 0,
            0
        )

    local source =
        getSourceFingerprint(
            aspect
        )

    return table.concat(
        {
            tostring(current),
            tostring(target),
            tostring(
                status[aspect] or ""
            ),
            tostring(
                source
                and source.id
                or ""
            ),
            tostring(
                source
                and source.dmg
                or ""
            ),
            tostring(
                config[aspect]
                and config[aspect].enabled
                or false
            )
        },
        "|"
    )
end


-- ============================================================
-- DRAW CARD
-- ============================================================

local function drawCard(
    aspect,
    cardIndex
)

    local x, y, cardWidth =
        getCardGeometry(
            cardIndex
        )


    local current =
        safeNumber(
            currentEssentia[aspect],
            0
        )

    local target =
        safeNumber(
            config[aspect]
            and config[aspect].target
            or 0,
            0
        )

    local cardStatus =
        getStatusLabel(
            aspect
        )

    local statusColor =
        getStatusColor(
            status[aspect]
        )


    if isNew(aspect) then
        statusColor = COLOR_PURPLE
    end


    if selected == aspect then

        fill(
            x,
            y,
            cardWidth,
            CARD_HEIGHT,
            COLOR_SELECTED
        )

    else

        fill(
            x,
            y,
            cardWidth,
            CARD_HEIGHT,
            COLOR_PANEL
        )
    end


    -- Top line

    drawText(
        x + 1,
        y,
        prettyAspect(aspect),
        COLOR_WHITE
    )


    local autoText =
        config[aspect].enabled
        and "ON"
        or "OFF"


    drawText(
        x + cardWidth - 5,
        y,
        autoText,
        config[aspect].enabled
        and COLOR_GREEN
        or COLOR_GREY
    )


    -- Current / Target

    local valueText =
        numberString(current)
        .. "/"
        .. numberString(target)

    drawCentered(
        x,
        y + 1,
        cardWidth,
        valueText,
        COLOR_WHITE
    )


    -- Progress

    drawProgressBar(
        x + 1,
        y + 2,
        cardWidth - 2,
        current,
        target,
        statusColor
    )


    -- Status

    drawCentered(
        x,
        y + 3,
        cardWidth,
        cardStatus,
        statusColor
    )
end


-- ============================================================
-- DASHBOARD
-- ============================================================

local function drawDashboard()

    if fullRedraw then

        clearScreen()

        drawHeader()

        drawFilters()

        lastCardSignatures = {}

        fullRedraw = false
    else

        drawHeader()

        drawFilters()
    end


    local first =
        (page - 1)
        * CARDS_PER_PAGE
        + 1

    local last =
        math.min(
            #filteredAspects,
            first + CARDS_PER_PAGE - 1
        )


    local newSignatures = {}


    for index = first, last do

        local cardIndex =
            index - first + 1

        local aspect =
            filteredAspects[index]

        local signature =
            getCardSignature(
                aspect
            )

        newSignatures[cardIndex] =
            signature


        if lastCardSignatures[cardIndex]
            ~= signature
            or fullRedraw then

            drawCard(
                aspect,
                cardIndex
            )
        end
    end


    for index = last - first + 2,
        CARDS_PER_PAGE do

        if lastCardSignatures[index] then

            local x, y, cardWidth =
                getCardGeometry(
                    index
                )

            fill(
                x,
                y,
                cardWidth,
                CARD_HEIGHT,
                COLOR_BG
            )
        end
    end


    lastCardSignatures =
        newSignatures


    -- Footer

    local pageCount =
        math.max(
            1,
            math.ceil(
                #filteredAspects
                / CARDS_PER_PAGE
            )
        )

    fill(
        1,
        height - 1,
        width,
        2,
        COLOR_PANEL_2
    )


    drawText(
        2,
        height - 1,
        "Page "
        .. page
        .. "/"
        .. pageCount,
        COLOR_GREY
    )


    drawText(
        15,
        height - 1,
        "Click card: settings",
        COLOR_GREY
    )


    if page > 1 then

        drawButton(
            width - 22,
            height - 1,
            9,
            1,
            "< PREV",
            true
        )
    end


    if page < pageCount then

        drawButton(
            width - 12,
            height - 1,
            10,
            1,
            "NEXT >",
            true
        )
    end


    drawText(
        2,
        height,
        "Q quit",
        COLOR_GREY
    )
end


-- ============================================================
-- EDITOR NUMBER INPUT
-- ============================================================

local function readNumber(
    promptText,
    default
)

    term.clear()

    print(
        promptText
    )

    print(
        "Current: "
        .. tostring(default)
    )

    io.write("> ")

    local raw =
        io.read()

    if not raw
        or raw == "" then

        return default
    end

    local value =
        tonumber(raw)

    if not value then
        return default
    end

    if value < 0 then
        value = 0
    end

    return math.floor(value)
end


-- ============================================================
-- EDITOR
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

        local currentStatus =
            getStatusLabel(
                aspect
            )


        drawText(
            2,
            2,
            "ESSENTIA SETTINGS",
            COLOR_BLUE
        )


        drawText(
            2,
            4,
            prettyAspect(
                aspect
            ),
            COLOR_WHITE
        )


        drawText(
            2,
            6,
            "Current:",
            COLOR_GREY
        )

        drawText(
            18,
            6,
            numberString(
                currentEss
            )
            .. " mB"
        )


        drawText(
            2,
            7,
            "Target:",
            COLOR_GREY
        )

        drawText(
            18,
            7,
            numberString(
                current.target
            )
            .. " mB"
        )


        drawText(
            2,
            8,
            "Need:",
            COLOR_GREY
        )

        drawText(
            18,
            8,
            numberString(
                math.max(
                    0,
                    current.target
                    - currentEss
                )
            )
            .. " mB"
        )


        drawText(
            2,
            10,
            "Source:",
            COLOR_GREY
        )


        if fingerprint then

            drawText(
                18,
                10,
                fingerprint.id,
                COLOR_GREEN
            )

            drawText(
                18,
                11,
                "damage "
                .. tostring(
                    fingerprint.dmg
                ),
                COLOR_GREY
            )

        else

            drawText(
                18,
                10,
                "NOT CONFIGURED",
                COLOR_PURPLE
            )
        end


        drawText(
            2,
            13,
            "Source in ME:",
            COLOR_GREY
        )

        drawText(
            18,
            13,
            numberString(
                available
            )
        )


        drawText(
            2,
            14,
            "Essentia / item:",
            COLOR_GREY
        )

        drawText(
            18,
            14,
            tostring(
                current.essentiaPerItem
            )
            .. " mB"
        )


        drawText(
            2,
            15,
            "Trigger:",
            COLOR_GREY
        )

        drawText(
            18,
            15,
            tostring(
                current.trigger
            )
            .. " mB"
        )


        drawText(
            2,
            16,
            "Status:",
            COLOR_GREY
        )

        drawText(
            18,
            16,
            currentStatus,
            getStatusColor(
                status[aspect]
            )
        )


        drawText(
            2,
            18,
            "Scanner:",
            COLOR_GREY
        )


        if scannerItem then

            drawText(
                18,
                18,
                scannerItem.name,
                COLOR_GREEN
            )

            drawText(
                18,
                19,
                "damage "
                .. tostring(
                    scannerItem.damage
                ),
                COLOR_GREY
            )

        else

            drawText(
                18,
                18,
                "EMPTY",
                COLOR_RED
            )
        end


        drawButton(
            2,
            21,
            18,
            1,
            "SCAN SOURCE",
            false
        )

        drawButton(
            22,
            21,
            15,
            1,
            "TARGET",
            false
        )

        drawButton(
            39,
            21,
            15,
            1,
            "TRIGGER",
            false
        )

        drawButton(
            56,
            21,
            15,
            1,
            "YIELD",
            false
        )


        drawButton(
            22,
            23,
            18,
            1,
            current.enabled
            and "AUTO: ON"
            or "AUTO: OFF",
            current.enabled,
            COLOR_GREEN
        )

        drawButton(
            42,
            23,
            18,
            1,
            "BACK",
            false
        )


        local eventName,
              address,
              x,
              y =
            event.pull(
                "touch"
            )


        if y == 21
            and x >= 2
            and x <= 20 then

            local scanned =
                scanSourceChest()


            if scanned then

                current.sourceFingerprint =
                    makeExportFingerprint(
                        scanned.name,
                        scanned.damage
                    )

                status[aspect] =
                    "SOURCE SET"

                saveConfig()

            else

                status[aspect] =
                    "NO SCAN ITEM"
            end


        elseif y == 21
            and x >= 22
            and x <= 37 then

            current.target =
                readNumber(
                    "Target essentia:",
                    current.target
                )

            saveConfig()


        elseif y == 21
            and x >= 39
            and x <= 54 then

            current.trigger =
                readNumber(
                    "Trigger deficit:",
                    current.trigger
                )

            saveConfig()


        elseif y == 21
            and x >= 56
            and x <= 71 then

            current.essentiaPerItem =
                readNumber(
                    "Essentia per source item:",
                    current.essentiaPerItem
                )

            if current.essentiaPerItem <= 0 then
                current.essentiaPerItem = 1
            end

            saveConfig()


        elseif y == 23
            and x >= 22
            and x <= 40 then

            current.enabled =
                not current.enabled

            saveConfig()


        elseif y == 23
            and x >= 42
            and x <= 60 then

            return
        end
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


local okStart, startError =
    pcall(
        refreshNetwork
    )


if not okStart then

    log(
        "[EssentiaManager] Initial refresh error: "
        .. tostring(
            startError
        )
    )
end


rebuildFilteredAspects()

fullRedraw = true
uiDirty = true


-- ============================================================
-- MAIN LOOP
-- ============================================================

while true do

    local now =
        computer.uptime()


    -- --------------------------------------------------------
    -- Network refresh
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
    -- Scanner update
    -- --------------------------------------------------------

    if now - lastScannerScan
        >= 1.0 then

        scanSourceChest()

        lastScannerScan =
            now
    end


    -- --------------------------------------------------------
    -- GUI
    -- --------------------------------------------------------

    if uiDirty then

        drawDashboard()

        uiDirty = false
    end


    -- --------------------------------------------------------
    -- INPUT
    -- --------------------------------------------------------

    local eventName,
          address,
          a,
          b =
        event.pull(
            0.25
        )


    if eventName == "touch" then

        local x = a
        local y = b


        -- ----------------------------------------------------
        -- Filter buttons
        -- ----------------------------------------------------

        if y == 3 then

            if x >= 1 and x < 12 then

                filterMode = "ALL"
                page = 1

                lastCardSignatures = {}

                fullRedraw = true
                uiDirty = true


            elseif x >= 13 and x < 24 then

                filterMode = "LOW"
                page = 1

                lastCardSignatures = {}

                fullRedraw = true
                uiDirty = true


            elseif x >= 25 and x < 36 then

                filterMode = "ACTIVE"
                page = 1

                lastCardSignatures = {}

                fullRedraw = true
                uiDirty = true


            elseif x >= 37 and x < 48 then

                filterMode = "ERRORS"
                page = 1

                lastCardSignatures = {}

                fullRedraw = true
                uiDirty = true


            elseif x >= 49 and x < 60 then

                filterMode = "NEW"
                page = 1

                lastCardSignatures = {}

                fullRedraw = true
                uiDirty = true
            end


        -- ----------------------------------------------------
        -- Cards
        -- ----------------------------------------------------

        elseif y >= HEADER_HEIGHT + 2
            and y <
                HEADER_HEIGHT
                + 2
                + CARD_ROWS
                * (CARD_HEIGHT + 1) then

            local cardWidth =
                math.floor(
                    (
                        width
                        - (CARD_COLUMNS - 1)
                        * CARD_GAP
                    )
                    / CARD_COLUMNS
                )


            local relativeY =
                y - (HEADER_HEIGHT + 2)


            local row =
                math.floor(
                    relativeY
                    / (CARD_HEIGHT + 1)
                )


            local column =
                math.floor(
                    (
                        x - 1
                    )
                    / (
                        cardWidth
                        + CARD_GAP
                    )
                )


            if column >= 0
                and column < CARD_COLUMNS
                and row >= 0
                and row < CARD_ROWS then

                local cardIndex =
                    row
                    * CARD_COLUMNS
                    + column
                    + 1


                local filteredIndex =
                    (
                        page - 1
                    )
                    * CARDS_PER_PAGE
                    + cardIndex


                local aspect =
                    filteredAspects[
                        filteredIndex
                    ]


                if aspect then

                    selected =
                        aspect

                    editAspect(
                        aspect
                    )

                    selected = nil

                    lastCardSignatures = {}

                    fullRedraw = true
                    uiDirty = true
                end
            end


        -- ----------------------------------------------------
        -- Footer
        -- ----------------------------------------------------

        elseif y >= height - 1 then

            local pageCount =
                math.max(
                    1,
                    math.ceil(
                        #filteredAspects
                        / CARDS_PER_PAGE
                    )
                )


            if x >= width - 22
                and x < width - 13
                and page > 1 then

                page =
                    page - 1

                lastCardSignatures = {}

                fullRedraw = true
                uiDirty = true


            elseif x >= width - 12
                and page < pageCount then

                page =
                    page + 1

                lastCardSignatures = {}

                fullRedraw = true
                uiDirty = true
            end
        end


    elseif eventName == "key_down" then

        local char = a


        if char == string.byte("q") then

            break


        elseif char == string.byte("r") then

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
