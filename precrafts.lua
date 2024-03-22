local component = require("component")
local serialize = require("serialization")
local me = component.me_interface
local data = {}
local marketData = {}
local gpu = component.gpu

local file = io.open("craftsData")
if not file then
    print("File craftsData not found")
    os.exit()
end

local text = file:read("*a")

file:close()
if(text ~= nil and text ~= '') then
    data = serialize.unserialize(text)
else
    print("File with craftsData is empty")
    os.exit()
end

local file = io.open("marketItems")
if not file then
    print("File marketItems not found")
    os.exit()
end

local text = file:read("*a")

file:close()
if(text ~= nil and text ~= '') then
    marketData = serialize.unserialize(text)
else
    print("File with marketItems is empty")
    os.exit()
end

local precrafts = {}

for k,v in pairs(data) do
    precrafts[k] = {
        fingerprint = {id = data[k].item.id, dmg = data[k].item.dmg},
        name = data[k].name,
        perCraft = data[k].craft,
        minQty = data[k].items,
        isCrafting = false,
        craftingStatus = {},
        tries = 0
    }
end

local needToCraftMarket = {}

for i = 1, #marketData do
    if marketData[i].needed then
        table.insert(needToCraftMarket, {
            data = marketData[i],
            craftingStatus = {},
            isCrafting = false,
            tries = 0
        })
    end
end

for i = 1, #needToCraftMarket do
    delete = false
    for j = 1, #precrafts do
        if precrafts[j].fingerprint.id == needToCraftMarket[i].data.fingerprint[1].id  and
        precrafts[j].fingerprint.dmg == needToCraftMarket[i].data.fingerprint[1].dmg then
            delete = true
        end
    end
    if delete then
        needToCraftMarket[i] = "deleted"
    end
end

local solarPanels = {
    fingerprint = {name = 'IC2:blockGenerator', damage = 3.0},
    name = 'Солнечная панель 1-го уровня',
    perCraft = 100,
    ironQty = 30000,
    isCrafting = false,
    craftingStatus = {},
    tries = 0
}

local redstone = {
    fingerprint = {name = 'minecraft:redstone', damage = 0.0},
    name = 'Красная пыль',
    perCraft = 1152,
    rsBlocks = 128,
    isCrafting = false,
    craftingStatus = {},
}

local materia = {
    fingerprint = {name = 'dwcity:Materia', damage = 0.0},
    limit = 1072,
    isCrafting = false,
}


function areOresCrafting()
    local craftingOres = {
        {qty = -1, fingerprint = {name = "minecraft:redstone_ore", damage = 0}},
        {qty = -1, fingerprint = {name="IC2:itemCrushedOre", damage=2.0}},
        {qty = -1, fingerprint = {name="IC2:itemPurifiedCrushedOre", damage=2.0}},
        {qty = -1, fingerprint = {name="IC2:itemCrushedOre", damage=0.0}},
        {qty = -1, fingerprint = {name="IC2:itemPurifiedCrushedOre", damage=0.0}},
        {qty = -1, fingerprint = {name="IC2:itemCrushedOre", damage=1.0}},
        {qty = -1, fingerprint = {name="IC2:itemPurifiedCrushedOre", damage=1.0}},
        {qty = -1, fingerprint = {name="IC2:itemCrushedOre", damage=3.0}},
        {qty = -1, fingerprint = {name="IC2:itemPurifiedCrushedOre", damage=3.0}},
    }

    for i=1, #craftingOres do
        while craftingOres[i].qty == -1 do
            if (pcall(function ()
                craftingOres[i].qty = me.getItemsInNetwork(craftingOres[i].fingerprint)[1].size
            end)) then
            else
                craftingOres[i].qty = 0
            end
            os.sleep(0.1)
        end

        if craftingOres[i].qty > 0 then
            return true
        end
    end
    return false
end

