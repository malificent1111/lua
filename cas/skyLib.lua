local component = require("component")
local computer=require("computer")
local serial = require("serialization")
local term = require("term")
local event = require("event")
local unicode = require("unicode")
local fs = require("filesystem")
local internet = require("internet")
local bit32 = require("bit32")

local sky = {}
local g = component.gpu

------------------------------[ Графика ] ------------------------------
--░▒▓█▀▄┌─┐└─┘│┤├
--ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ
--ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ
--０１２３４５６７８９
--＊｜（）＃％＝［］｛｝＜＞＼／：；！？．，～＂｀＄｟｠

function sky.mid(width,y,text) --Центровка
	--local _,n = string.gsub(text, "&","")
	local l = unicode.len(sky.getOnlyText(text)) -- - n * 2
	local x = (width / 2) - (l / 2) + 1
	sky.text(math.floor(x), y, text)
end

function sky.drawImage(x,y,path) --Отрисовка картинок
	local back, font = g.getBackground(), g.getForeground()
	if (fs.exists(path)) then
		local start_x = x
		local text = "{" .. sky.fileRead(path) .. "}"
		local image = serial.unserialize(text)
		for i = 1, #image / 2 do
			x = start_x
			for j = 1, #image[i] do
				
				if sky.convert24BitTo8Bit(image[i * 2 - 1][j]) == sky.convert24BitTo8Bit(image[i * 2][j]) then
					g.setBackground(image[i * 2 - 1][j])
					g.set(x,y," ")
				else
					g.setBackground(image[i * 2 - 1][j])
					g.setForeground(image[i * 2][j])
					g.set(x,y,"▄")
				end
				x = x + 1
			end
			y = y + 1
		end
	end
	g.setBackground(back)
	g.setForeground(font)
end

function sky.money(nick) --Баланс игрока 
	local c = sky.com("money " .. nick)
	local _, b = string.find(c, "Баланс: §f")
	local balance
	if b == nil then 
		balance = "0.00"
	elseif string.find(c, "Emeralds") ~= nil then
		balance = unicode.sub(c, b - 16, unicode.len(c) - 10)
	else
		balance = unicode.sub(c, b - 16, unicode.len(c) - 9)
	end	
	return (balance)
end

function sky.checkMoney(nick,price) --Чекнуть, баланс, если хватает, то снять бабки
	local balance = sky.money(nick)
	balance = string.sub(balance, 1, string.len(balance) - 3)
	if string.find(balance, "-") ~= nil then
		return false
	else
		balance = string.gsub(balance,",","")
		if tonumber(balance) < price then
			return false
		else
			sky.com("money take " .. nick .. " " .. price)
			return true
		end
	end
end

function sky.clear(w,h) --Очистка всего, кроме рамки
	g.fill(3,2,w-4,h-2," ")
end

function sky.logo(name,col1,col2,w,h,offset) --Рамка P.S. Луфф питух
	term.clear()
	g.setBackground(0x000000)
	g.setForeground(col2)
	for i = 1, w do
		g.set(i,1,"=")
		g.set(i,h,"=")
	end
	for i = 1, h do
		g.set(1, i, "||")
		g.set(w-1, i, "||")
	end
	if offset == nil then
		offset = 0
	end
	if name ~= nil or name ~= "" then
		local x = (w / 2) - (unicode.len("[ " .. name .. " ]") / 2) + offset + 1
		sky.text(math.floor(x), 1, "[ " .. name .. " ]")
	end
	g.set(w-20, h, "[ A: SkyDrive_ ]")
	g.setForeground(col1)
	if name ~= nil or name ~= "" then
		local x = (w / 2) - (unicode.len(name) / 2) + offset + 1
		g.set(math.floor(x), 1, name)
	end
	g.set(w-18, h, "A: SkyDrive_")
end

function sky.setColor(index) --Список цветов
	if (index ~= "r") then back = g.getForeground() end
	if (index == "0") then g.setForeground(0x333333) end
	if (index == "1") then g.setForeground(0x0000ff) end
	if (index == "2") then g.setForeground(0x00ff00) end
	if (index == "3") then g.setForeground(0x24b3a7) end
	if (index == "4") then g.setForeground(0xff0000) end
	if (index == "5") then g.setForeground(0x8b00ff) end
	if (index == "6") then g.setForeground(0xff8700) end
	if (index == "7") then g.setForeground(0xbbbbbb) end
	if (index == "8") then g.setForeground(0x808080) end
	if (index == "9") then g.setForeground(0x007fff) end
	if (index == "a") then g.setForeground(0x66ff66) end
	if (index == "b") then g.setForeground(0x00ffff) end
	if (index == "c") then g.setForeground(0xff3333) end
	if (index == "d") then g.setForeground(0xff00ff) end
	if (index == "e") then g.setForeground(0xffff00) end
	if (index == "f") then g.setForeground(0xffffff) end
	if (index == "g") then g.setForeground(0x00ff00) end
	if (index == "r") then g.setForeground(back) end
