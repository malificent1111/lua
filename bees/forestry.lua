local component = require "component"
local t = component.transposer
local cp = component.container_pedestal
local gpu = component.gpu
local apiary = 2
local workChest = 3
local finishChest = 1

local beeOnPedestalGlobal = cp.getStackInSlot(1).individual

function isAnalyzed(bee)
    if not getChestSlot(bee).individual.isAnalyzed then
        return "notAnalyzed"
    end
end

function areGenesEqual(beeOnPedestal, currentBee)

    if beeOnPedestal.species.name ~= currentBee.species then
        return "name"
    end

    if beeOnPedestal.fertility ~= currentBee.fertility then
        return "fertility"
    end

    if beeOnPedestal.effect ~= currentBee.effect then
        return "effect"
    end

    if beeOnPedestal.speed ~= currentBee.speed then
        return "speed"
    end

    if beeOnPedestal.flowerProvider ~= currentBee.flowerProvider then
        return "flowerProvider"
    end

    if beeOnPedestal.lifespan ~= currentBee.lifespan then
        return "lifespan"
    end

    if beeOnPedestal.humidityTolerance ~= currentBee.humidityTolerance then
        return "humidityTolerance"
    end

    if beeOnPedestal.humidityTolerance ~= currentBee.humidityTolerance then
        return "humidityTolerance"
    end

    for i = 1, 3 do
        if beeOnPedestal.territory[i] ~= currentBee.territory[i] then
            return "territory"
        end
    end

    if beeOnPedestal.nocturnal ~= currentBee.nocturnal then
        return "nocturnal"
    end

    if beeOnPedestal.caveDwelling ~= currentBee.caveDwelling then
        return "caveDwelling"
    end

    if beeOnPedestal.temperatureTolerance ~= currentBee.temperatureTolerance then
        return "temperatureTolerance"
    end

    if beeOnPedestal.tolerantFlyer ~= currentBee.tolerantFlyer then
        return "tolerantFlyer"
    end


    return "finished"

end

function getChestSlot(bee)
    if t.getStackInSlot(workChest, bee) == nil then
        return "nil"
    else
        return t.getStackInSlot(workChest, bee)
    end
end

function sendBeeToApiary(bee)
    local transferResult = 0
    while transferResult == 0 do
        transferResult = t.transferItem(workChest,apiary,1,bee,1)
        if transferResult == 1 then
            gpu.setForeground(0x5555FF)
            io.write("Transfering princess number ", bee, " to apiary\n")
            gpu.setForeground(0xFFFFFF)
        end
    end
end

io.write('How many queens do you want? - ')
    local totalQty = io.read()
    totalQty = tonumber(totalQty)

    local currentSlots = 0

    for i = 1, t.getInventorySize(workChest) do
        if getChestSlot(i) ~= "nil" then
            currentSlots = currentSlots + 1
        end
    end

    if currentSlots < totalQty then
        gpu.setForeground(0xFF0000)
        print("Not enought queens!")
        gpu.setForeground(0xFFFFFF)

        os.exit()
    end

    if not beeOnPedestalGlobal.isAnalyzed then
        gpu.setForeground(0xFF0000)
        print("The bee on pedestal is not analyzed!")
        gpu.setForeground(0xFFFFFF)
    end

    gpu.setForeground(0xFF00FF)
    print("Please, be sure you have enough drones!")
    gpu.setForeground(0xFFFFFF)


    local finished = 0
    local previousFinished = 0
    while finished < totalQty do
        for i = 1, totalQty do
            if getChestSlot(i) ~= "nil" then
                if isAnalyzed(i) == "notAnalyzed" then
                    sendBeeToApiary(i)
                    finished = 0
                else
                    active = areGenesEqual(beeOnPedestalGlobal.active, getChestSlot(i).individual.active)
                    inactive = areGenesEqual(beeOnPedestalGlobal.inactive, getChestSlot(i).individual.inactive)
                    if active ~= "finished" or inactive ~= "finished" then
                        io.write("Princess number ", i, " has no ", active, " or ", inactive, "\n")
                        sendBeeToApiary(i)
                        finished = 0
                    elseif active == "finished" and inactive == "finished" then
                        finished = finished + 1
                    end
                end
            end
        end

        if finished > 0 and finished ~= previousFinished then
            gpu.setForeground(0x55FF55)
            print("Finished princesses: ", finished)
            gpu.setForeground(0xFFFFFF)
        end

        if finished < totalQty then
            previousFinished = finished
            finished = 0
        end
        os.sleep(0.2)
    end

    gpu.setForeground(0xFF00FF)
    print("Transfering princesses to finish chest...")
    gpu.setForeground(0xFFFFFF)

    for i = 1, totalQty do
        j = i
        transferStatus = 0
        while transferStatus == 0 do
            transferStatus = t.transferItem(workChest, finishChest, 1, i, j)
            j = j + 1
        end
    end


    gpu.setForeground(0xFF00FF)
    print("Ordering work chest...")
    gpu.setForeground(0xFFFFFF)

    for i = 1, t.getInventorySize(workChest) do
        if (getChestSlot(i) ~= "nil") then
            t.transferItem(workChest, workChest, 1, i, i-totalQty)
        end
    end

    gpu.setForeground(0x55FF55)
    print("Everything is finished!")
    gpu.setForeground(0xFFFFFF)