while true do

    for i = 1, #precrafts do
        local qty = -1
        while qty == -1 do
            if (pcall(function ()
                qty = me.getItemsInNetwork({name=precrafts[i].fingerprint.id, damage = precrafts[i].fingerprint.dmg})[1].size
            end)) then
            end
        end
        if precrafts[i].isCrafting then
            if precrafts[i].craftingStatus.isDone() or precrafts[i].craftingStatus.isCanceled() then
                precrafts[i].isCrafting = false
                precrafts[i].craftingStatus = {}
            end
        end

        if tonumber(precrafts[i].minQty) > qty and not precrafts[i].isCrafting then
            if (pcall(function() precrafts[i].craftingStatus = me.getCraftables(
                {name=precrafts[i].fingerprint.id, damage = precrafts[i].fingerprint.dmg}
            )[1].request(tonumber(precrafts[i].perCraft)) end)) then
                os.sleep(0.1)
                if not precrafts[i].craftingStatus.isCanceled() and not precrafts[i].craftingStatus.isDone() then
                    gpu.setForeground(0x55FF55)
                    io.write("Need to create ", precrafts[i].minQty - qty, " ", precrafts[i].name, "\n")
                    gpu.setForeground(0xFFFFFF)
                    io.write("Start creating ", precrafts[i].perCraft, " items", "\n")
                    precrafts[i].isCrafting = true
                    precrafts[i].tries = 0
                elseif precrafts[i].craftingStatus.isCanceled() and precrafts[i].tries == 0 then
                    gpu.setForeground(0xFF0000)
                    print("Oops... no resources to craft", precrafts[i].name)
                    gpu.setForeground(0xFFFFFF)
                    precrafts[i].tries = 1
                end
            else
                gpu.setForeground(0xFF0000)
                print("Sorry, craft does not exist ---> ", precrafts[i].name)
                gpu.setForeground(0xFFFFFF)
            end

        end
    end

    for i = 1, #needToCraftMarket do
        if needToCraftMarket[i] ~= "deleted" then
            qty = -1
            while qty == -1 do
                if pcall(function ()
                    qty = me.getItemsInNetwork({name=needToCraftMarket[i].data.fingerprint[1].id, damage = needToCraftMarket[i].data.fingerprint[1].dmg})[1].size
                end) then
                end
            end

            if needToCraftMarket[i].isCrafting then
                if needToCraftMarket[i].craftingStatus.isDone() or needToCraftMarket[i].craftingStatus.isCanceled() then
                    needToCraftMarket[i].isCrafting = false
                    needToCraftMarket[i].craftingStatus = {}
                end
            end

            if qty < needToCraftMarket[i].data.needed and not needToCraftMarket[i].isCrafting then
                if (pcall(function() needToCraftMarket[i].craftingStatus = me.getCraftables(
                    {name=needToCraftMarket[i].data.fingerprint[1].id, damage = needToCraftMarket[i].data.fingerprint[1].dmg}
                )[1].request(needToCraftMarket[i].data.needed - qty)  end )) then
                    os.sleep(0.1)
                    if not needToCraftMarket[i].craftingStatus.isCanceled() and not needToCraftMarket[i].craftingStatus.isDone() then
                        gpu.setForeground(0xffaa00)
                        io.write("Market needs to create ", needToCraftMarket[i].data.needed - qty, " ", needToCraftMarket[i].data.text, "\n")
                        gpu.setForeground(0xFFFFFF)
                        io.write("Start creating ", needToCraftMarket[i].data.needed - qty, " items", "\n")
                        needToCraftMarket[i].isCrafting = true
                        needToCraftMarket[i].tries = 0
                    elseif needToCraftMarket[i].craftingStatus.isCanceled() and needToCraftMarket[i].tries == 0 then
                        gpu.setForeground(0xFF0000)
                        print("Oops... no resources to craft", needToCraftMarket[i].data.text)
                        gpu.setForeground(0xFFFFFF)
                        needToCraftMarket[i].tries = 1
                    end
                else
                    gpu.setForeground(0xFF0000)
                    print("Sorry, craft does not exist ---> ", needToCraftMarket[i].data.text)
                    gpu.setForeground(0xFFFFFF)
                end
            end
        end

    end

    local rsBlocks = -1
    while rsBlocks == -1 do
        if pcall(function ()
            rsBlocks = me.getItemsInNetwork({name="minecraft:redstone_block", damage = 0.0})[1].size
        end) then
        end
    end
    if redstone.isCrafting then
        if redstone.craftingStatus.isDone() or redstone.craftingStatus.isCanceled() then
            redstone.isCrafting = false
            redstone.craftingStatus = 0
        end
    end

    if rsBlocks > redstone.rsBlocks and not redstone.isCrafting then
        if (pcall(function() redstone.craftingStatus = me.getCraftables(redstone.fingerprint)[1].request(redstone.perCraft) end)) then
            if not redstone.craftingStatus.isCanceled() and not redstone.craftingStatus.isDone() then
                redstone.isCrafting = true
                gpu.setForeground(0xFF55FF)
                io.write("Start creating ", redstone.perCraft, " redstone", "\n")
                gpu.setForeground(0xFFFFFF)
            end
        end
    end

    local materiaQty = -1
    while materiaQty == -1 do
        if pcall(function ()
            materiaQty = me.getItemsInNetwork(materia.fingerprint)[1].size
        end) then
        end
    end

    readyOres = 0

    if materiaQty > materia.limit and not areOresCrafting() then
        ores = {
            {toCheck = {currentQty = -1, fingerprint = {name='IC2:itemIngot', damage = 0.0}, qty = 30000}, toCraft = {fingerprint = {name='IC2:blockOreCopper',damage=0}, qty = 166}},
            {toCheck = {currentQty = -1, fingerprint = {name='minecraft:gold_ingot', damage = 0.0}, qty = 10000}, toCraft = {fingerprint = {name='minecraft:gold_ore',damage=0}, qty = 40}},
            {toCheck = {currentQty = -1, fingerprint = {name='minecraft:redstone', damage = 0.0}, qty = 100000}, toCraft = {fingerprint = {name='minecraft:redstone_ore',damage=0}, qty = 67}},
            {toCheck = {currentQty = -1, fingerprint = {name='minecraft:coal', damage = 0.0}, qty = 50000}, toCraft = {fingerprint = {name='minecraft:coal_ore',damage=0}, qty = 273}},
            {toCheck = {currentQty = -1, fingerprint = {name='minecraft:iron_ingot', damage = 0.0}, qty = 30000}, toCraft = {fingerprint = {name='minecraft:iron_ore',damage=0}, qty = 410}},
            {toCheck = {currentQty = -1, fingerprint = {name='IC2:itemIngot', damage = 1.0}, qty = 30000}, toCraft = {fingerprint = {name='IC2:blockOreTin',damage=0}, qty = 104}},
        }

        readyOres = 0

        for i=1, #ores do
            while ores[i].toCheck.currentQty == -1 do
                if (pcall(function ()
                    ores[i].toCheck.currentQty = me.getItemsInNetwork(ores[i].toCheck.fingerprint)[1].size
                end)) then
                end
            end

            if ores[i].toCheck.currentQty < ores[i].toCheck.qty then
                if (pcall(function() me.getCraftables(ores[i].toCraft.fingerprint)[1].request(ores[i].toCraft.qty) end)) then
                end

                gpu.setForeground(0xFFFF55)
                io.write('Start creating ', ores[i].toCraft.fingerprint.name, '\n')
                gpu.setForeground(0xFFFFFF)
                break
            end
            readyOres = readyOres + 1
        end
    end

    if readyOres == #ores then
        gpu.setForeground(0x5555FF)
        io.write("Start creating ", solarPanels.perCraft, " solar panels", "\n")
        gpu.setForeground(0xFFFFFF)
        if (pcall(function() me.getCraftables(solarPanels.fingerprint)[1].request(solarPanels.perCraft) end)) then
        end
    end




    os.sleep(0.2)
end