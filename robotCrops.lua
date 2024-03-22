--Скрипт для робота, для поднятия статов у кропсов или разведения дубликатов (режим задается константой mode)
--Автор: aka_zaratustra осень 2020
local ver = "1.1.3" -- версия программы
--Историю версий см. в конце файла

-- схема грядки
--|C1|M1|C2
--|M2|C3|M3
--|C4|M4|C5
--|CH|P0|BR
 
-- P0 - исходное положение робота. Робот находится на 1 блок выше кропсов (чтобы мог летать над ними), смотрит на север (в сторону грядок). В руках у робота должна быть лопатка Spade. В первом слоте инвентори робота или должны быть палки или он должен быть пустой (робот сам возьмет и положет туда палки)
-- С[n] - дочерние (разводимые) растения
-- M[n] - материнские растения
-- СН - chest, сундук, куда будут помещаться мешочки с семечками и урожай
-- BR - барель с кропсами(палками)
 
-- В начале работы материнские кропсы должны быть высажены на грядку. Дочерние (разводимые) могут быть высажены, а может быть голая земля.
-- У робота должны в обязательном порядке присутстовать компоненты: Geolyzer, Inventory Upgrade, Inventory Controller Upgrade
-- Рекомендуется для удобства поместить файл с этим скриптом в папку /home/ , а имя файла скрипта добавить в файл /home/.shrc - тогда скрипт будет запускаться при включении робота автоматически
-- Если в бочке кончаются кропсы(палки), робот сломает пустые палки, если они есть на поле и завершит свою работу с ошибкой (чтобы всё поле не сожрали сорняки)
-- Максимальные статы кропсов, выше которых робот поднимать статы выводимых кропсов не будет, задаются константами max_grow и max_gain
-- Стат resistans робот не поднимает, а при возможости опускает до 0
-- Начиная с версии 1.1.3 робот перестал быть уязвим к коллизиям. Нахождение игрока на пути следования робота больше не приводит к потере роботом маршрута. Робот после столкновения с игроком замирает на секунду, после чего продолжает попытку движения.
-- Механизм оценки приемлемости (качества) полученного растения менять в функции howInterestingIsThisCrop(с)
-- При наличии интернет карты в роботе, скрипт в робота можно загрузить командой `pastebin get cZY3P7As -f crop_stats.lua`
 
-- mode:
-- 1 - режим поднятия статов кропсов
-- 2 - режим разведения дубликатов кропсов (НЕ ТЕСТИРОВАЛСЯ! НЕ ИСПОЛЬЗОВАТЬ!)
local mode = 1
-- выше заданных здесь значений робот понимать статы не будет
local max_grow = 20 -- если больше 23, то кроп начинает вести себя как сорняк
local max_gain = 28
local grow_kill = 24 -- значение стата grow, при котором и выше которого робот будет убивать растение на корню
 
local robot = require("robot") 
local computer = require("computer") 
local component = require("component") 
local geo = component.geolyzer
local cropname
 
local c_cropname = {} --имена дочерних кропов
--статы дочерних кропов
local c_gain = {}
local c_grow = {}
local c_resistans = {} 
local c_size = {} 
local c_maxSize = {} 
 
-- статус может принимать значения:
-- "unknown" - неисследованный. назначается при старте, дальше не используется
-- "double crop" - жердочки
-- "growing" - растущий кроп, у которого статы или дошли до целевых или лучше материнских. после вырастания или отправится в сундук или может заменить собой материнский кроп
local c_status = {"unknown", "unknown", "unknown", "unknown", "unknown"} -- "unknown" для всех пяти дочерних кропов
 
local m_gain = {}
local m_grow = {}
local m_resistans = {}
 
local error_string
local bestSeedsSlot --слот в инвентори робота с семенами с лучшими статами
local robotLocation -- текущее местонаходение робота. значение из списка: {"С1", "С2", ... , "С5", "M1", "M2", "M3", "M4", "P0"}
 
function robot_error(msg)
    print("Ошибка: ", msg)
    computer.beep(1000,0.3)
    computer.beep(1000,0.3)
    computer.beep(1000,0.3)
    os.exit()
end
 
