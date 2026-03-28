local component = require("component")
local computer=require("computer")
local event = require("event")
local term = require("term")
local shell = require("shell")
local fs = require("filesystem")
local unicode = require("unicode")
local serial = require("serialization")
local pim = component.pim
local g = component.gpu
local sky = require("skyLib")
event.shouldInterrupt = function () return false end
--------------------Настройки--------------------
local WIDTH, HEIGHT = 146, 42 --Разрешение моника 146/112 x 42
local AUTOEXIT = 30 --Автовыход через n сек.
local COLOR1 = 0x00ffff --Рамка
local COLOR2 = 0x0000ff --Цвет кнопок
local TONE = 600 --Тональность звука
local RED = 0 --Сторона редстоун блока
local CHAT_NAME = "§8[§2OpenCasino§8]: " --Ник чатбокса
local STAVKA = 5 --Начальная ставка
local MAX_STAVKA = 10 --Максимальная ставка (Больше 10к лучше не ставить, а то уедет за пределы кнопки)
local SPAM = 1 --Время, в течении которого нельзя юзать комп, после выхода
-------------------------------------------------
if not (fs.exists(shell.getWorkingDirectory() .. "/LogoCasino.lua")) then
	shell.execute("wget https://www.dropbox.com/s/b6j1an94qo8sbhp/LogoCasino.lua?dl=1")
end
local image = {} --Библиотека
local mid = (WIDTH-32)/2+32
local images = {"cherry", "seven", "diamond", "orange", "pickaxe", "cheese", "pokeball", "meat", "apple"}
local summa = 0
local smile = false
local summa_money
local active = false

stavka = STAVKA
login = false
timer = 0
spam = false

component.chat_box.setName("§6G§7")

g.setResolution(WIDTH, HEIGHT)
sky.logo("OpenCasino", COLOR1, COLOR2, WIDTH, HEIGHT)
g.setForeground(COLOR2)
for i = 1, HEIGHT do
	g.set(29, i, "||")
end

function Wins(win1,win2,win3) -- При смене бонуса, сменичть число в функции Say()
	if win1 == 1 and win2 == 1 and win3 == 1 then
		return 15
	elseif win1 == 2 and win2 == 2 and win3 == 2 then
		return 100
	elseif win1 == 3 and win2 == 3 and win3 == 3 then
		return 40
	elseif win1 == 4 and win2 == 4 and win3 == 4 then
		return 20
	elseif win1 == 5 and win2 == 5 and win3 == 5 then
		return 12
	elseif win1 == 6 and win2 == 6 and win3 == 6 then
		return 17
	elseif win1 == 7 and win2 == 7 and win3 == 7 then
		return 10
	elseif win1 == 8 and win2 == 8 and win3 == 8 then
		return 25
	elseif win1 == 9 and win2 == 9 and win3 == 9 then
		return 30
	elseif win1 == win2 or win2 == win3 then
		return 2
	elseif win1 == win3 then
		return 1
	else
		return 0
	end
end

function money_all()
	if (fs.exists(shell.getWorkingDirectory() .. "/moneyCasino")) then
		local text = sky.fileRead(shell.getWorkingDirectory() .. "/moneyCasino")
		if text == nil then
			summa_money = {0,0}
			return 0,0
		else
			local object = serial.unserialize(text)
			summa_money = {object[1],object[2]}
			return object[1],object[2]
		end
	else
		sky.fileWrite(shell.getWorkingDirectory() .. "/moneyCasino", "{0,0}")
		summa_money = {0,0}
		return 0,0
	end
end

function Login(w,h,nick)
	if w>=7 and w<=24 and h>=37 and h<=39 then
		if not (login) then
			computer.addUser(nick)
			login = true
			sky.clearR(WIDTH,HEIGHT)
			g.setForeground(COLOR2)
			sky.midL(WIDTH,28,"Добро пожаловать")
			sky.midL(WIDTH,31,"Ваш баланс:")
			g.setForeground(COLOR1)
			sky.midL(WIDTH,29,nick)
			sky.midL(WIDTH,32, "[ " .. "Ваши средства" .. " ]") --TODO: change to balance inside file | sky.money(nick)
			sky.button(7,37,18,3,COLOR1,COLOR2,"    Выход    ")
			stavka = STAVKA
			Game()
			computer.beep(TONE, 0.05)
		else
			Exit()
		end
	end
