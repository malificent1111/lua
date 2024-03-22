local blackList = {
    "nickname",
}

local data = {
    {
        takeName = 'Железная руда',
        giveName = 'Железный слиток',
        amount = 2.33,
        take = {id='minecraft:iron_ore',dmg=0},
        give = {id='minecraft:iron_ingot',dmg=0},
    },
    {
        takeName = 'Медная руда',
        giveName = 'Медный слиток',
        amount = 2.33,
        take = {id='IC2:blockOreCopper',dmg=0},
        give = {id='IC2:itemIngot',dmg=0},
    },
    {
        takeName = 'Оловянная руда',
        giveName = 'Оловянный слиток',
        amount = 2.33,
        take = {id='IC2:blockOreTin',dmg=0},
        give = {id='IC2:itemIngot',dmg=1},
    },
    {
        takeName = 'Золотая руда',
        giveName = 'Золотой слиток',
        amount = 2.33,
        take = {id='minecraft:gold_ore',dmg=0},
        give = {id='minecraft:gold_ingot',dmg=0},
    },
    {
        takeName = 'Свинцовая руда',
        giveName = 'Свинцовый слиток',
        amount = 2,
        take = {id='IC2:blockOreLead',dmg=0},
        give = {id='IC2:itemIngot',dmg=5},
    },
    {
        takeName = 'Серебряная руда',
        giveName = 'Серебрянный слиток',
        amount = 2.33,
        take = {id='ThermalFoundation:Ore',dmg=2},
        give = {id='IC2:itemIngot',dmg=6},
    },
    {
        takeName = 'Никелевая руда',
        giveName = 'Никелевый слиток',
        amount = 2,
        take = {id='ThermalFoundation:Ore',dmg=4},
        give = {id='ThermalFoundation:material',dmg=68},
    },
    {
        takeName = 'Лазуритовая руда',
        giveName = 'Лазурит',
        amount = 14,
        take = {id='minecraft:lapis_ore',dmg=0},
        give = {id='minecraft:dye',dmg=4},
    },
    {
        takeName = 'Дракониевая руда',
        giveName = 'Дракониевая пыль',
        amount = 8,
        take = {id='DraconicEvolution:draconiumOre',dmg=0},
        give = {id='DraconicEvolution:draconiumDust',dmg=0},
    },
    {
        takeName = 'Алмазная руда',
        giveName = 'Алмаз',
        amount = 3,
        take = {id='minecraft:diamond_ore',dmg=0},
        give = {id='minecraft:diamond',dmg=0},
    },
    {
        takeName = 'Красная руда',
        giveName = 'Красная пыль',
        amount = 8,
        take = {id='minecraft:redstone_ore',dmg=0},
        give = {id='minecraft:redstone',dmg=0},
    },
    {
        takeName = 'Руда истинного кварца',
        giveName = 'Истинный кварц',
        amount = 4,
        take = {id='appliedenergistics2:tile.OreQuartz',dmg=0},
        give = {id='appliedenergistics2:item.ItemMultiMaterial',dmg=0},
    },
    {
        takeName = 'Угольная руда',
        giveName = 'Уголь',
        amount = 3,
        take = {id='minecraft:coal_ore',dmg=0},
        give = {id='minecraft:coal',dmg=0},
    },

}

local component = require("component")
local event = require("event")
local change = {
    me = component.proxy("385296c7-333a-402b-8856-da179dbc7f34"),
    pim = component.proxy("842cf441-a224-4fbb-9661-c389aa41032b"),
    fingerprint = "change",
}

local cobble = {
    me = component.proxy("0f6a3c5d-8662-4264-9e59-6df886fa4ebf"),
    fingerprint = {id='minecraft:cobblestone',dmg=0},
}

local stone = {
    me = component.proxy("6e260c9c-a83e-4645-b42c-db800f622214"),
    fingerprint = {id='minecraft:stone',dmg=0},
}

local sand = {
    me = component.proxy("64c86fcc-9787-4bfa-a5e8-281f20743329"),
    fingerprint = {id='minecraft:sand',dmg=0},
}

local glass = {
    me = component.proxy("fceedae9-cd0a-4421-a71b-f3bc6860d191"),
    fingerprint = {id='minecraft:glass',dmg=0},
}

function hasValue (tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end



function whatPim(e)
    if e == "a45f6b0d-a39b-4a84-b5c0-03142ace3880" then
        return change
    end
    if e == "204834a5-f525-4149-9ad6-06f78e8b68c6" then
        return cobble
    end
    if e == "92e0b96f-1e49-48b9-b4f8-3690ad0fb4fc" then
        return stone
    end
    if e == "ec1dfae0-0b12-414b-91e2-a793337d9724" then
        return sand
    end
    return glass

end

local function scanInventory(player)
    size = 36
    for i = 1, size do
        if change.pim.getStackInSlot(i) then
            slot = change.pim.getStackInSlot(i)

            for j = 1, #data do
                if slot.id == data[j].take.id and slot.dmg == data[j].take.dmg then
                    exchange(i, slot, data[j], player)
                end
            end
        end
    end
end


function exchange(i, slot, data, player)
    shouldGiveQty = math.floor(slot.qty*data.amount+0.5)
    if change.me.getItemDetail(data.give) then
        currentQty = change.me.getItemDetail(data.give).basic().qty
    else
        currentQty = -1
    end

    if currentQty and currentQty > shouldGiveQty then
        io.write(player, " is changing ", slot.qty, " ", slot.display_name, "\n")
        takedOre = change.pim.pushItem("DOWN", i, slot.qty)
        if takedOre then
            toGiveItems = math.floor(takedOre*data.amount+0.5)

            currentGive = 0

            while currentGive < toGiveItems do
                if pcall(function() gived = change.me.exportItem(data.give, "UP", toGiveItems-currentGive, 0).size  end) then
                    currentGive = currentGive + gived
                end
            end

            if currentGive < toGiveItems then
                print("Not enough space in inventory")
                change.me.exportItem(data.take, "UP", math.floor((toGiveItems-currentGive)/data.amount+0.5), 0)
            end
        else
            print("Attempt to perform arithmetic on a nil value")
        end

    else
        print("Not enough items in system") return
    end
end

while true do
    local e = {event.pull()}
    if e[1] == "player_on" and not hasValue(blackList, e[2]) then
        currentPim = whatPim(e[4])
        if currentPim.fingerprint == "change" then
            scanInventory(e[2])
        else
            io.write(e[2], " took ", currentPim.fingerprint.id, "\n")
            canExportItems = true
            while canExportItems do
                if currentPim.me.getItemDetail(currentPim.fingerprint) then
                    exp = currentPim.me.exportItem(currentPim.fingerprint, "UP", 64, 0).size
                end
                if exp < 7 then
                    canExportItems = false
                end
            end
        end
    end
end