function robotTryForward() -- роботы пытается сделать шаг вперед, до тех пор, пока ему это не удастся
    while robot.forward() == nil do
        print("Робот столкнулся с препятствием.")
        os.sleep(1) -- останавливаем робота на 1 секунду
    end
end
--------------------------------------
function get_crop_stat(analyze_result, stat_name) --функция - просматривает таблицу скана блока и возвращает значение поля, имя которого передано в stat_name. если не находит, то возвращает nil
    --file = io.open("log.txt", "a") --файл для лога 
    found = false
    for name, v in pairs(analyze_result) do --просмотрим таблицу реультата анализа кропса
        
        pos = string.find(name, stat_name) 
        --print(pos)
        if pos ~=  nil then -- если строку в метадате нашли
            found = true
            --print(v)
            return v
        end
    end
 
end
 
function robotMove_P0_M1()
    --исходное положение P0 смотрит вверх
    robotTryForward()
    robotTryForward()
    robotTryForward()
    --конечное положение M1 смотрит вверх
end
function robotMove_M1_M2()
    --начальное положение M1 смотрит вверх
    robot.turnLeft()
    robotTryForward()
    robot.turnLeft()
    robotTryForward()
    --конечное положение M2 смотрит вниз
end
function robotMove_M2_M3()
    --начальное положение M2 смотрит вниз
    robot.turnLeft()
    robotTryForward()
    robotTryForward()
    --конечное положение M3 смотрит вправо
end
function robotMove_M3_M4()
    --начальное положение M3 смотрит вправо
    robot.turnRight()
    robotTryForward()
    robot.turnRight()
    robotTryForward()
    --конечное положение M4 смотрит влево
end
function robotMove_M4_P0()
    --начальное положение M4 смотрит влево
    robot.turnLeft()
    robotTryForward()
    robot.turnAround()
    --конечное положение P0 смотрит вверх
end
function robotMove_P0_C1()
    --начальное положение P0 смотрит вверх
    robotTryForward()
    robotTryForward()
    robotTryForward()
    robot.turnLeft()
    robotTryForward()
    --конечное положение C1 смотрит влево
end
function robotMove_C1_C4()
    --начальное положение C1 смотрит влево
    robot.turnLeft()
    robotTryForward()
    robotTryForward()
    --конечное положение C4 смотрит вниз
end
function robotMove_C4_C5()
    --начальное положение C4 смотрит вниз
    robot.turnLeft()
    robotTryForward()
    robotTryForward()
    --конечное положение C5 смотрит вправо
end
function robotMove_C5_C2()
    --начальное положение C5 смотрит вправо
    robot.turnLeft()
    robotTryForward()
    robotTryForward()
    --конечное положение C2 смотрит вверх
end
function robotMove_C2_C3()
    --начальное положение C2 смотрит вверх
    robot.turnLeft()
    robotTryForward()
    robot.turnLeft()
    robotTryForward()
    --конечное положение C3 смотрит вниз
end
function robotMove_C3_P0()
    --начальное положение C3 смотрит вниз
    robotTryForward()
    robotTryForward()
    robot.turnAround()
    --конечное положение P0 смотрит вверх
end
function robotGoToParkFrom_M_Crop(m) --едем на парковку. "m" - номер материнского кропа с которого мы едем
    if m == 1 then
        --начальное положение M1 смотрит вверх
        robot.turnAround()
        robotTryForward()
        robotTryForward()
        robotTryForward()
        robot.turnAround()
        --конечное положение P0 смотрит вверх
    end
    if m == 2 then
        --начальное положение M2 смотрит влево
        robot.turnAround()
        robotTryForward()
        robot.turnRight()
        robotTryForward()
        robotTryForward()
        robot.turnAround()
        --конечное положение P0 смотрит вверх
    end
    if m == 3 then
        --начальное положение M3 смотрит вправо
        robot.turnAround()
        robotTryForward()
        robot.turnLeft()
        robotTryForward()
        robotTryForward()
        robot.turnAround()
        --конечное положение P0 смотрит вверх
    end
    if m == 4 then
        --начальное положение M4 смотрит влево
        robot.turnLeft()
        robotTryForward()
        robot.turnAround()
        --конечное положение P0 смотрит вверх  
    end
