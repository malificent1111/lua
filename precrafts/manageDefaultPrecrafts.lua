local component = require("component")
local serialize = require("serialization")
local string = require("string")
local data = {}
local inputPoint = "-1"
local cp = component.container_pedestal

local file = io.open("craftsData")
if not file then
    print("File not found")
    os.exit()
end
local text = file:read("*a")
if(text ~= nil and text ~= '') then
    data = serialize.unserialize(text)
end
file:close()

function addPrecraft()
    local item = cp.getStackInSlot(1)
    if item == nil then
        print("No items requested or middle item is missing")
        return
    end

    print("Enter craft name: ")
    local craftName = io.read()
    if(craftName == '') then
        craftName = item.name .. ":" .. item.dmg
    end

    print("How many items to keep in stock? - ")
    local minQty = io.read()
    if(minQty == '') then
        minQty = 1
    end

    print("How many items to craft max at once? - ")
    local perCraft = io.read()
    if(perCraft == '') then
        perCraft = 1
    end


    data[#data+1] = {item = {id = item.id, dmg = item.dmg}, name = craftName, items = minQty, craft = perCraft}
end

function deletePrecraft()
    print("Enter precraft name. To find out existed precrafts type 2 in the main menu")
    local craftN = io.read()
    if(craftN == nil or craftN == '') then
        return
    end
    for k,v in pairs(data) do
        if(data[k].name ~= nil and data[k].name == craftN) then
            table.remove(data, k)
            print("Successfully removed this craft!")
            return
        end
    end
    print("Given name was not found in the list")
end

function showPrecrafts()
    if(#data == 0) then
        print("Craft list in empty")
        return
    end
    for k,v in pairs(data) do
        io.write("name = ", data[k].name, ", quantity = ", data[k].items, ", crafting = ", data[k].craft, "\n")
    end
end

while inputPoint ~= "4" do
    print("----------------------------")
    print("What should we do:")
    print("1 - add precraft")
    print("2 - show precrafts")
    print("3 - delete precraft")
    print("4 - exit")
    print("----------------------------")
    inputPoint = io.read()

    if(inputPoint == "1") then
        addPrecraft()
        goto continue
    end
    if(inputPoint == "2") then
        showPrecrafts()
        goto continue
    end
    if(inputPoint == "3") then
        deletePrecraft()
        goto continue
    end
    if(inputPoint == "4") then
        file = io.open("craftsData", "w")
        file:write(serialize.serialize(data))
        file:close()
        os.sleep(0.5)
    end
    ::continue::
end