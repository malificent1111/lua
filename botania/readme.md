## Установка для жизнекамня/жизнедерева:

- Собираем робота, в него обязательно помещаем **"Геоанализатор", "Контроллер инвентаря", "Инвентарь"**
- Помещаем робота, как показано на скриншоте **lifeblocks_instruction.png** (`обязательно с правой стороны`). Робот смотрит в сторону цветка!
- Отделяем рабочую область робота другими блоками, чтобы он в них обязательно упирался, иначе будет выходить за рамки поля.
- Сбоку от робота ставим зарядку, под роботом ставим МЭ интерфейс
- В МЭ интерфейс в первый слот помещаем 8 камня, а во второй слот помещаем 8 любого дерева
- В программе меняем 6 и 7 строку (это инструменты, которые будет использовать робот, по умолчанию это ихор кирка и ихор топор)
> Инструментов обязательно должно быть два, даже если будете использовать программу под один тип блоков (жизнекамень или жизнедерево).
> Их мы помещаем как показано на скриншоте **lifeblocks_robot_setup.png**, в каком порядке не важно, будь то топор или кирка в первом/втором слоте.
- Перед запуском убедитесь, что нет никаких блоков вокруг цветка.


## Установка для рун:

- Устанавливаем блоки, как показано в **runes_instruction.png**
- Справа выключенный вакуумный сундук (`обязательно использовать именно его!`)
- Слева вакуумный сундук с настройками со скриншота **runes_vacuum_setup.png**
- Настраиваем файл **runes.lua** (строки 5,7) - инструкция указана внутри файла
- С автоматизацией клика по руническому алтарю думаю разберетесь сами
- Заполняем интерфейс шаблонами (всего 16 рун)
> `Шаблон не содержит в себе жизнекамень!` Жизнекамень подается отдельно в выбрасыватель сверху от рунического алтаря.