end
function robotGoToPark(c) --едем на парковку. "с" - номер дочернего кропа с которого мы едем
    if c == 1 then
        --начальное положение C1 смотрит влево
        robot.turnAround()
        robotTryForward()
        robot.turnRight()
        robotTryForward()
        robotTryForward()
        robotTryForward()
        robot.turnAround()
        --конечное положение P0 смотрим вверх
    end
    if c == 2 then
        --начальное положение C2 смотрит вверх
        robot.turnLeft()
        robotTryForward()
        robot.turnLeft()
        robotTryForward()
        robotTryForward()
        robotTryForward()
        robot.turnAround()
        --конечное положение P0 смотрим вверх
    end
    if c == 3 then
        --начальное положение C3 смотрит вниз
        robotTryForward()
        robotTryForward()
        robot.turnAround()
        --конечное положение P0 смотрим вверх
    end
    if c == 4 then
        --начальное положение C4 смотрит вниз
        robot.turnLeft()
        robotTryForward()
        robot.turnRight()
        robotTryForward()
        robot.turnAround()
        --конечное положение P0 смотрим вверх
    end
    if c == 5 then
        --начальное положение C5 смотрит вправо
        robot.turnAround()
        robotTryForward()
        robot.turnLeft()
        robotTryForward()
        robot.turnAround()
        --конечное положение P0 смотрим вверх
    end
 
end
function robotGoTo_M_Crop_FromPark(m) --едем с парковки P0 к материнскому кропу. "m" - номер кропа к которому мы едем
    if m==1 then
        --исходное положение P0 смотрит вверх
        robotTryForward()
        robotTryForward()
        robotTryForward()
        --конечное положение M1 смотрит вверх
    end
    if m==2 then
        --начальное положение P0 смотрит вверх
        robotTryForward()
        robotTryForward()
        robot.turnLeft()
        robotTryForward()
        --конечное положение M2 смотрит влево
    end
    if m==3 then
        --начальное положение P0 смотрит вверх
        robotTryForward()
        robotTryForward()
        robot.turnRight()
        robotTryForward()
        --конечное положение M3 смотрит вправо
    end
    if m==4 then
        --начальное положение P0 смотрит вверх
        robotTryForward()
        robot.turnLeft()        
        --конечное положение M4 смотрит влево
    end
end
function robotGoTo_C_Crop_FromPark(c) --едем с парковки P0 к дочернему кропу. "с" - номер кропа к которому мы едем
    if c == 1 then
        --начальное положение P0 смотрим вверх
        robotTryForward()
        robotTryForward()
        robotTryForward()
        robot.turnLeft()
        robotTryForward()
        --конечное положение C1 смотрит влево
    end
    if c == 2 then
        --начальное положение P0 смотрим вверх
        robotTryForward()
        robotTryForward()
        robotTryForward()
        robot.turnRight()
        robotTryForward()
        robot.turnLeft()
        --конечное положение C2 смотрит вверх
    end
    if c == 3 then
        --начальное положение P0 смотрим вверх
        robotTryForward()
        robotTryForward()
        robot.turnAround()
        --конечное положение C3 смотрит вниз
    end
    if c == 4 then
        --начальное положение P0 смотрим вверх
        robotTryForward()
        robot.turnLeft()
        robotTryForward()
        robot.turnLeft()
        --конечное положение C4 смотрит вниз
    end
    if c == 5 then
        --начальное положение P0 смотрим вверх
        robotTryForward()
        robot.turnRight()
        robotTryForward()
        --конечное положение C5 смотрит вправо
    end
 
end
function grabCropsFromBarrel() --пополняем запас палок в роботе из бочки. 
    --возвращает true если после попытки взять палки, есть хотя бы одна палка в роботе
    --возвращает false если палки в роботе и в бочке кончились
    cropsStackSize = 62 --размер стака палок, который робот возит с собой. 62 потому что при уничтожения кропса робот выдерает из земли и палки, и они могут попасть в нецелевой слот
    
    --палки лежат в первом слоте
    returnValue = true
    itemCount = robot.count(1)
    if itemCount < cropsStackSize then --если палок неполный стак, до доберем из бочки
        robot.select(1) --активизируем слот, в котором лежат палки
        robot.turnRight() --повернемся к бочке
        --добираем палок до полного стака
        robot.suck(cropsStackSize-itemCount)
        itemCount = robot.count(1) --смотрим сколько палок в роботе
        if itemCount == 0 then --если палки в роботе кончились
            returnValue = false --возвращаем признак, что ПАЛКИ В РОБОТЕ И БОЧКЕ КОНЧИЛИСЬ
        elseif itemCount < cropsStackSize then --если после попытки взять палки из бочки, мы имеем меньше стака палок в роботе
            print("В бочке закончились палки!")
            computer.beep(1000,1)
            returnValue = true
        else
            returnValue = true
        end
        robot.turnLeft() --повернемся обратно к кропсам
    end
    return returnValue