end

function sky.textOLD(x,y,text) --Цветной текст
	local n = 1
	for i = 1, unicode.len(text) do
		if unicode.sub(text, i,i) == "&" then
			sky.setColor(unicode.sub(text, i + 1, i + 1))
		elseif unicode.sub(text, i - 1, i - 1) ~= "&" then
			g.set(x+n,y, unicode.sub(text, i,i))
			n = n + 1
		end
	end
end

--Костыльная замена обычному string.find()
--Работает медленнее, но хотя бы поддерживает юникод
function unicode.find(str, pattern, init, plain)
	if init then
		if init < 0 then
			init = -#unicode.sub(str,init)
		elseif init > 0 then
			init = #unicode.sub(str,1,init-1)+1
		end
	end
	
	a, b = string.find(str, pattern, init, plain)
	
	if a then
		local ap,bp = str:sub(1,a-1), str:sub(a,b)
		a = unicode.len(ap)+1
		b = a + unicode.len(bp)-1
		return a,b
	else
		return a
	end
end

function sky.text(x,y,text) --Цветной текст

	local f = unicode.find(text, "&.")
	if f == nil then
		g.set(x,y,text)
	else
		if f ~= 1 then
			g.set(x,y, unicode.sub(text, 1, f-1))
			text = unicode.sub(text, f, unicode.len(text))
		end
		
		for s in string.gmatch(text, "&.") do
			sky.setColor(unicode.sub(text, 2, 2))
			text = unicode.sub(text, 3, unicode.len(text))
			
			x = x + f - 1
			
			local f2 = unicode.find(text, "&.")
			if f2 ~= nil then
				g.set(x, y, unicode.sub(text, 1, f2-1))
				text = unicode.sub(text, f2, unicode.len(text))
				f = f2
			else
				g.set(x, y, unicode.sub(text, 1, unicode.len(text)))
			end
			
		end
	end
end

function sky.getOnlyText(text) --Удалить цветовые коды
	return text:gsub("&.", "")
end

function sky.button(x,y,w,h,col1,col2,text) -- Кнопка
	g.setForeground(col1)
	g.set(x + w/2 - unicode.len(text)/2, y+h/2, text)
	g.setForeground(col2)
	for i = 1, w-2 do
		g.set(x+i,y,"─")
		g.set(x+i,y+h-1,"─")
	end
	for i = 1, h-2 do
		g.set(x,y+i,"│")
		g.set(x+w-1,y+i,"│")
	end
	g.set(x,y,"┌")
	g.set(x+w-1,y,"┐")
	g.set(x,y+h-1,"└")
	g.set(x+w-1,y+h-1,"┘")
end

function sky.takeItem(nick, item, numb) --Забрать итем
	if string.find(sky.com("clear " .. nick .. " " .. item .. " " .. numb), "Убрано") ~= nil then
		return true
	else
		return false
	end
end

function sky.fileRead(path) --Чтение файла
	local file = io.open(path, "r")
	if file == nil then
		return nil
	end
	local text = file:read("*a")
	file:close()
	return text
end

function sky.fileWrite(path, text, mode) --Запись в файл. Моды: w - перезапись файла, a - запись в конец файла
	if mode == nil then
		mode = "w"
	end
	local file = io.open(path, mode)
	if file ~= nil then
		file:write(tostring(text) .. "\n")
		file:close()
	end
end

function sky.giveItem(nick, item, numb) --Выдать предмет и чекнуть влезло ли в инвентарь, если нет, вернуть остаток
	local text = sky.com("egive " .. nick .. " " .. item .. " " .. numb)

	if string.find(text, "Недостаточно свободного места") ~= nil then
		local _, b = string.find(text, "Недостаточно свободного места, §c")
		if b == nil then
			return 0
		end
		
		local i = 0
		local ostatok = ""
		while (ostatok ~= " ") do
			i = i + 1
			ostatok = string.sub(text, b+i, b+i)
		end
		ostatok = string.sub(text, b+1, b+i-1)
		ostatok = string.gsub(ostatok,",","")
		return ostatok
	else
		return 0
	end
end

function sky.com(command) --Выполнить команду
	if (component.isAvailable("opencb")) then
		local _,c = component.opencb.execute(command)
		return c
	end
end

function sky.mathRound(roundIn , roundDig) --Округлить число
	local mul = math.pow(10, roundDig)
	return ( math.floor(( roundIn * mul) + 0.5)/mul)
end

function sky.swap(array, index1, index2) --Свап
	array[index1], array[index2] = array[index2], array[index1]
