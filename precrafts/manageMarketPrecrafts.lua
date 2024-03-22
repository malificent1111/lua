local component = require("component")
local chest = component.diamond
local gpu = component.gpu
local data = {}
local serialize = require("serialization")

local file = io.open("items")
if not file then
    print("File not found")
    os.exit()
end

io.open("items", "w"):close()

for i = 1, chest.getInventorySize() do
    if chest.getStackInSlot(i) ~= nil then
        item = chest.getStackInSlot(i)
        
        gpu.setForeground(0xffaa00)
        print("Enter data for ", item.display_name)
        gpu.setForeground(0xffffff)
        
        print("Print original name: ")
        name = io.read()
        
        print("Print maximum items to sell at once: ")
        maxQty = io.read()
        
        fingerPrint = {
            {dmg = item.dmg, id = item.id}
        }
        
        rawName = {item.raw_name}
        
        data[i] = {
            text = name,
            buyPrice = tonumber(price),
            minCount = 1,
            maxCount = tonumber(maxQty),
            fingerprint = fingerPrint,
            raw_name = rawName
        }
    end
end

file = io.open("items", "w")
file:write(serialize.serialize(data))
file:close()