end
function dropToChest() --все что есть в инвентори, скидываем в сундук
    --начальная позиция - P0 смотрим вверх
    robot.turnLeft()
    for i=2,16 do 
        item = component.inventory_controller.getStackInInternalSlot(i)
        if item then --если в слоте что-то есть
            robot.select(i)
            robot.drop() --сдаем все из текущего слота в сундук
        end
    end
    robot.turnRight() --поворачиваемся к с0
    robot.select(1)
end
function destroyAllDoubleCrops() --уничтожим все двойные кропсы
    --пройдемся по массиву статусов кропсов и у всех кропсов, у которых статус = "жердочки", съездим к ним и сломаем их
    for c=1,5 do
        if c_status[c] == "double crop" then
            robotGoTo_C_Crop_FromPark(c)
            robot.swingDown() --ломаем кропсы
            robotGoToPark(c)
        end
    end
    
end
function howInterestingIsThisCrop(c) --оценивает полезность нового растения сравнивая статы дочернего ростения [с] со статами материнский растений . тип растения во внимание не принимается
--возвращает: 0 - негодное
--            -1 - годно для сохранения
--            m - превосходит материнское, где 1<m<4 - номер материнского кропа, который нужно заменить новым растением 
 
    if c_grow[c] >= grow_kill then --если grow у дочернего растения достигло опасного значения, то это растение считаем негодным
        return 0
    end
    
    --если статы нового растения больше максимально разрешенных
    if (c_gain[c] > max_gain) or (c_grow[c] > max_grow) then
        --то считаем это растение приемлемым
        print("Полученое растение, превышает максимальные статы.")
        return -1
    end
 
    --сравним статы нового растения со статами материнских растений
    maxDifference = 0 --самая лучшая разница в качестве
    m_crop_maxDifference = 0 --материнский кроп с самой лучшей разницей в качестве
    for m = 1, 4 do
        --сравниваем статы полученного растения со статами материнских растений
        difference = (c_gain[c] + c_grow[c] - c_resistans[c]) - (m_gain[m] + m_grow[m] - m_resistans[m])
        if (difference > 0) and (difference > maxDifference) then --если растение лучше и это лучшая разница в качестве
            maxDifference = difference --обновим лучшую разницу в качестве
            m_crop_maxDifference = m --материнский кроп с самой лучшей разницей в качестве
        end
    end
    if maxDifference>0 then
        --полученное растение лучше чем одно из материнских, а значит нужно пересадить (на самый слабый материнский кроп)
        return m_crop_maxDifference --возвращаем материнский кроп с самой лучшей разницей в качестве
    end
    
    --если мы здесь, значит новое растение не привысило максимальные статы и не лучше чем материнские растения
    --а занчит   РАСТЕНИЕ ПЛОХОЕ
    return 0
 
end
function placeDoubleCrops() --ставит новые палки
    component.inventory_controller.equip() --экипируем кропсы(палки)
    robot.useDown() --ставим палку на землю
    robot.useDown() --ставим палку (получаются жердочки для скрещивания)
    component.inventory_controller.equip() --возвращаем в руки лопатку
end
function findSeedsInRobotInventory() --возвращает номер слота в инвентори робота с семечками, если нет семечек, то возвращает 0, а если вообще ничего нет, то возвращает -1
    foundAnything = false
    for i=2,16 do 
        item = component.inventory_controller.getStackInInternalSlot(i)
        if item then --если в слоте что-то есть
            foundAnything = true
            if item.name == "IC2:itemCropSeed" then --если в слоте семена
                return i --возвращаем номер слота, в котором семена
            end
        end
    end
    if foundAnything then --если что-то нашли (обычно это урожай), но семян не было
        return 0
    end
    return -1 --вообще ничего нет
