local component = require("component")
local robot = require("robot")
local ic = component.inventory_controller
local geo = component.geolyzer

local pickaxe = "Awakened Ichorium Pickaxe"
local axe = "Awakened Ichorium Axe"

local function robotGoForward()
    while robot.forward() do
        whatToDo.fn()
        os.sleep(0.1)
    end
end

local function placeBlock()
    robot.placeDown()
end

local function passWay()
    for i = 1, 4 do
        robotGoForward()
        robot.turnLeft()
    end
    robot.back()
end

local function destroyBlock()
    while geo.analyze(0).name ~= block do
        if geo.analyze(0).name == 'minecraft:air' then
            return
        end
        os.sleep(0.5)
    end
    if geo.analyze(0).name == block then
        robot.swingDown()
    end
end



print("Какой блок желаете получить?\n")
print("1 - Жизнекамень")
print("2 - Жизнедерево")
local userChoice = io.read("*n")

if pcall(function()
    anotherInstrument = ic.getStackInInternalSlot(2).label
end) then
else
    print("Поставьте инструмент во второй слот робота!")
    os.exit()
end


if userChoice == 1 then
    if anotherInstrument == pickaxe then
        robot.select(2)
        ic.equip()
    end
    block = "Botania:livingrock"
elseif userChoice == 2 then
    if anotherInstrument == axe then
        robot.select(2)
        ic.equip()
    end
    block = "Botania:livingwood"
else
    print("Неправильно введенное число! Попробуйте снова!")
    os.exit()
end

robot.select(1)

while true do
    ic.suckFromSlot(0, userChoice)

    whatToDo = {
        fn = function() placeBlock() end
    }
    passWay(whatToDo)

    os.sleep(30)

    whatToDo = {
        fn = function() destroyBlock() end
    }
    passWay(whatToDo)
    ic.dropIntoSlot(0, 3)
    
    os.sleep(1)
end