end

function sky.shake(array) --Шафл
	local counter = #array
	while counter > 1 do
		local index = math.random(counter)
		sky.swap(array, index, counter)
		counter = counter - 1
	end
end

function sky.get(url, filename,x,y) --Получить поток
	local f, reason = io.open(filename, "w")
	if not f then
		g.set(x,y,"         Ошибка чтения файла         ")
		os.sleep(2)
		return
	end
 
	g.set(x,y,"          Идёт скачивание...         ")
	os.sleep(2)
	local result, response = pcall(internet.request, url)
	if result then
		g.set(x,y,"        Файл успешно загружен        ")
		os.sleep(2)
		for chunk in response do
			f:write(chunk)
		end
		f:close()
	else
		f:close()
		fs.remove(filename)
		g.set(x,y,"   HTTP запрос не дал результатов    ")
		os.sleep(2)
	end
end

function sky.run(url, ...) --Запуск и удаление файла
	local tmpFile = os.tmpname()
	sky.read(url, tmpFile)
	term.clear() -- <=== Очистка экрана перед запуском проги, если чё, она тута
	local success, reason = shell.execute(tmpFile, nil, ...)
	if not success then
		--mid(23,"             Битый файлик             ")
		--os.sleep(2)
	end
	fs.remove(tmpFile)
end

function sky.checkOP(nick) --Чек на опку
	local c = sky.com("whois " .. nick)
	local _, b = string.find(c, "OP:§r ")
	local text = string.sub(c, b+1, string.find(c, "Режим полета:"))
	if string.find(text, "§aистина§r") ~= nil then
		return true
	else
		return false
	end
end

function sky.playtime(nick) --Плейтайм
	local c = sky.com("playtime " .. nick)
	local _, b = string.find(c, "на сервере ")
	local text = ""
	if b == nil then 
		text = "error"
	elseif string.find(c, "час") then
		text = string.sub(c, b+1, string.find(c, " час")) .. " ч."
	else
		text = string.sub(c, b+1, string.find(c, " минут")) .. " мин."
	end
	return text
end

function sky.checkMute(nick) --Чекнуть висит ли мут
	local c = sky.com("checkban " .. nick)
	if string.find(c, "Muted: §aFalse") ~= nil then
		return false
	else
		return true
	end
end

function sky.getHostTime(timezone) --Получить текущее реальное время компьютера, хостящего сервер майна
	timezone = timezone or 0
	sky.fileWrite("/HostTime.tmp", "123")
	local timeCorrection = timezone * 3600
	local lastModified = tonumber(string.sub(fs.lastModified("/HostTime.tmp"), 1, -4)) + timeCorrection
	fs.remove("HostTime.tmp")
	local year, month, day, hour, minute, second = os.date("%Y", lastModified), os.date("%m", lastModified), os.date("%d", lastModified), os.date("%H", lastModified), os.date("%M", lastModified), os.date("%S", lastModified)
	
	return day, month, year, hour, minute, second
end

function sky.time(timezone) --Получет настоящее время, стоящее на Хост-машине
	local time = {sky.getHostTime(timezone)}
	local text = string.format("%02d:%02d:%02d", time[4], time[5], time[6])
	return text
end

function sky.hex(Hcolor) --Конвертация Dec в Hex
	local hex = "000000" .. string.format('%x', Hcolor)
	hex = string.sub(hex, unicode.len(hex)-5, unicode.len(hex))
	return hex
end

function sky.dec(Dcolor) --Конвертация Hex в Dec
	if Dcolor == "" then
		Dcolor = "ffffff"
	end
	local dec = string.format('%d', '0x'.. Dcolor)
	return tonumber(dec)
end

function sky.TF(value) --Если false, то вернёт true и наоборот
	if value then
		return false
	end
	return true
end

function sky.drawMenu(w, h, color)
	
	local WIDTH, HEIGHT = g.getResolution()
	
	if color == nil then
		color = 0x333333
	end
	if returnOld == nil then
		returnOld = false
	end

	local y = math.ceil(HEIGHT / 2 - h / 2)

	g.setForeground(color)
	local lineTop = "┌─────"
	local lineMid = "│     "
	local lineBottom = "└─────"
	for i = 1, w do
		lineTop = lineTop .. "─"
		lineMid = lineMid .. " "
		lineBottom = lineBottom .. "─"
	end
	lineTop = lineTop .. "─────┐"
	lineMid = lineMid .. "     │"
	lineBottom = lineBottom .. "─────┘"
	
	local l = unicode.len(sky.getOnlyText(lineTop)) -- - n * 2
	local x = (WIDTH / 2) - (l / 2)
		
	sky.mid(WIDTH, y - 1, lineTop)
	for i = 0, h + 1 do
		sky.mid(WIDTH, y + i, lineMid)
	end
	sky.mid(WIDTH, y + h + 2, lineBottom)
	