end
function analizeAndProceed(c) --функция анализа и обработки кропа. с - номер кропа.
 
    
    analyze_result = geo.analyze(0) --анализируем блок под роботом 
    c_cropname[c] = get_crop_stat(analyze_result, "crop:name")
    if c_cropname[c] ~= nil then -- если перед нами что-то вывелось, а не пустые палки
        
        
        --получаем остальные статы кропа
        c_gain[c] = get_crop_stat(analyze_result, "crop:gain")
        c_grow[c] = get_crop_stat(analyze_result, "crop:grow")
        c_resistans[c] = get_crop_stat(analyze_result, "crop:resistance")
        c_size[c] = get_crop_stat(analyze_result, "crop:size")
        c_maxSize[c] = get_crop_stat(analyze_result, "crop:maxSize")
 
        if c_status[c] == "double crop" or c_status[c] == "unknown" then  --если статус растения был двойные палки, значит появилось новое растение
            print("Новый кроп С"..c..": "..c_cropname[c].."  "..c_grow[c].."  "..c_gain[c].."  "..c_resistans[c]) -- "Новый кроп С1:    reed"
            --print(c_grow[c], c_gain[c], c_resistans[c], "size: "..c_size[c].."/"..c_maxSize[c]) --"23   31   0   size: 2/3"
        end
        
        --если прокнуло растение другого вида, выкапываем его лопаткой и отвозим в сундук
        if c_cropname[c] ~= cropname then
            robot.useDown()--по умолчанию у нас в руках лопатка, юзаем ее
            component.inventory_controller.equip() --экипируем кропсы(палки)
            robot.useDown() --ставим палку (получаются жердочки для скрещивания)
            component.inventory_controller.equip() --возвращаем в руки лопатку
            c_status[c] = "double crop" --устанавливаем статус растения - жердочки
            
            --после копки проверим инвентори робота
            foundAnything = false
            for i=2,16 do 
                item = component.inventory_controller.getStackInInternalSlot(i)
                if item then --если в слоте что-то есть
                    foundAnything = true
                end
            end
            
            if foundAnything or robot.count(1) == 0 then --если что-то выкопалось от этого непрофильного растения или закончились палки
                robotGoToPark(c) --едем на парковку   
                if foundAnything then --если есть в инветори что-то выкопанное, сдаем в сундук
                    dropToChest()
                end
                --пополняем запас палок в роботе
                if grabCropsFromBarrel() then 
                else --если палки кончились
                    destroyAllDoubleCrops() --уничтожим все двойные кропсы
                    robot_error("ПАЛКИ КОНЧИЛИСЬ!") --заканчиваем работу с ошибкой
                end
                robotGoTo_C_Crop_FromPark(c)
            end
        else--если растение нужного типа
            if c_status[c] == "double crop" or c_status[c] == "unknown" then  --если статус растения был двойные палки, значит появилось новое растение
                --оценим полезность нового растения
                interest = howInterestingIsThisCrop(c)
                
                --выведем инфу о новом кропе
                interestString = ""
                if interest == 0 then
                    interestString = "негодное"
                elseif interest == -1 then
                    interestString = "годное, статы дошли до целевых"
                else
                    interestString = "превосходит материнское М"..interest
                end
                print("Полезность:"..interestString)
                
                if interest == 0 then -- растение с плохими статами
                    --уничтожаем растение
                    robot.swingDown() --ломаем кропсы
                    placeDoubleCrops() --ставим новые палки
                    c_status[c] = "double crop" --устанавливаем статус растения - жердочки
                    --посмотрим, попали ли семечки в инвентори
                    seedSlot = findSeedsInRobotInventory() --находим слот с семечками
                    if seedSlot > 0 then --если семечки есть
                        --отвезем эти семечки домой
                        robotGoToPark(c) --едем на парковку
                        dropToChest() --сбрасываем всё в сундук
                        grabCropsFromBarrel() --добираем палок из бочки
                        robotGoTo_C_Crop_FromPark(c) --возвращаемся на кроп
                    end
                else --растение со статами превышающими материнские или статы дошли до целевых
                    c_status[c] = "growing" --устанавливаем статус растущего кропа
                    --оставляем его в покое, пусть растет
                end
            
            else -- c_status[c] == "growing" --растение уже ранее сканировалось
                
                if c_size[c] == c_maxSize[c] then --если растение доросло
                    robot.swingDown() --ломаем кропсы, собираем урожай
                    placeDoubleCrops() --ставим новые палки
                    c_status[c] = "double crop" --устанавливаем статус растения - жердочки
                    
                    --посмотрим, попали ли семечки в инвентори
                    seedSlot = findSeedsInRobotInventory() --находим слот с семечками
                    if seedSlot > 0 then --если семечки есть
                        --делаем повторную оценку полезности
                        interest = howInterestingIsThisCrop(c)
                        if interest == -1 then --годное, статы дошли до целевых
                            --везем в сундук
                            robotGoToPark(c) --едем на парковку
                            dropToChest() --сбрасываем всё в сундук
                            grabCropsFromBarrel() --добираем палок из бочки
                            robotGoTo_C_Crop_FromPark(c) --возвращаемся на кроп
                            
                        elseif interest > 0 then --превосходит материнское
                            --меняем материнское ростение на текущее дочернее
                            print("Заменяем кроп М"..interest..":  "..m_grow[interest].."  "..m_gain[interest].."  "..m_resistans[interest].." -> "..c_grow[c].."  "..c_gain[c].."  "..c_resistans[c])
                            --обновляем статы материнского растения
                            m_grow[interest] = c_grow[c]
                            m_gain[interest] = c_gain[c]
                            m_resistans[interest] = c_resistans[c]
                            --едем менять материнское растение
                            robotGoToPark(c) --едем через паркинг. прямых маршрутов от С до M робот не знает
                            robotGoTo_M_Crop_FromPark(interest) --едем на материнский кропс, который будем менять
                            robot.swingDown() --ломаем кропсы, собираем урожай
                            component.inventory_controller.equip() --экипируем кропсы(палки)
                            robot.useDown() --ставим палку на землю
                            component.inventory_controller.equip() --возвращаем в руки лопатку
                            robot.select(seedSlot) --делаем активным слот с семенами, которые мы собираемся сажать
                            component.inventory_controller.equip() -- берем семена в руки
                            robot.useDown() --сажаем
                            component.inventory_controller.equip() -- берем обратно лопатку в руки
                            robot.select(1)
                            robotGoToParkFrom_M_Crop(interest) --едем на паркинг
                            dropToChest() --сбрасываем всё в сундук
                            grabCropsFromBarrel() --добираем палок из бочки
                            robotGoTo_C_Crop_FromPark(c) --возвращаемся на кроп
                        end
                    end
                end
            end
        end 
    else -- если перед нами или пустые палки или воздух
        if c_status[c] == "unknown" then -- если мы сканируем этот кроп впервые
            if get_crop_stat(analyze_result, "name") == "IC2:blockCrop" then --если перед нами двойные палки
                c_status[c] = "double crop"
            else --перед нами не растение и не двойные палки. значит перед нами воздух
                --ставим палки
                component.inventory_controller.equip() --экипируем кропсы(палки)
                robot.useDown() --ставим палку на землю
                robot.useDown() --ставим палку (получаются жердочки для скрещивания)
                component.inventory_controller.equip() --возвращаем в руки лопатку
                c_status[c] = "double crop" --устанавливаем статус растения - жердочки
            end
            
        end
        
    end 
 
