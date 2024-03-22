local component = require("component")
local t = component.transposer
local rs = component.redstone

local runeAltar = 3 --transposer looking towards runealtar (south)
local chest = 1 --the chest is on top
local rsSide = 2 --redstone controller is looking towards dropper (north)

while true do
    if t.getStackInSlot(chest, 1) ~= nil and t.getStackInSlot(runeAltar, 1) == nil then
        print('---> Start creating rune')
        local totalItems = 0

        for i = 1, t.getInventorySize(chest) do
            if t.getStackInSlot(chest, i) ~= nil then
                totalItems = totalItems + t.getStackInSlot(chest, i).size
            end
        end
        sourceSlot = 1
        sinkSlot = 1
        while sinkSlot <= totalItems do
            if t.getStackInSlot(chest, sourceSlot) ~= nil then
                print('Transfering item number', sinkSlot)
                t.transferItem(chest, runeAltar, 1, sourceSlot, sinkSlot)
                sinkSlot = sinkSlot + 1
                os.sleep(0.4)
            else
                sourceSlot = sourceSlot + 1
            end
        end

        rs.setOutput(rsSide,15)
        os.sleep(0.2)
        rs.setOutput(rsSide,0)

        print('---> Finished transfering items\n')
    end
    os.sleep(1)
end