end

--Обычный квадрат указанного цвета
function sky.square(x,y,w,h,color)
	g.setForeground(color)
	g.fill(x,y,w,h,"█")
end

--Всплывающее меню с выбором элемента массива
function sky.selectMenu(mass, settings)

	local WIDTH, HEIGHT = g.getResolution()

	if settings == nil then
		settings = {}
	end

	if settings.color1 == nil then --Цвет кнопки "Ок"
		settings.color1 = 0x7fff00
	end
	
	if settings.color2 == nil then --Цвет рамки
		settings.color2 = 0x333333
	end

	if settings.offsetL == nil then --Удаление текста слева
		settings.offsetL = 0
	end

	if settings.offsetR == nil then --Удаление текста справа
		settings.offsetR = 0
	end
		
	if settings.ok == nil then --Выбор по клику на кнопку "Ок" или по клику на элемент
		settings.ok = true
	end
	
	--menuName - название меню, отображающееся сверху

	local wMass = 0
	
	for i = 1, #mass do
		if wMass < unicode.len(tostring(mass[i])) then
			wMass = unicode.len(tostring(mass[i])) - (settings.offsetL + settings.offsetR)
			wMass = math.ceil(wMass / 2) * 2
		end
	end
	
	local xMass = math.ceil(WIDTH / 2 - wMass / 2)
	local yMass = math.ceil(HEIGHT / 2 - #mass / 2)
	
	sky.drawMenu(wMass, #mass, settings.color2)
	
	if settings.menuName ~= nil then
		sky.mid(WIDTH, yMass - 1, "[ " .. settings.menuName	.. " &r]")
	end
	
	if settings.ok then
		sky.mid(WIDTH, yMass + #mass + 2, "[ Ок ]")
	end	
	
	for i = 1, #mass do
		sky.mid(WIDTH, yMass + i, string.sub(mass[i], 1 + settings.offsetL, string.len(mass[i]) - settings.offsetR))
	end
	
	local index
	
	while true do
	
		local e,_,w,h = event.pull("touch")
		
		if h > yMass and h <= yMass + #mass and w >= xMass and w <= xMass + wMass then
			index = mass[h - yMass]
			if not settings.ok then
				return index
			end
			for i = 1, #mass do
				if index == mass[i] then
					sky.mid(WIDTH, yMass + i, "&2▸▸ " .. string.sub(mass[i], 1 + settings.offsetL, string.len(mass[i]) - settings.offsetR) .. " &2◂◂")
				else
					sky.mid(WIDTH, yMass + i, "   " .. string.sub(mass[i], 1 + settings.offsetL, string.len(mass[i]) - settings.offsetR) .. "   ")
				end
			end
		elseif index ~= nil and h == yMass + #mass + 2 and w > WIDTH / 2 - 1 and w <= WIDTH / 2 + 1 then
			return index
		elseif settings.ok then
			index = nil
			for i = 1, #mass do
				sky.mid(WIDTH, yMass + i, "   " .. string.sub(mass[i], 1 + settings.offsetL, string.len(mass[i]) - settings.offsetR) .. "   ")
			end
		end
		
		if settings.ok then
			if index ~= nil then
				g.setForeground(settings.color1)
			else
				g.setForeground(settings.color2)
			end
			sky.mid(WIDTH, yMass + #mass + 2, "Ок")
		end
	end
end

--Конвертация из HEX в RGB
function sky.HEXtoRGB(color)
 return bit32.rshift(color, 16), bit32.band(bit32.rshift(color, 8), 0xFF), bit32.band(color, 0xFF)
end

--Конвертация из RGB в HEX
function sky.RGBtoHEX(rr, gg, bb)
 return bit32.lshift(rr, 16) + bit32.lshift(gg, 8) + bb
end

local palette = {}
 
for r = 0, 5 do
  for g = 0, 7 do
    for b = 0, 4 do
      table.insert(palette, sky.RGBtoHEX(r * 0x33, g * 0x24, math.floor(b / 4 * 0xFF + 0.5))) --СИНИЙ, ПРЕКРАТИ
    end
  end
end
for gr = 1, 0x10 do --Градации серого
  table.insert(palette, gr * 0xF0F0F) --Нет смысла использовать colorlib.RGBtoHEX()
end
table.sort(palette)

--Конвертация в 8-битный цвет
function sky.convert24BitTo8Bit(hex24)
  local encodedIndex = nil
  local colorMatchFactor = nil
  local colorMatchFactor_min = math.huge
 
  local red24, green24, blue24 = sky.HEXtoRGB(hex24)
 
  for colorIndex, colorPalette in ipairs(palette) do
    local redPalette, greenPalette, bluePalette = sky.HEXtoRGB(colorPalette)
 
    colorMatchFactor = (redPalette-red24)^2 + (greenPalette-green24)^2 + (bluePalette-blue24)^2
 
    if (colorMatchFactor < colorMatchFactor_min) then
      encodedIndex = colorIndex
      colorMatchFactor_min = colorMatchFactor
    end
  end
   
  return encodedIndex - 1
  -- return searchClosestColor(1, #palette, hex24)
end

--Конфиг
function sky.settingsMenu(settings)
	--mode 1=label, 2=switch, 3=resolution
	--{x = 1, y = 1, mode = 1, label = "Ник: ", value = "SkyDrive_"}

	local widthConfig, heightConfig	= 0, 0
	local WIDTH, HEIGHT	= g.getResolution()
	
	local MIN_RESOLUTION = {X = 88, Y = 25} --Минимальное разрешение монитора
	local MAX_RESOLUTION = {X = 160, Y = 50} --Максимальное разрешение монитора
	
	for i = 1, #settings do	
		
		local maxL = 4
		if settings[i].maxL ~= nil then
			maxL = settings[i].maxL
		end
		
		local widthString = 0
		if settings[i].label ~= nil then
			widthString = unicode.len(settings[i].label) + maxL + 4
		end
		
		if widthConfig < widthString then
			widthConfig = widthString
		end
		
		heightConfig = heightConfig + 2
	end
		
	sky.drawMenu(widthConfig-1, heightConfig-1)
	
	local xMass = math.ceil(WIDTH/2 - widthConfig/2)
	local yMass = math.ceil(HEIGHT/2 - heightConfig/2 - 1)
	sky.mid(WIDTH, yMass + heightConfig + 2, "&0[ &2Сохранить &0]")
	
	local function drawValues()
		for i = 1, #settings do
			
			g.setForeground(0x00ffff)
			sky.text(xMass, yMass + i*2, settings[i].label)
			
			if settings[i].mode == 1 then
				
			elseif settings[i].mode == 2 then
			
				sky.drawSwitch(xMass + widthConfig - 2, yMass + i*2, settings[i].value)
				
			elseif settings[i].mode == 3 then
				local lenX = unicode.len(tostring(settings[i].x))
				local lenY = unicode.len(tostring(settings[i].y))
				
				sky.text(xMass + widthConfig - (lenX+lenY+7), yMass + i*2, " &0[ &2" .. settings[i].x .. " &0x &2" .. settings[i].y .. " &0]") --Пробел в начале для очистки 160 -> _80
			end
			
		end
	end
	
	drawValues()
	
	while true do
		local e,_,w,h = event.pull("touch")
		for i = 1, #settings do
			
			if h == yMass + i*2 then
				if settings[i].mode == 1 then
					print("Нада дописывать(9")
				elseif settings[i].mode == 2 and w >= xMass + widthConfig - 2 and w < xMass + widthConfig + 2 then
					if settings[i].value then
						settings[i].value = false
					else
						settings[i].value = true
					end
				elseif settings[i].mode == 3 then
								
					local lenX = unicode.len(tostring(settings[i].x))
					local lenY = unicode.len(tostring(settings[i].y))
					local xButton = xMass + widthConfig - (lenX+lenY+3) 
					local yButton = yMass + i*2
				
					if sky.pressButton(w,h,{xButton, yButton, lenX, 1}) then --Разрешение: X
						g.setForeground(0x00ff00)
						local xRes = sky.read({x = xButton, y = yButton, text = tostring(settings[i].x), max = 3, accept = "[0-9]"})
						if xRes ~= "" then
							xRes = tonumber(xRes)
							if xRes < MIN_RESOLUTION.X then
								settings[i].x = MIN_RESOLUTION.X
							elseif xRes > MAX_RESOLUTION.X then
								settings[i].x = MAX_RESOLUTION.X
							else
								settings[i].x = xRes
							end
						end
					elseif sky.pressButton(w,h,{xButton+lenX+3, yButton, lenY, 1}) then --Разрешение: Y
						g.setForeground(0x00ff00)
						local yRes = sky.read({x = xButton+lenX+3, y = yButton, text = tostring(settings[i].y), max = 2, accept = "[0-9]"})
						if yRes ~= "" then
							yRes = tonumber(yRes)
							if yRes < MIN_RESOLUTION.Y then
								settings[i].y = MIN_RESOLUTION.Y
							elseif yRes > MAX_RESOLUTION.Y then
								settings[i].y = MAX_RESOLUTION.Y
							else
								settings[i].y = yRes
							end
						end
					end
				end
			end
		
		end
		
		if h == yMass + heightConfig + 2 and w >= WIDTH/2-4 and w < WIDTH/2+5 then --[ Сохранить ]
			return settings
		end
		
		drawValues()
	end
	
end

--Палитра
function sky.palitra(col)
	local OldColor = g.getForeground()
	if col ~= nil then
		OldColor = col
		NewColor = col
	end
	local NewColor = g.getForeground()
	local x,y = g.getResolution()
	x = x/2-14
	y = y/2-5
	local palitra = {
	{0x9b2d30, 0xff0000, 0xff9900, 0xffff00},
	{0x66ff00, 0x008000, 0x00ffff, 0x0000ff},
	{0x00cccc, 0x8b00ff, 0xff00ff, 0xf78fa7},
	{0x666666, 0x222222, 0xffffff},
	}

	g.setForeground(0x333333)

	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█                █ ██████ █")
	g.set(x,y+2,"█                █ ██████ █")
	g.set(x,y+3,"█                █▄▄▄▄▄▄▄▄█")
	g.set(x,y+4,"█                █        █")
	g.set(x,y+5,"█                █        █")
	g.set(x,y+6,"█                █        █")
	g.set(x,y+7,"█                █   Ок   █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█▄▄▄▄▄▄▄▄█")

	for i = 1, #palitra do
		for j = 1, #palitra[i] do
			g.setForeground(palitra[i][j])
			g.set(j*4-4+x+2,i*2-2+y+1, "██")
		end
	end

	g.setForeground(OldColor)
	g.set(x+19,y+1,"██████")
	g.set(x+19,y+2,"██████")
	g.set(x+19, y+5, sky.hex(OldColor))

	while true do
		local e,_,w,h = event.pull("touch")
		if e == "touch" then
			for i = 1, #palitra do
				for j = 1, #palitra[i] do
					if w>=j*4-4+x+2 and w<=j*4-4+x+3 and h==i*2-2+y+1 then
						NewColor = palitra[i][j]
						g.setForeground(NewColor)
						g.set(x+19,y+1,"██████")
						g.set(x+19,y+2,"██████")
						g.set(x+19, y+5, sky.hex(NewColor))
					end
				end
			end
			if w>=x+19 and w<=x+24 and h==y+5 then
				g.set(x+19,y+5,"      ")
				term.setCursor(x+19,y+5)
				NewColor = sky.read({max = 6, accept = "0-9a-f", blink = true})
				NewColor = sky.dec(NewColor)
				g.setForeground(NewColor)
				g.set(x+19,y+1,"██████")
				g.set(x+19,y+2,"██████")
				g.set(x+19, y+5, sky.hex(NewColor))
			elseif w>=x+21 and w<=x+22 and h==y+7 then
				g.setForeground(OldColor)
				g.fill(x,y,x+26,y+8," ")
				return NewColor
			end
		end
	end
end

function sky.pressButton(Pw,Ph,mass) --Проверка нажатия кнопки
	local x,y,w,h = mass[1], mass[2], mass[3], mass[4]
	if Pw>=x and Pw<=x+w-1 and Ph>=y and Ph<=y+h-1 then
		return true
	end
	return false
end

function sky.drawButton(mass) --Отрисовка кнопки
	local x,y,w,h,text,col1,col2 = mass[1], mass[2], mass[3], mass[4], mass[5], mass[6], mass[7]
	g.fill(x,y,w,h," ")
	g.setForeground(col1)
	g.set(x + w/2 - unicode.len(text)/2, y+h/2, text)
	g.setForeground(col2)
	for i = 1, w-2 do
		g.set(x+i,y,"─")
		g.set(x+i,y+h-1,"─")
	end
	for i = 1, h-2 do
		g.set(x,y+i,"│")
		g.set(x+w-1,y+i,"│")
	end
	g.set(x,y,"┌")
	g.set(x+w-1,y,"┐")
	g.set(x,y+h-1,"└")
	g.set(x+w-1,y+h-1,"┘")
end

function sky.pressSwitch(w,h,x,y)
	if w >= x and w < x+4 and h == y then
		return true
	end
	return false
end

function sky.drawSwitch(x,y,value) --Свич
	g.setForeground(0x111111)
	g.set(x,y, "████")
	if value == true then
		g.setForeground(0x7fff00)
		g.set(x+2,y,"██")
	else
		g.setForeground(0x003300)
		g.set(x,y, "██")
	end
end

--Запомнить область пикселей и возвратить ее в виде массива
function sky.rememberOldPixels(x, y, x2, y2)
	local newPNGMassiv = { ["backgrounds"] = {} }
	newPNGMassiv.x, newPNGMassiv.y = x, y

	--Перебираем весь массив стандартного PNG-вида по высоте
	local xCounter, yCounter = 1, 1
	for j = y, y2 do
		xCounter = 1
		for i = x, x2 do
			local symbol, fore, back = g.get(i, j)

			newPNGMassiv["backgrounds"][back] = newPNGMassiv["backgrounds"][back] or {}
			newPNGMassiv["backgrounds"][back][fore] = newPNGMassiv["backgrounds"][back][fore] or {}

			table.insert(newPNGMassiv["backgrounds"][back][fore], {xCounter, yCounter, symbol} )

			xCounter = xCounter + 1
			back, fore, symbol = nil, nil, nil
		end

		yCounter = yCounter + 1
	end

	return newPNGMassiv
end
 
--Нарисовать запомненные ранее пиксели из массива
function sky.drawOldPixels(massivSudaPihay)
	--Перебираем массив с фонами
	for back, backValue in pairs(massivSudaPihay["backgrounds"]) do
		g.setBackground(back)
		for fore, foreValue in pairs(massivSudaPihay["backgrounds"][back]) do
			g.setForeground(fore)
			for pixel = 1, #massivSudaPihay["backgrounds"][back][fore] do
				if massivSudaPihay["backgrounds"][back][fore][pixel][3] ~= transparentSymbol then
					g.set(massivSudaPihay.x + massivSudaPihay["backgrounds"][back][fore][pixel][1] - 1, massivSudaPihay.y + massivSudaPihay["backgrounds"][back][fore][pixel][2] - 1, massivSudaPihay["backgrounds"][back][fore][pixel][3])
				end
			end
		end
	end
end


function sky.word(x,y,text,ramka) --Шрифт
	text = unicode.lower(text)
	for i = 1, unicode.len(text) do
		sky.symbol(i*8-8 + x, y, string.sub(text,i,i), ramka)
	end
end

function sky.symbol(x,y,symbol,ramka) --Символы шрифта
	local WBack = g.getBackground()
	
	if ramka ~= nil then
		local WColor = g.getForeground()
		g.setForeground(ramka)
		g.set(x,y,  "███████")
		g.set(x,y+1,"███████")
		g.set(x,y+2,"███████")
		g.set(x,y+3,"▀▀▀▀▀▀▀")
		g.setBackground(ramka)
		g.setForeground(WColor)
	end
	
	symbol = string.lower(symbol)
	
	if symbol == "a" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█▄▄▄█")
		g.set(x+1,y+2,"█   █")
	elseif symbol == "b" then
		g.set(x+1,y,  "▄▄▄▄")
		g.set(x+1,y+1,"█▄▄█▄")
		g.set(x+1,y+2,"█▄▄▄█")
	elseif symbol == "c" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█")
		g.set(x+1,y+2,"█▄▄▄▄")
	elseif symbol == "d" then
		g.set(x+1,y,  "▄▄▄▄")
		g.set(x+1,y+1,"█   █")
		g.set(x+1,y+2,"█▄▄▄▀")
	elseif symbol == "e" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█▄▄▄")
		g.set(x+1,y+2,"█▄▄▄▄")
	elseif symbol == "f" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█▄▄")
		g.set(x+1,y+2,"█")
	elseif symbol == "g" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█  ▄▄")
		g.set(x+1,y+2,"█▄▄▄█")
	elseif symbol == "h" then
		g.set(x+1,y,  "▄   ▄")
		g.set(x+1,y+1,"█▄▄▄█")
		g.set(x+1,y+2,"█   █")
	elseif symbol == "i" then
		g.set(x+2,y,  "▄▄▄")
		g.set(x+2,y+1," █")
		g.set(x+2,y+2,"▄█▄")
	elseif symbol == "j" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"    █")
		g.set(x+1,y+2,"█▄▄▄█")
	elseif symbol == "k" then
		g.set(x+1,y,  "▄  ▄")
		g.set(x+1,y+1,"█▄▀")
		g.set(x+1,y+2,"█ ▀▄")
	elseif symbol == "l" then
		g.set(x+1,y,  "▄")
		g.set(x+1,y+1,"█")
		g.set(x+1,y+2,"█▄▄▄")
	elseif symbol == "m" then
		g.set(x+1,y,  "▄   ▄")
		g.set(x+1,y+1,"█▀▄▀█")
		g.set(x+1,y+2,"█   █")
	elseif symbol == "n" then
		g.set(x+1,y,  "▄▄  ▄")
		g.set(x+1,y+1,"█ █ █")
		g.set(x+1,y+2,"█  ▀█")
	elseif symbol == "o" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█   █")
		g.set(x+1,y+2,"█▄▄▄█")
	elseif symbol == "p" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█▄▄▄█")
		g.set(x+1,y+2,"█")
	elseif symbol == "q" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█   █")
		g.set(x+1,y+2,"█▄▄██")
	elseif symbol == "r" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█▄▄▄█")
		g.set(x+1,y+2,"█  ▀▄")
	elseif symbol == "s" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"█▄▄▄▄")
		g.set(x+1,y+2,"▄▄▄▄█")
	elseif symbol == "t" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1,"  █")
		g.set(x+1,y+2,"  █")
	elseif symbol == "u" then
		g.set(x+1,y,  "▄   ▄")
		g.set(x+1,y+1,"█   █")
		g.set(x+1,y+2,"▀▄▄▄▀")
	elseif symbol == "v" then
		g.set(x+1,y,  "▄   ▄")
		g.set(x+1,y+1,"█   █")
		g.set(x+1,y+2," ▀▄▀")
	elseif symbol == "w" then
		g.set(x+1,y,  "▄   ▄")
		g.set(x+1,y+1,"█ █ █")
		g.set(x+1,y+2,"▀▄█▄▀")
	elseif symbol == "x" then
		g.set(x+1,y,  "▄   ▄")
		g.set(x+1,y+1," ▀▄▀")
		g.set(x+1,y+2,"▄▀ ▀▄")
	elseif symbol == "y" then
		g.set(x+1,y,  "▄   ▄")
		g.set(x+1,y+1," ▀▄▀ ")
		g.set(x+1,y+2,"  █")
	elseif symbol == "z" then
		g.set(x+1,y,  "▄▄▄▄▄")
		g.set(x+1,y+1," ▄▄▄▀")
		g.set(x+1,y+2,"█▄▄▄▄")
	end
	g.setBackground(WBack)
end

function sky.read(settings) --Считывание вводимого текста

	if not settings then
		settings = {}
	end
	
	if not settings.x or not settings.y then --Корды
		settings.x, settings.y = term.getCursor()
	end
	
	if not settings.text then --Текст
		settings.text = ""
	end

	if not settings.max then --Макс. длина
		settings.max = 999
	else
		settings.max = settings.max - 1
	end
	
	if not settings.accept then --Символы
		settings.accept = "." --"[0-9a-zA-Z]"
	end
	
	if not settings.mask then --Маска
		settings.mask = false
	end
	
	if not settings.center then --Центровка
		settings.center = false
	end

	local text = settings.text
	local x = settings.x
	local y = settings.y
	local blink = true

	local function getX()
		if settings.center then
			return x - unicode.len(text) / 2
		else
			return x
		end
	end
	
	local function setText()
		if not settings.mask then
			g.set(getX(), y, text)
		else
			g.fill(getX(), y, unicode.len(text), 1, "*")
		end
	end
	
	setText()
	
	while true do
		local event, _, char, code = event.pull(0.5)
				
		if event == "key_down" then
			if code == 28 then --Enter
				g.set(getX() + unicode.len(text), y, " ")
				term.setCursor(1, y + 1)
				return text
			elseif code == 14 then --BackSpace
				text = unicode.sub(text, 1, -2)
				g.set(getX() + unicode.len(text), y, "  ")
				if settings.center then
					setText()
					g.set(getX() - 1, y, " ")
				end
			elseif char and char ~= 0 then
				if unicode.char(char):find(settings.accept) then
					if settings.max >= unicode.len(text) then
						text = text .. unicode.char(char)
						setText()
					end
				end
			end
		elseif event == "clipboard" then
			text = text .. char
			if unicode.len(text) > settings.max then
				text = unicode.sub(text, 1, settings.max)
			end
			setText()
		end
		
		if not blink or event ~= nil then
			blink = true
			g.set(getX() + unicode.len(text), y, "█")
		else
			blink = false
			g.set(getX() + unicode.len(text), y, " ")
		end
	end
end

--Old function
function sky.clearL(h) --Очистка левой части
	g.fill(3,2,26,h-2," ")
end

function sky.clearR(w,h) --Очистка правой части
	g.fill(31,2,w-32,h-2," ")
end

function sky.midL(w,y,text) --Центровка слева
	local _,n = string.gsub(text, "&","")
	local l = unicode.len(text) - n * 2
	x = 13 - (l / 2)
	sky.text(x+2, y, text)
end

function sky.midR(w,y,text) --Центровка справа
	local _,n = string.gsub(text, "&","")
	local l = unicode.len(text) - n * 2
	x = ((w - 34) / 2) - (l / 2)
	sky.text(x+31, y, text)
end

function sky.tohex(str) --Преобразовать строку из str в hex
	return (str:gsub('.', function (c)
		return string.format('%02X', string.byte(c))
	end))
end

function sky.fromhex(str) --Преобразовать строку из hex в str
	return (str:gsub('..', function (cc)
		return string.char(tonumber(cc, 16))
	end))
end

return sky