end
----------------------------------------------------
--Шаг 1
--Начинаем работать 
print("--------------------------------------"); --выводим приветствие
print("Скрипт для робота, для поднятия статов у кропсов или разведения дубликатов запущен.");
print("Версия: "..ver)
if mode == 1 then -- 1 - режим поднятия статов кропсов
    print("Выбран режим поднятия статов кропсов.");
else -- 2 - режим разведения дубликатов кропсов
    print("Выбран режим разведения дубликатов кропсов.");
end
print("Шаг 1. Проверка входящих условий."); 
-- проверяем правильность входящий условий
--В руках должна быть лопатка
robot.select(1) --выбираем первый слот инвентори, на случай если при начале работы был выбран другой слот
component.inventory_controller.equip() --убираем лопатку к себе в инвентори и смотрим, лопатка ли это?
item = component.inventory_controller.getStackInInternalSlot(1)
if item == nil then --если в слоте ничего нет
    robot_error("Нет лопатки в слоте для инструмента!")
end
if item.name ~= "IC2:itemWeedingTrowel" then --если в слоте что-то есть, но это не лопатка berriespp:itemSpade
    robot_error("Нет лопатки в слоте для инструмента!")
end
component.inventory_controller.equip() --лопатку возвращаем в слот для инструмента
--print("Входящие условия соблюдены.")
----------------------------------------------------
--Шаг 2
if mode == 1 then -- 1 - режим поднятия статов кропсов
    print("Шаг 2. Сканируем материнские кропсы и запоминаем их статы.")
    --Сканируем материнские кропсы и запоминаем их статы
    --Исходная позиция - робот стоит на P0
    -- кроп M1
    robotMove_P0_M1()
    analyze_result = geo.analyze(0)
    cropname = get_crop_stat(analyze_result, "crop:name")
    m_gain[1] = get_crop_stat(analyze_result, "crop:gain")
    m_grow[1] = get_crop_stat(analyze_result, "crop:grow")
    m_resistans[1] = get_crop_stat(analyze_result, "crop:resistance")
    print("M1:", cropname, m_grow[1], m_gain[1], m_resistans[1])
    -- кроп M2
    robotMove_M1_M2()
    analyze_result = geo.analyze(0)
    cropname = get_crop_stat(analyze_result, "crop:name")
    m_gain[2] = get_crop_stat(analyze_result, "crop:gain")
    m_grow[2] = get_crop_stat(analyze_result, "crop:grow")
    m_resistans[2] = get_crop_stat(analyze_result, "crop:resistance")
    print("M2:", cropname, m_grow[2], m_gain[2], m_resistans[2])
    -- кроп M3
    robotMove_M2_M3()
    analyze_result = geo.analyze(0)
    cropname = get_crop_stat(analyze_result, "crop:name")
    m_gain[3] = get_crop_stat(analyze_result, "crop:gain")
    m_grow[3] = get_crop_stat(analyze_result, "crop:grow")
    m_resistans[3] = get_crop_stat(analyze_result, "crop:resistance")
    print("M3:", cropname, m_grow[3], m_gain[3], m_resistans[3])
    -- кроп M4
    robotMove_M3_M4()
    analyze_result = geo.analyze(0)
    cropname = get_crop_stat(analyze_result, "crop:name")
    m_gain[4] = get_crop_stat(analyze_result, "crop:gain")
    m_grow[4] = get_crop_stat(analyze_result, "crop:grow")
    m_resistans[4] = get_crop_stat(analyze_result, "crop:resistance")
    print("M4:", cropname, m_grow[4], m_gain[4], m_resistans[4])
    robotMove_M4_P0() --возвращаем робота в исходное положение