end

function LoginPim(nick)
	if not (login) then
		computer.addUser(nick)
		login = true
		sky.clearR(WIDTH,HEIGHT)
		g.setForeground(COLOR2)
		sky.midL(WIDTH,28,"Добро пожаловать")
		sky.midL(WIDTH,31,"Ваш баланс:")
		g.setForeground(COLOR1)
		sky.midL(WIDTH,29,nick)
		sky.midL(WIDTH,32, "[ " .. "Ваши средства" .. " ]") --TODO: change to balance inside file | sky.money(nick)
		sky.button(7,37,18,3,COLOR1,COLOR2,"    Выход    ")
		stavka = STAVKA
		Game()
		computer.beep(TONE, 0.05)
	else
		Exit()
	end
end

function autoExit()
	timer = timer - 1
	g.setForeground(COLOR2)
	sky.midL(WIDTH,35, "Авто выход через:  ")
	g.setForeground(COLOR1)
	g.set(24, 35, timer .. " ")
	if (smile) then
		sky.midL(WIDTH,26, "__(^o^)__")
		smile = false
	else
		sky.midL(WIDTH,26, " \\(^o^)/ ")
		smile = true
	end
end

function Game()	
	sky.button(mid-30,37,6,3,COLOR1,COLOR2, "-10$")
	sky.button(mid-23,37,5,3,COLOR1,COLOR2, "-5$")
	sky.button(mid-17,37,5,3,COLOR1,COLOR2, "-1$")
	sky.button(mid-11,37,20,3,COLOR1,COLOR2, "Ставка " .. STAVKA .. "$")
	sky.button(mid+10,37,5,3,COLOR1,COLOR2, "+1$")
	sky.button(mid+16,37,5,3,COLOR1,COLOR2, "+5$")
	sky.button(mid+22,37,6,3,COLOR1,COLOR2, "+10$")
	g.setForeground(COLOR1)
	sky.midR(WIDTH,3, "Инфа о выигрышах:")
	sky.midR(WIDTH,5, "Выигрыш = ставка * на бонус")
	sky.midR(WIDTH,7, "Если 2 одинаковых предмета по краям - Бонус = х1")
	sky.midR(WIDTH,8, "Если 2 одинаковых предмета рядом - Бонус = х2")	
	g.setForeground(COLOR2)
	sky.midR(WIDTH,10, "Три покебола - Бонус = х10")
	sky.midR(WIDTH,11, "Три кирки - Бонус = х12")
	sky.midR(WIDTH,12, "Три вишенки - Бонус = х15")
	sky.midR(WIDTH,13, "Три сыра - Бонус = х17")
	sky.midR(WIDTH,14, "Три апельсинчика - Бонус = х20")
	sky.midR(WIDTH,15, "Три окорочка - Бонус = х25")
	sky.midR(WIDTH,16, "Три яблочка - Бонус = х30")
	sky.midR(WIDTH,17, "Три алмаза - Бонус = х40")
	sky.midR(WIDTH,18, "Три семёрки - Бонус = х100")
	g.setForeground(COLOR1)
	sky.midR(WIDTH,20, "Минимальная ставка: 1$")
	sky.midR(WIDTH,21, "Максимальная ставка: " .. MAX_STAVKA .. "$")
	local x,y = mid - 30, 24
	for i = 1, 3 do
		Image(images[math.random(1,#images)],x,y)
		x = x + 20
	end
end

function Image(pic,x,y)
	if pic == "cherry" then
		image.cherry(x,y)
	elseif pic == "seven" then
		image.seven(x,y)
	elseif pic == "diamond" then
		image.diamond(x,y)
	elseif pic == "orange" then
		image.orange(x,y)
	elseif pic == "pickaxe" then
		image.pickaxe(x,y)
	elseif pic == "cheese" then
		image.cheese(x,y)
	elseif pic == "pokeball" then
		image.pokeball(x,y)
	elseif pic == "meat" then
		image.meat(x,y)
	elseif pic == "apple" then
		image.apple(x,y)
	end
end

function check_rand(rand)
	if rand == #images then
		rand = 1
	else
		rand = rand + 1
	end
	return rand
end

function Table(rand1,rand2,rand3)
	local win = {}
	for i = 1, 60 do
		if i <= 20 then
			Image(images[rand1],mid-30,24)
			Image(images[rand1],mid-10,24)
			Image(images[rand1],mid+10,24)
			win[1] = rand1
			rand1 = check_rand(rand1)
		elseif i<=40 then
			Image(images[rand2],mid-10,24)
			Image(images[rand2],mid+10,24)
			win[2] = rand2
			rand2 = check_rand(rand2)
		elseif i<=60 then
			Image(images[rand3],mid+10,24)
			win[3] = rand3
			rand3 = check_rand(rand3)
		end
		os.sleep(0.05)
	end
	return win[1],win[2],win[3]
end

function Start(w,h,nick,stavka)
	--if(sky.checkMoney(nick,stavka)) then --TODO: change to check inventory/balance inside file
		computer.beep(TONE, 0.05)
		
		summa_money[1] = summa_money[1] + stavka
		sky.fileWrite(shell.getWorkingDirectory() .. "/moneyCasino", "{" .. summa_money[1] .. "," .. summa_money[2] .. "}")
		
		g.setForeground(COLOR1)
		sky.midL(WIDTH,11, summa_money[1] .. " эм.")
		sky.midL(WIDTH,35,"      Идёт игра...      ")
		sky.midL(WIDTH,32, " [ " .. "Ваши средства" .. " ] ") --TODO: change to balance inside file | sky.money(nick)
		sky.midR(WIDTH,35, "                    Крутим на " .. stavka .. "$                    ")
		local rand1, rand2, rand3, win = math.random(1, #images),math.random(1, #images),math.random(1, #images)
		local bonus = Wins(Table(rand1,rand2,rand3))
		g.setForeground(COLOR1)
		if bonus ~= 0 then 
			stavka = stavka * bonus
			--sky.com("money give " .. nick .. " " .. stavka) --TODO: change to increase balance inside file
			sky.midR(WIDTH,35,"Бонус ставки = x" .. bonus .. "  Вы выиграли: " .. stavka .. "$")

			--component.opencb.addWinningToStats(nick, stavka) --TODO: change to file stats
			
			summa_money[2] = summa_money[2] + stavka
			sky.fileWrite(shell.getWorkingDirectory() .. "/moneyCasino", "{" .. summa_money[1] .. "," .. summa_money[2] .. "}")
			
			sky.midL(WIDTH,14, summa_money[2] .. " эм.")
			sky.midL(WIDTH,32, "[ " .. "Ваши средства" .. " ]") --TODO: change to balance inside file | sky.money(nick)
			Say(bonus,nick,stavka)
			if bonus >= 10 then
				--component.redstone.setOutput(RED, 15) --TODO: do smth
				os.sleep(1)
				--component.redstone.setOutput(RED, 0)
			end
		else
			sky.midR(WIDTH,35,"                    Бонус ставки = x0  Вы проиграли                    ")
		end
	--else
	--	sky.midR(WIDTH,35, "                             Недостаточно средств                             ")
	--end
end

function Rules()
	g.setForeground(COLOR2)
	sky.midL(WIDTH,5,"==========================")
	sky.midL(WIDTH,9,"==========================")
	sky.midL(WIDTH,12,"==========================")
	sky.midL(WIDTH,15,"==========================")
	sky.midL(WIDTH,10, "Всего потрачено:")
	sky.midL(WIDTH,13, "Всего выиграно:")
	g.setForeground(COLOR1)
	sky.midL(WIDTH,3, "Общая инфа:")
	sky.midL(WIDTH,6, "Вы играете на свой")
	sky.midL(WIDTH,7, "страх и риск")
	sky.midL(WIDTH,8, "Эмы не возвращаются")
	local money_in, money_out = money_all()
	sky.midL(WIDTH,11,  money_in .. " эм.")
	sky.midL(WIDTH,14,  money_out .. " эм.")
	sky.button(7,37,18,3,COLOR1,COLOR2, "Залогиниться")
end

function Exit()
	login = false
	sky.clearL(HEIGHT)
	sky.clearR(WIDTH,HEIGHT)
	Rules()
	sky.drawImage(mid - 25,7, shell.getWorkingDirectory() .. "/LogoCasino.lua")
	image.cherry(mid - 30,24)
	image.apple(mid - 10,24)
	image.meat(mid + 10,24)
	local users={computer.users()}
    for i=1, #users do
        computer.removeUser(users[i])
    end
	spam = true
end

function Say(bonus, nick, stavka)
	if bonus == 15 then
		component.chat_box.say(CHAT_NAME .. "§5" .. nick .. " §aВыбил Три вишни в казино, выиграв §5" .. stavka .. " эм.")
	elseif bonus == 100 then
		component.chat_box.say(CHAT_NAME .. "§5" .. nick .. " §aВыбил Три семёрки в казино, выиграв §6" .. stavka .. " эм.")
	elseif bonus == 40 then
		component.chat_box.say(CHAT_NAME .. "§5" .. nick .. " §aВыбил Три алмаза в казино, выиграв §5" .. stavka .. " эм.")
	elseif bonus == 20 then
		component.chat_box.say(CHAT_NAME .. "§5" .. nick .. " §aВыбил Три апельсина в казино, выиграв §5" .. stavka .. " эм.")
	elseif bonus == 12 then
		component.chat_box.say(CHAT_NAME .. "§5" .. nick .. " §aВыбил Три кирки в казино, выиграв §5" .. stavka .. " эм.")
	elseif bonus == 17 then
		component.chat_box.say(CHAT_NAME .. "§5" .. nick .. " §aВыбил Три сыра в казино, выиграв §5" .. stavka .. " эм.")
	elseif bonus == 10 then
		component.chat_box.say(CHAT_NAME .. "§5" .. nick .. " §aВыбил Три покеболла в казино, выиграв §5" .. stavka .. " эм.")
	elseif bonus == 25 then
		component.chat_box.say(CHAT_NAME .. "§5" .. nick .. " §aВыбил Три окорочка в казино, выиграв §5" .. stavka .. " эм.")
	elseif bonus == 30 then
		component.chat_box.say(CHAT_NAME .. "§5" .. nick .. " §aВыбил Три яблока в казино, выиграв §5" .. stavka .. " эм.")
	end
end

function getStavka(w,h)
	if w>= mid-30 and w<=mid-25 and h>=37 and h<=39 then -- -10$
		stavka = stavka - 10
	elseif w>= mid-23 and w<=mid-19 and h>=37 and h<=39 then -- -5$
		stavka = stavka - 5
	elseif w>= mid-17 and w<=mid-13 and h>=37 and h<=39 then -- -1$
		stavka = stavka - 1
	elseif w>= mid+10 and w<=mid+14 and h>=37 and h<=39 then -- +1$
		stavka = stavka + 1
	elseif w>= mid+16 and w<=mid+20 and h>=37 and h<=39 then -- +5$
		stavka = stavka + 5
	elseif w>= mid+22 and w<=mid+27 and h>=37 and h<=39 then -- +10$
		stavka = stavka + 10
	else
		return
	end
	if stavka > MAX_STAVKA then 
		stavka = MAX_STAVKA
	elseif stavka < 1 then
		stavka = 1
	end
	g.setForeground(COLOR1)
	sky.midR(WIDTH,38,"  Ставка " .. stavka .. "$  ")
end

function image.cherry(x,y)
	g.setForeground(0x333333)
	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█           ▄▄▄▄ █")
	g.set(x,y+2,"█       ▄▄▀▀█▄ █ █")
	g.set(x,y+3,"█     ▄▀    █ ▀  █")
	g.set(x,y+4,"█  ▄▀▀▀▄   ▄█▄   █")
	g.set(x,y+5,"█ █     █▄▀   ▀▄ █")
	g.set(x,y+6,"█ ▀▄   ▄▀█     █ █")
	g.set(x,y+7,"█   ▀▀▀   ▀▄▄▄▀  █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█")
	g.setBackground(0x14a205)
	g.set(x+13,y+2,"▄ ")
	g.setBackground(0xd70f00)
	g.set(x+4,y+4,"▀▀▀")
	g.set(x+3,y+5,"     ")
	g.set(x+3,y+6,"▄   ▄")
	g.set(x+10,y+5,"▀   ▀")
	g.set(x+10,y+6,"     ")
	g.set(x+11,y+7,"▄▄▄")
	g.setForeground(0x700901)
	g.set(x+4,y+6,"▄▄█")
	g.set(x+7,y+5,"█")
	g.set(x+13,y+6,"▄█")
	g.setForeground(0xffffff)
	g.set(x+4,y+5,"▀")
	g.set(x+11,y+5,"▄")	
	g.setBackground(0x700901)
	g.setForeground(0x333333)
	g.set(x+7,y+6,"▄")
	g.set(x+14,y+5,"▀")
	g.set(x+11,y+7,"▄▄▄")
	g.setBackground(0x000000)
end

function image.seven(x,y)
	g.setForeground(0x333333)
	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█  █▀▀▀▀▀▄▄▄▄▀▀█ █")
	g.set(x,y+2,"█  █           █ █")
	g.set(x,y+3,"█  █▄▄▀▀▀▀▄   ▄▀ █")
	g.set(x,y+4,"█        ▄▀  █   █")
	g.set(x,y+5,"█      ▄▀   ▄▀   █")
	g.set(x,y+6,"█     ▄▀   ▄▀    █")
	g.set(x,y+7,"█     █▄▄▄▄█     █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█")
	g.setBackground(0xff7800)
	g.set(x+4,y+1,"▀▀▀▀▀")
	g.set(x+13,y+1,"▀▀")
	g.set(x+4,y+2,"           ")
	g.set(x+4,y+3,"▄▄")
	g.set(x+10,y+3,"▄   ▄")
	g.set(x+10,y+4,"▀  ")
	g.set(x+8,y+5,"▀   ▄")
	g.set(x+7,y+6,"▀   ▄")
	g.set(x+7,y+7,"▄▄▄▄")
	g.setBackground(0x000000)
end

function image.diamond(x,y)
	g.setForeground(0x333333)
	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█      ▄▄▄▄      █")
	g.set(x,y+2,"█    ▄▀    ▀▄    █")
	g.set(x,y+3,"█   █       ▀▄   █")
	g.set(x,y+4,"█  █         ▀▄  █")
	g.set(x,y+5,"█  █          █  █")
	g.set(x,y+6,"█   █        █   █")
	g.set(x,y+7,"█    ▀▄▄▄▄▄▄▀    █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█")
	g.setBackground(0x008b8b)
	g.set(x+6,y+7,"▄")
	g.set(x+11,y+7,"▄")
	g.setBackground(0xffffff)
	g.set(x+6,y+2,"▀")
	g.setBackground(0x00ffff)
	g.set(x+11,y+2,"▀")
	g.set(x+12,y+3,"▀")
	g.set(x+13,y+4,"▀")
	g.setForeground(0xffffff)
	g.set(x+7,y+2,"▀▀▀█")
	g.set(x+5,y+3,"█ ▄▄█▄ ")
	g.set(x+4,y+4,"█ █      ")
	g.set(x+4,y+5,"█▀")
	g.setForeground(0x008b8b)
	g.set(x+11,y+4,"█")
	g.set(x+6,y+5,"▀▄▄▄▄▀▀▀")
	g.set(x+5,y+6," █    █ ")
	g.setForeground(0x333333)
	g.set(x+7,y+7,"▄▄▄▄")
	g.setBackground(0x000000)
end

function image.orange(x,y)
	g.setForeground(0x333333)
	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█   ▄▀▀▀▀▀▀▀▄    █")
	g.set(x,y+2,"█ ▄▀         ▀▄  █")
	g.set(x,y+3,"█ █           █▄ █")
	g.set(x,y+4,"█ █            █ █")
	g.set(x,y+5,"█ █           █▀ █")
	g.set(x,y+6,"█ ▀▄         ▄▀  █")
	g.set(x,y+7,"█   ▀▄▄▄▄▄▄▄▀    █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█")
	g.setBackground(0xfcef84)
	g.set(x+5,y+1,"▀▀▀▀▀")
	g.set(x+3,y+2,"▀")
	g.set(x+3,y+6,"▄")
	g.set(x+5,y+7,"▄▄▄▄▄")
	g.setForeground(0xffc600)
	g.set(x+4,y+2,"▄██ ██▄")
	g.set(x+3,y+3," ▄▀█ █▀▄ ")
	g.set(x+3,y+4," ██   ██ ")
	g.set(x+3,y+5," ▀▄█ █▄▀ ")
	g.set(x+4,y+6,"▀██ ██▀")
	g.setForeground(0x333333)
	g.setBackground(0xff7800)
	g.set(x+10,y+1,"▀▀")
	g.set(x+13,y+2,"▀")
	g.set(x+13,y+6,"▄")
	g.set(x+10,y+7,"▄▄")
	g.setForeground(0xfcef84)
	g.set(x+11,y+2,"▄ ")
	g.set(x+12,y+3,"  ")
	g.set(x+12,y+4,"   ")
	g.set(x+12,y+5,"  ")
	g.set(x+11,y+6,"▀ ")
	g.setBackground(0x000000)
end

function image.pickaxe(x,y)
	g.setForeground(0x333333)
	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█     ▄▄▄▄▄      █")
	g.set(x,y+2,"█    ▀▄▄▄▄ ▀▄▀   █")
	g.set(x,y+3,"█        ▄▀▄ ▀▄  █")
	g.set(x,y+4,"█      ▄▀▄▀ █ █  █")
	g.set(x,y+5,"█    ▄▀▄▀   █ █  █")
	g.set(x,y+6,"█  ▄▀▄▀      ▀   █")
	g.set(x,y+7,"█ ▀▄▀            █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█")
	g.setBackground(0x08d7bc)
	g.set(x+6,y+2,"▄▄▄▄ ▀")
	g.set(x+11,y+3,"▄ ▀")
	g.set(x+13,y+4," ")
	g.set(x+13,y+5," ")
	g.setBackground(0x974a06)
	g.set(x+12,y+2,"▄▀")
	g.set(x+10,y+3,"▀")
	g.set(x+8,y+4,"▀▄")
	g.set(x+6,y+5,"▀▄")
	g.set(x+4,y+6,"▀▄")
	g.set(x+3,y+7,"▄")
	g.setBackground(0x000000)
end

function image.cheese(x,y)
	g.setForeground(0x333333)
	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█                █")
	g.set(x,y+2,"█    ▄▀▀▀▄▄      █")
	g.set(x,y+3,"█  ▄▀      ▀▀▄▄  █")
	g.set(x,y+4,"█ █            █ █")
	g.set(x,y+5,"█ █            █ █")
	g.set(x,y+6,"█ █            █ █")
	g.set(x,y+7,"█ ▀▀▀▀▀▀▀▀▀▀▀▀▀▀ █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█")
	g.setBackground(0xffb400)
	g.set(x+6,y+2,"▀▀▀")
	g.set(x+4,y+3,"▀      ▀▀")
	g.setBackground(0xff8400)
	g.setForeground(0xffb400)
	g.set(x+7,y+3,"▄██▀")
	g.set(x+3,y+4,"▀▀   ▀▀▀▀▀▀▀")
	g.setForeground(0x982020)
	g.set(x+3,y+5,"  ▀▀▀  ██  ▄")
	g.set(x+3,y+6," ▄▄  ▀     ▀")
	g.set(x+5,y+4,"▄▄▄")
	g.setBackground(0x000000)
end

function image.pokeball(x,y)
	g.setForeground(0x333333)
	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█    ▄▄▀▀▀▀▄▄    █")
	g.set(x,y+2,"█  ▄▀        ▀▄  █")
	g.set(x,y+3,"█ ▄▀    ▄▄    ▀▄ █")
	g.set(x,y+4,"█ █▄▄▄▄█  █▄▄▄▄█ █")
	g.set(x,y+5,"█ ▀▄    ▀▀    ▄▀ █")
	g.set(x,y+6,"█  ▀▄        ▄▀  █")
	g.set(x,y+7,"█    ▀▀▄▄▄▄▀▀    █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█")
	g.setBackground(0xff0000)
	g.set(x+7,y+1,"▀▀▀▀")
	g.set(x+4,y+2,"▀        ▀")
	g.set(x+3,y+3,"▀    ▄▄    ▀")
	g.set(x+3,y+4,"▄▄▄▄█  █▄▄▄▄")
	g.setBackground(0xffffff)
	g.set(x+8,y+4,"  ")
	g.set(x+3,y+5,"▄    ▀▀    ▄")
	g.set(x+4,y+6,"▄        ▄")
	g.set(x+7,y+7,"▄▄▄▄")
	g.setBackground(0x000000)
end

function image.meat(x,y)
	g.setForeground(0x333333)
	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█          ▄▀▀█▄ █")
	g.set(x,y+2,"█          █   █ █")
	g.set(x,y+3,"█   ▄▄▄▄▀▀▀▄▄▀▀  █")
	g.set(x,y+4,"█ ▄▀        █    █")
	g.set(x,y+5,"█ █        █     █")
	g.set(x,y+6,"█ █       █      █")
	g.set(x,y+7,"█  ▀▄▄▄▄▄▀       █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█")
	g.setBackground(0xe87209)
	g.set(x+8,y+3,"▀▀▀▄▄")
	g.set(x+3,y+4,"▀        ")
	g.set(x+3,y+5,"        ")
	g.set(x+3,y+6,"       ")
	g.setBackground(0x981b07)
	g.set(x+8,y+3,"▀")
	g.set(x+4,y+7,"▄▄▄▄▄")
	g.setForeground(0xe87209)
	g.set(x+7,y+4,"▀█▄ ▀")
	g.set(x+4,y+5,"▄████▀ ")
	g.set(x+3,y+6,"▀██▄▀  ")
	g.setBackground(0xfef2ae)
	g.set(x+13,y+2,"█▄")
	g.setForeground(0x333333)
	g.set(x+12,y+1,"▀▀")	
	g.set(x+12,y+2," ")
	g.set(x+11,y+3,"▄")
	g.setBackground(0x000000)
end

function image.apple(x,y)
	g.setForeground(0x333333)
	g.set(x,y,  "█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█")
	g.set(x,y+1,"█      ▀▄        █")
	g.set(x,y+2,"█   ▄▀▀▀▀█▀▀▀▄   █")
	g.set(x,y+3,"█  █    ▀▀    █  █")
	g.set(x,y+4,"█  █          █  █")
	g.set(x,y+5,"█  ▀▄        ▄▀  █")
	g.set(x,y+6,"█   ▀▄      ▄▀   █")
	g.set(x,y+7,"█     ▀▀▀▀▀▀     █")
	g.set(x,y+8,"█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█")
	g.setBackground(0xc6ff00)
	g.set(x+5,y+2,"▀▀")
	g.set(x+4,y+3,"    ▀▀    ")
	g.set(x+4,y+5,"▄")
	g.set(x+5,y+6,"▄")
	g.setBackground(0x14a205)
	g.set(x+7,y+2,"▀▀█▀▀▀")
	g.set(x+13,y+5,"▄")
	g.set(x+12,y+6,"▄")
	g.setForeground(0xc6ff00)
	g.set(x+7,y+3,"▄")
	g.set(x+10,y+3,"▄   ")
	g.set(x+4,y+4,"████████  ")
	g.set(x+5,y+5,"██████▀ ")
	g.set(x+6,y+6,"▀▀▀▀▀ ")
	g.setBackground(0xffffff)
	g.set(x+5,y+3,"▀")
	g.set(x+5,y+4,"   ")
	g.set(x+6,y+5,"▄▄")
	g.setBackground(0x000000)
end

Exit()

while true do
	if (not spam) then
		local eventData = {event.pull(1)}
		local e,_,w,h,_,nick = event.pull(1, "touch")
		local e = eventData[1]
		if e == "player_on" then
			nick = eventData[2]
			LoginPim(nick)
		end
		if e == "touch" then
			if (login) then
				w,h,nick = eventData[3], eventData[4], eventData[6]
				getStavka(w,h)
				if w>=mid-11 and w<=mid+8 and h>=37 and h<=39 then
					Start(w,h,nick,stavka)
				end
			end
			timer = AUTOEXIT
		end
		if (login) then
			autoExit()
			if timer == 0 then	
				Exit()
			end
		end
	else
		os.sleep(SPAM)
		spam = false
	end
end