end
----------------------------------------------------
--Шаг 3
if mode == 1 then -- 1 - режим поднятия статов кропсов
    print("Шаг 3. Приступаем к поднятию статов.");
else -- 2 - режим разведения дубликатов кропсов
    print("Шаг 2. Приступаем к разведению дубликатов кропсов.");
end
 
while true do --главный цикл
    --пополняем запас палок в роботе
    if grabCropsFromBarrel() then 
    else --если палки кончились
        destroyAllDoubleCrops() --уничтожим все двойные кропсы
        robot_error("ПАЛКИ КОНЧИЛИСЬ!")
    end
    --едем сканить дочерние кропсы
    robotMove_P0_C1()
    analizeAndProceed(1)
    robotMove_C1_C4()
    analizeAndProceed(4)
    robotMove_C4_C5()
    analizeAndProceed(5)
    robotMove_C5_C2()
    analizeAndProceed(2)
    robotMove_C2_C3()
    analizeAndProceed(3)
    robotMove_C3_P0() --конечное положение P0 смотрим вверх
    --os.exit()    
    os.sleep(15)
end
 
os.exit()
--История версий:
--Версия 1.1.3
--Устранена уязвимость к коллизиям. Нахождение игрока на пути следования робота больше не приводит к потере роботом маршрута. Робот после столкновения с игроком замирает на секунду, после чего продолжает попытку движения
--Добавлена история версий в файл скрипта робота
