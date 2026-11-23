# ForeverTrading

## v1.1.4

**New**
- **Faster**: saving a scan takes three to four times less work and far less of the game's memory - prices are written into the saved file once, when you log out (or `/reload`), not with every price. After "My items" or prices from another player, the Market, the deals and the item stats count again only the items that changed; everything again after a full scan, another auction house, a new day, and every 10 minutes. Long jobs take a share of each frame (less in a fight) instead of a fixed number of items: smooth on a slow computer, quicker on a fast one. `/ft perf` shows what each part took, the addon's memory, the saved data and how much of it waits to be written.
- **Without Auctionator**: ForeverTrading goes by its own scans. The fewer days an auction house has been scanned, the fewer days of prices are asked for - its first day the price of the last hours stands in for the average: top gainers and losers, the market mood, an item's change in a day, a week and a month, buy and sell signals, liquidity and reselling work from the first days. A market watched longer behaves as before. Auctionator and Mastercraft only fill in what is missing.
- **The carry list**: Signals > Deals > Between houses - a right click on a deal puts it on your list (and takes it off). It stays on the page, first, even when the deal is gone; at the other auction house the Sell page marks what you brought and shows what it cost and the price the deal counted on. It goes once you have listed it there, or after two weeks.
- **A smaller saved file**: Settings > Data - remove the history of items not seen on either auction house for 30 days (it says how many first). The ones that matter to you stay: your recipes and their materials, watchlist, what you own.
- **A lighter exchange**: between two players with 1.1.4 prices go compact - about a third fewer messages (7,000 prices in some 1 minute on three lanes instead of almost 2). With older versions as before. `/ft share test` also checks that every character comes through; should they come changed, the old format is asked for.
- **Our own font**: Sofia Sans Condensed Medium (SIL Open Font License) - narrow, with Cyrillic; no Mastercraft needed for it. The classic style keeps the game's font. A new file: restart the game once after updating.

**Changes**
- Top gainers and losers show only items that rose, or fell - no rows of 0%; before today's scan, the moves of the last day the market was seen.

**Новое**
- **Быстрее**: сохранение скана в 3–4 раза легче и гораздо меньше нагружает память игры — цены пишутся в файл сохранений один раз, при выходе (или `/reload`), а не с каждой ценой. После «Моих товаров» или цен от другого игрока «Рынок», сделки и статистика предметов пересчитывают только изменившиеся предметы; всё целиком — после полного скана, смены аукциона, в новый день и раз в 10 минут. Долгая работа занимает долю каждого кадра (в бою меньше), а не фиксированное число предметов: плавно на слабом компьютере, быстрее на сильном. `/ft perf` показывает, сколько заняла каждая часть, память аддона, размер данных и сколько ждёт записи.
- **Без Auctionator**: ForeverTrading опирается на свои сканы. Чем меньше дней аукцион сканировали, тем меньше дней истории требуется — в первый день вместо средней берётся цена последних часов: лидеры роста и падения, настроение рынка, изменение цены за день, неделю и месяц, сигналы «купить/продать», ликвидность и перепродажа работают с первых дней. На рынке, который смотрят дольше, — как раньше. Auctionator и Mastercraft только дополняют недостающее.
- **Список закупки**: «Сигналы > Сделки > Между аукционами» — правый клик по сделке добавляет её в список (и убирает). Она остаётся на странице первой, даже когда сделки уже нет; на другом аукционе вкладка «Продажа» помечает, что вы привезли, и показывает, почём купили и по какой цене ставить. Убирается сама, когда вы выставили привезённое там, или через две недели.
- **Файл сохранений меньше**: «Настройки > Данные» — убрать историю предметов, которых не было ни на одном аукционе 30 дней (сначала скажет, сколько). Нужные вам остаются: рецепты и их материалы, избранное, то, что у вас есть.
- **Обмен легче**: между игроками с 1.1.4 цены идут в плотном виде — примерно на треть меньше сообщений (7 000 цен примерно за минуту по трём каналам вместо почти двух). Со старыми версиями — как раньше. `/ft share test` заодно проверяет, что все символы доходят; если они приходят искажёнными, запрашивается старый формат.
- **Свой шрифт**: Sofia Sans Condensed Medium (свободная лицензия SIL OFL) — узкий, с кириллицей, Mastercraft для него не нужен. В классической теме — шрифт игры. Это новый файл: после обновления один раз перезапустите игру.

**Изменения**
- В лидерах роста и падения только выросшие или упавшие предметы, без строк с 0%; до сегодняшнего скана — движения за последний день, когда рынок видели целиком.

## v1.1.3

**Fixes**
- The ForeverTrading tab on the auction house window without Auctionator: it was placed after itself and threw an error ("Cannot anchor to itself") - now after the game's last tab.

**Исправления**
- Вкладка ForeverTrading на окне аукциона без Auctionator: она цеплялась сама к себе и давала ошибку («Cannot anchor to itself») — теперь встаёт после последней вкладки игры.

## v1.1.2

**New**
- **Blackwater apart**: the neutral auction house (shared by both factions) has lots and prices of its own, and now keeps its own price history, order books, sales, deals, your auctions there and its cut - a scan at Blackwater no longer mixes into your faction's prices. Talking to an auctioneer picks its house (an auctioneer of neither faction: the neutral one); the chip next to the auction house status switches whose prices the pages show - at an auctioneer too: standing at one house with the other's prices on, ForeverTrading is offline there (nothing read, bought or posted) until you switch back. A wrong guess is put right with the pencil on the chip (it asks first) and remembered for the auctioneers there. The exchange passes prices of the house on only (1.1.1 knows only your faction's); Auctionator's and Mastercraft's prices count for your faction's house only (Mastercraft's scans made while you were at Blackwater are left out). The cut is learned per house from its letters - 15% at Blackwater until one is read. The deals journal and the craft queue stay one for both houses.
- **A tidier look**: choices (views, durations, kinds of deals) are one framed switch with the chosen part raised, tinted buttons have an edge, a button that can't be pressed now goes grey - nothing that is a button reads as plain text. Very slightly rounded corners everywhere and round status lights. The light style has more contrast: hovered rows show grey, chosen rows gold, chips and badges show on white; the dark style's secondary text is a little brighter. Lined up: the Market's filters (a grid of four columns), the order book's buying box (its title, then the field and the button), the overview's cards (the mood bar under their text). The header keeps room for the pages: the name only in the full-screen window, the auction house pill a light alone in the compact one.
- **Deals between the auction houses** (Signals > Deals > Between houses): an item cheaper at one house than the other sells it for - buy, carry it over (Blackwater is open to both factions), list it there a copper under its lowest, or at its usual price when that is lower now; the cut of the house sold at counted. No more than sells there in two days (or half of what is listed there), and nothing that is hardly bought there. Both prices show with their age; the price there may be up to 3 days old.
- **Item windows ("More")**: up to four at once, to look at items side by side - "More" opens the next one (the item open already: its window; all four open: the one looked at longest ago), a material clicked in a window opens in that window. Each has a compact mode (the charts alone, half as wide: no order book, no buttons) and the standard one, and keeps it; a gold outline sets them apart from the main window. Each window has its own auction house (its chip), whatever the main window and the other windows show: one item at your faction's house and at Blackwater side by side; a window of the house you don't stand at is offline (no live prices, no buying).
- **A faster price exchange**: prices go on three lanes at once between two players with 1.1.2 - about three times as fast (5,000 prices in some 2 minutes instead of 5-6), some 750 bytes a second; with 1.1.1 as before. **Exchange** pressed while it runs stops it: what has come stays (`/ft share stop`).

**Fixes**
- **Good deals on any computer**: what a vendor pays was known only for items the game had loaded - a new computer or game has hardly any, and deals to a vendor didn't come. Now they are asked for (the cheapest items first, a few at a time) and the deals follow as they come. The empty page says why there are none: no prices yet, more deals with older prices than chosen, vendor prices still loading, too little history for reselling, deals under the minimum profit. `/ft debug` tells what the last look saw.
- **Deals journal**: a sale counts one even when the letter says 0 (Forever's do) - those written before too; letters are read the moment they are taken, so mail addons' "Collect all" no longer leaves sales out. "Bought / sold at" shows without a missing sign.
- **No exchange during your own scan**: asking by itself waits for it, nobody's prices are taken meanwhile, and what comes after that isn't fresher than your scan stops.
- The Settings page's columns no longer vanish when the window changes size; while a scan runs, Full scan and Exchange step aside in the standard window too; the ticker tape shows the market's most valuable listings while there are no moves yet (a new auction house, the first days); the market is built even when one item fails; a deals look that fails no longer stays "looking".

**Новое**
- **Черноводье отдельно**: у нейтрального аукциона (общего для обеих фракций) свои лоты и цены, и теперь у него своя история цен, стаканы, продажи, сделки, ваши лоты там и своя комиссия — скан у Черноводья больше не смешивается с ценами аукциона вашей фракции. Аукционист сам выбирает свой аукцион (аукционист без фракции — нейтральный); чип рядом со статусом аукциона переключает, чьи цены на страницах, — и у аукциониста тоже: если вы стоите у одного аукциона, а выбраны цены другого, ForeverTrading там офлайн (ничего не читается, не покупается и не выставляется), пока не переключите обратно. Ошибку определения исправляет карандаш на чипе (сначала спросит), и она запоминается для аукционистов этого места. Обмен передаёт цены только выбранного аукциона (1.1.1 знает только аукцион фракции); цены Auctionator и Mastercraft идут только в аукцион фракции (сканы Mastercraft, сделанные пока вы были у Черноводья, не берутся). Комиссия узнаётся для каждого аукциона по его письмам — у Черноводья 15%, пока письмо не прочитано. Журнал сделок и очередь крафта общие для обоих аукционов.
- **Аккуратнее вид**: переключатели (виды, длительность, типы сделок) — единый элемент в рамке с выделенной выбранной частью, у цветных кнопок есть контур, недоступная кнопка становится серой — ни одна кнопка не выглядит как простой текст. Везде чуть скруглённые углы и круглые индикаторы. В светлой теме больше контраста: наведённые строки серые, выбранные золотистые, чипы и бейджи видны на белом; второстепенный текст тёмной темы чуть ярче. Выровнены: фильтры рынка (сетка в четыре колонки), блок покупки под стаканом (заголовок, под ним поле и кнопка), карточки обзора (полоска настроения под текстом). В шапке хватает места вкладкам: название только в полноэкранном окне, в компактном у статуса аукциона только индикатор.
- **Сделки между аукционами** («Сигналы > Сделки > Между аукционами»): что на одном аукционе дешевле, чем продаётся на другом, — купить, отвезти (Черноводье открыто обеим фракциям), выставить там на 1 медь дешевле самой низкой цены или по обычной цене, если сейчас она ниже; учтена комиссия аукциона, где продаёте. Не больше, чем там продаётся за два дня (или половина выставленного там), и ничего, что там почти не покупают. Обе цены показаны с возрастом; цена там может быть до 3 дней.
- **Окна предметов («Подробнее»)**: до четырёх сразу, чтобы смотреть товары рядом — «Подробнее» открывает следующее (товар уже открыт — его окно; открыты все четыре — то, на которое дольше всего не смотрели), материал, кликнутый в окне, открывается в нём же. У каждого есть компактный режим (только графики, вдвое уже: без стакана и кнопок) и стандартный, и окно его запоминает; золотая обводка отделяет их от главного окна. У каждого окна свой аукцион (свой чип), независимо от главного окна и других окон: один товар на аукционе фракции и у Черноводья рядом; окно аукциона, у которого вы не стоите, — офлайн (без живых цен и покупки).
- **Обмен цен быстрее**: между игроками с 1.1.2 цены идут сразу по трём каналам — примерно в три раза быстрее (5 000 цен примерно за 2 минуты вместо 5–6), около 750 байт в секунду; с 1.1.1 — как раньше. Нажатие **Обмен** во время обмена останавливает его, полученное остаётся (`/ft share stop`).

**Исправления**
- **Сделки на любом компьютере**: цена торговца была известна только для предметов, которые игра уже загрузила — на новом компьютере или в новой игре их почти нет, и сделок «Торговцу» не было. Теперь эти цены запрашиваются (сначала самые дешёвые предметы, понемногу), и сделки появляются по ходу. Пустая страница объясняет, почему сделок нет: цен ещё нет, есть сделки по ценам старше выбранного срока, цены торговцев ещё загружаются, мало истории для перепродажи, сделки меньше минимальной прибыли. `/ft debug` показывает, что нашёл последний поиск.
- **Журнал сделок**: продажа считается за одну, даже если в письме 0 (письма Forever так и пишут), — и уже записанные тоже; письма читаются в момент, когда их забирают, поэтому «Собрать все» из почтовых аддонов больше не теряет продажи. «Покупка / продажа» показывается без пустого квадратика.
- **Обмен не идёт во время вашего скана**: автоматический запрос ждёт его конца, чужие цены в это время не принимаются, а то, что приходит после и не свежее вашего скана, останавливается.
- Колонки страницы настроек больше не пропадают при смене размера окна; во время скана «Полный скан» и «Обмен» уступают место и в стандартном окне; бегущая строка показывает самые дорогие лоты рынка, пока нет движений цен (новый аукцион, первые дни); рынок собирается, даже если один предмет дал ошибку; поиск сделок с ошибкой больше не зависает на «Ищу сделки...».

## v1.1.1

**New**
- **Good deals** (Signals > Deals): what to buy at the auction house right now for a profit - lots under what a vendor pays (buy, sell to the vendor: a sure profit), and lots far under the fair price on a steady market (not flooded, no crowd of new sellers, the cheap lots a small part of what is listed) to list again, the auction house's cut counted. Every cheap lot counts with a fresh order book (yours left out); **Check order books** searches the rest at the auction house. Click: the item with its order book, to buy there. Settings > Signals: how far under the fair price, the minimum profit.
- **What really sells** (an estimate: the game tells no one's sales): two looks at an item's listings are compared seller by seller and price by price - fewer at a price its sellers stay at is bought, a seller gone from a price and listing anew is a relisting (no sale), a listing whose time ran out expired. The Craft page, the Market and the item window show "sells ~4.2 a day (14 h watched)"; an item that hardly sells for what is listed gets RISKY, and Good deals skip it. The looks come from live prices, My items, the items you open or search, and (for the items that matter to you) the deep full scan.
- **Undercut**: an auction of yours that is no longer the cheapest (your own other lots aside) is said in chat at the auction house - once per auction and price - and shows on the Signals page. Sell > My auctions tells whether to wait or post again: what is listed under yours against what really sells in the time yours has left, and a price far under the fair or the vendor's not worth following. **Take off to post cheaper**: the auction is taken off (the deposit is lost), the item comes back by mail, and the Sell page has it first, at a copper under the lowest.
- **Deals journal** (Portfolio > Deals journal): what you bought and sold at the auction house and what it brought - from its letters (the price, the cut, the deposit back, how many), read when you open your mailbox, and the deposits of what you post here. Sold, bought, deposits lost and the result for today, 7, 30 or 90 days; item by item with the prices bought and sold at, and what came back unsold.
- **Craft queue** (Craft > Craft queue): recipes and how many crafts; every material of it together, less what you have in your bags and bank, each at its cheapest (the auction house walked up its order book for the whole amount, a vendor, or crafting it yourself) - what to buy and what it costs, what the crafts bring, and how long they take to sell. **Queue it** on a recipe (Shift: five).
- **What's new**: once a version, the first time the window opens after an update - a few lines, each with a button to where it is. **The tour**: step by step over the real window, the part a step is about ringed and the rest dimmed; offered on a first install. Both again any time: Settings > About, `/ft news`, `/ft tour`. About shows the version (a copy straight from the repository no longer says "dev").

**Smarter numbers**
- **Risks see the competition**: a craft gets RISKY, and the Sell page warns, when the market is flooded (far more listed than usual), more sellers than usual have come, or the price is 10% lower than at the check half an hour or more ago - checked again with every live update. Listed, auctions and sellers show how many more or fewer than at that check. Settings > Signals: **Flooded: more than usual by**.
- **The auction house's cut** isn't taken as 5% any more (it isn't the same everywhere now): it is learned from the auction house's letters about your sales - 5% until one is read - and the pages no longer say a percent.
- **Vendor prices of materials** are recorded again when you open a merchant (on Forever the game answers through a newer function, and nothing was recorded): craft costs take a material from the vendor whenever it is cheaper there. The poison supplier's reagents are known without a visit too (an estimate until you open the vendor).
- **Risky recipes on the Signals page** too, under Hold / avoid, with the reasons (they showed only on the Craft page).
- **Search on the Signals page**; searching finds Russian names whatever the case of the letters (Lua's lower case knew only A-Z).

**Fixes**
- **Price exchange fixed**: on Forever a character is "First Surname", and ForeverTrading didn't know itself in the exchange's messages - the one picked to send its prices never began. Now it does; and should the guild and the group bring nothing, the question goes as hidden whispers (to your group, to the ForeverTrading users met before and, when you press **Exchange**, to your guild online). `/ft share test` shows which ways the game carries.
- A scan up to 3 days old is passed on (it was one day). A pressed **Exchange** that brings nothing says who answered and why (no full scan yet, too old, not fresher than yours, sharing off, busy) or that nobody answered at all; `/ft debug` traces every step.
- **Poisons are back on the Craft page**: the classic craft window doesn't always say the item a recipe makes (Mastercraft reads it without one), so the item of the recipe's name is taken. A profession window no longer loses recipes: read with a search or a filter on, the recipes it doesn't show stay; switching windows, the previous profession's recipes are no longer saved under the new one. `/ft debug` counts the recipes of each profession.
- Intraday prices keep one record per 10 minutes while live too (it was one record for a whole live session).
- Stackable goods show **Price levels** instead of auctions (the game lists them by price, not by auction); the compact window's Craft page shows the charts without the materials.

**Новое**
- **Выгодные сделки** (Сигналы > Сделки): что купить на аукционе прямо сейчас с прибылью — лоты дешевле, чем платит торговец (купить и продать торговцу: прибыль без риска), и лоты сильно ниже справедливой цены на спокойном рынке (нет завала и наплыва продавцов, дешёвых лотов — малая часть выставленного), чтобы выставить снова, с учётом комиссии аукциона. Со свежим стаканом считаются все дешёвые лоты (ваши не в счёт); **Проверить стаканы** ищет остальные на аукционе. Клик — предмет со стаканом, покупать там. Настройки > Сигналы: насколько ниже справедливой и минимальная прибыль.
- **Что реально продаётся** (оценка: игра не сообщает чужих продаж): два замера стакана сравниваются по продавцам и ценам — стало меньше на цене, где продавцы остались, значит купили; продавец ушёл с цены и выставился заново — перевыставление, не продажа; у лота кончилось время — истёк. Крафт, Рынок и окно предмета показывают «продаётся ~4.2 в день (за 14 ч наблюдений)»; товар, который почти не покупают при таком предложении, получает РИСК, а «Сделки» его пропускают. Замеры дают живые цены, «Мои товары», открытые и найденные предметы и (для важных вам предметов) глубокий скан.
- **Вас перебили**: ваш лот, который больше не самый дешёвый (ваши другие лоты не в счёт), сообщается в чат у аукциониста — один раз на лот и цену — и виден в «Сигналах». Продажа > Мои лоты подскажет, ждать или перевыставить: сколько выставлено дешевле вашего против того, сколько реально продаётся за оставшееся вашему лоту время, а за ценой сильно ниже справедливой или торговца гнаться не стоит. **Снять и выставить дешевле**: лот снимается (залог сгорает), предмет приходит по почте, и страница «Продажа» покажет его первым с ценой на 1 медь ниже самой низкой.
- **Журнал сделок** (Портфель > Журнал сделок): что вы купили и продали на аукционе и что это принесло — по письмам аукциона (цена, комиссия, возвращённый залог, количество), которые читаются при открытии почтового ящика, и по залогам выставленного здесь. Продано, куплено, сгоревшие залоги и итог за сегодня, 7, 30 или 90 дней; по каждому предмету — цены покупки и продажи и что вернулось непроданным.
- **Очередь крафта** (Крафт > Очередь): рецепты и число крафтов; все материалы вместе за вычетом того, что есть в сумках и банке, каждый по самой выгодной цене (аукцион — проход по стакану на всё количество, торговец или свой крафт): что купить и сколько стоит, что принесут крафты и сколько дней займёт продажа. Кнопка **В очередь** на рецепте (Shift — пять).
- **Что нового**: один раз на версию, при первом открытии окна после обновления — несколько строк, у каждой кнопка «Показать». **Экскурсия**: шаг за шагом по настоящему окну, нужная часть обведена, остальное затемнено; предлагается при первой установке. И то и другое можно открыть снова: Настройки > Об аддоне, `/ft news`, `/ft tour`. В «Об аддоне» видна версия (копия прямо из репозитория больше не пишет «dev»).

**Точнее цифры**
- **Риски видят конкурентов**: крафт получает РИСК, а страница продажи предупреждает, когда рынок завален (выставлено намного больше обычного), продавцов стало больше обычного или цена на 10% ниже, чем при замере полчаса и более назад, — с проверкой при каждом живом обновлении. У «Выставлено», «Лотов» и «Продавцов» видно, на сколько больше или меньше, чем при том замере. Настройки > Сигналы: **Завал: больше обычного на**.
- **Комиссия аукциона** больше не считается как 5% (сейчас она не везде одинакова): она берётся из писем аукциона о ваших продажах — пока писем не было, 5%, — и процент больше нигде не пишется.
- **Цены торговцев на материалы** снова записываются при открытии окна торговца (на Forever игра отвечает через более новую функцию, и ничего не записывалось): себестоимость крафта берёт материал у торговца, когда там дешевле. Реагенты торговца ядами известны и без визита (оценка, пока вы не откроете торговца).
- **Рискованные рецепты в «Сигналах»** — в колонке «Держать / избегать», с причинами (раньше они были видны только в Крафте).
- **Поиск во вкладке «Сигналы»**; поиск находит русские названия в любом регистре (lower() в Lua знал только латиницу).

**Исправления**
- **Обмен ценами исправлен**: на Forever персонаж — «Имя Фамилия», и ForeverTrading не узнавал себя в сообщениях обмена: выбранный для отправки так и не начинал. Теперь узнаёт; а если гильдия и группа ничего не дали, запрос уходит скрытым шёпотом (группе, уже знакомым пользователям ForeverTrading и, когда вы нажали **Обмен**, гильдии в сети). `/ft share test` покажет, какие пути пропускает игра.
- Передаётся скан возрастом до 3 дней (было — сутки). Если нажатый **Обмен** ничего не принёс, он скажет, кто ответил и почему (полного скана ещё нет, слишком старый, не свежее ваших цен, выключено «Делиться», занят) или что не ответил никто; `/ft debug` показывает каждый шаг.
- **Яды вернулись в Крафт**: классическое окно ремесла не всегда сообщает предмет рецепта (Mastercraft читает его без него) — теперь берётся предмет с названием рецепта. Окно профессии больше не теряет рецепты: открытое с поиском или фильтром, оно не стирает невидимые, а при переключении окон рецепты прошлой профессии не записываются под новой. `/ft debug` показывает число рецептов по профессиям.
- Внутридневные цены хранят по записи на каждые 10 минут и при живом обновлении (раньше весь онлайн-сеанс сливался в одну запись).
- У стакающихся товаров вместо «Лотов» — **«Цен»** (игра отдаёт их строками по ценам, а не по лотам); в компактном окне Крафт показывает графики без материалов.
## v1.1.0

**Trading right in ForeverTrading** (at the auction house; nothing happens without your click on a question with the exact numbers)
- **Buy from the order book** (Market and the item window): click a price level or type a quantity, then **Buy**; stackable goods at the server's exact price, gear one auction at a time.
- **Selling page**: what you carry that the auction house takes, with market prices and signals; the price to begin with is a copper under the cheapest (or **At the cheapest**, or the **Fair price**), 2 / 8 / 24 hours, the deposit, the 5% cut, what you get and warnings (under the vendor price, far under the fair price, a price jump or fall, old prices).
- **My auctions**: your auctions with the lowest price now (red when you were undercut) and the time left; **Check the prices** reads their order books; **Cancel the auction**.
- **In place of the auction house window** (Settings > General, off by default): talking to an auctioneer opens ForeverTrading; the **AH: online / offline** pill shows whether you are at the auction house and brings the game's window back.

**Live data**
- **Live prices**: at the auction house the item you have open is searched again every 8 seconds (on the Craft page the recipe's item and its materials take turns); a small green circle counts down to the next update.
- **More**: the item in its own window - large charts, the numbers, the order book and the materials of one craft.
- **Price exchange**: ForeverTrading users in a guild or group share their scans; prices more than an hour old are asked for by themselves, or press **Exchange** (Settings > Exchange).

**Smarter numbers**
- **Fair price**: the median of the last days' prices, weighted by how many were listed, how long each stood and how recent it is. A **price jump** far above it (someone bought out the cheap lots and relisted them) isn't counted on in profits and signals; a **fast fall** under it (other crafters undercutting) makes a craft RISKY.
- **Materials per craft** next to the order book, each at its cheapest, priced by walking the order book for the quantity needed.
- The profitability line of items you don't craft is in gold; the moving averages ("Averages") show from 3 days of prices.
- Craft: a recipe worth crafting has an **Open recipe** button.

**Market and interface**
- Market list: **subcategories** and a **Filter** like the auction house's (level, usable, not collected, quality); an item opened from another page shows alone in the list (× clears the search).
- The compact window shows charts only; Settings is the gear in the header; ForeverTrading's questions are its own windows in the chosen style; price alerts in gold / silver / copper boxes.
- **My items** is scanned only when you press it, and asks first; the full scan at the auction house is off by default.
- Fixed: blue items flashing white on the Signals page; missing profession names in Russian; text running into other text in the header and the item views.

**Торговля прямо в ForeverTrading** (у аукциониста; ничего не происходит без вашего клика в окне с точными цифрами)
- **Покупка из стакана** (на Рынке и в окне предмета): клик по уровню цены или своё количество, затем **Купить**; обычные товары — по точной цене сервера, экипировка — по одному лоту.
- **Вкладка «Продажа»**: что у вас в сумках примет аукцион, с ценами рынка и сигналами; для начала цена на 1 медь дешевле самой низкой (или **По самой низкой**, или **Справедливая**), срок 2 / 8 / 24 ч, залог, комиссия 5%, сколько получите и предупреждения (дешевле торговца, сильно ниже справедливой, скачок или падение цены, старые цены).
- **Мои лоты**: ваши лоты с самой низкой ценой сейчас (красной, если вас перебили) и остатком времени; **Проверить цены** читает их стаканы; **Снять с аукциона**.
- **Вместо окна аукциона** (Настройки > Общие, по умолчанию выключено): при разговоре с аукционистом открывается ForeverTrading; индикатор **АХ: онлайн / офлайн** показывает, у аукциониста ли вы, и возвращает окно игры.

**Живые данные**
- **Живые цены**: у аукциониста открытый предмет запрашивается заново каждые 8 секунд (в Крафте по очереди предмет рецепта и его материалы); зелёный кружок показывает отсчёт до следующего обновления.
- **Подробнее**: предмет в отдельном окне — большие графики, цифры, стакан и материалы на 1 крафт.
- **Обмен ценами**: пользователи ForeverTrading в гильдии или группе делятся сканами; цены старше часа запрашиваются сами, или кнопка **Обмен** (Настройки > Обмен).

**Точнее цифры**
- **Справедливая цена**: медиана цен за последние дни, взвешенная по числу лотов, времени, сколько цена держалась, и свежести. **Скачок цены** намного выше неё (дешёвое скупили и перевыставили) не учитывается в прибыли и сигналах; **быстрое падение** ниже неё (конкуренты сбивают цену) делает крафт РИСКОМ.
- **Материалы на 1 крафт** рядом со стаканом — каждый по самой низкой цене, по стакану на нужное количество.
- Линия прибыльности для того, что вы не крафтите, — в золоте; «Средние» видны уже с 3 дней цен.
- Крафт: у выгодного рецепта есть кнопка **Открыть рецепт**.

**Рынок и интерфейс**
- Список Рынка: **подкатегории** и **Фильтр** как на аукционе (уровень, используемые, недостающие, качество); предмет, открытый с другой страницы, показывается в списке один (× сбрасывает поиск).
- Компактное окно — только графики; настройки — шестерёнка в шапке; вопросы ForeverTrading — в собственных окнах выбранного стиля; ценовой алерт — поля золото / серебро / медь.
- **Мои товары** сканируются только по кнопке и с подтверждением; полный скан при открытии аукциона по умолчанию выключен.
- Исправлено: мигание синих предметов белым на «Сигналах»; непереведённые профессии; наезжающий текст в шапке и карточках предметов.

## v1.0.1

- Fixed: searching the Market list no longer freezes the game or makes the list jump. Item names are kept in a saved name book, and the ones the game hasn't loaded yet arrive quietly in the background while you search.
- The release package now holds only the addon's files.

- Исправлено: поиск в списке рынка больше не вызывает фризы и «прыжки» списка. Названия предметов запоминаются, а недостающие тихо подгружаются в фоне, пока вы ищете.
- В архиве релиза теперь только файлы аддона.

## v1.0.0

First release.

- **Market**: every item seen on the auction house with its price, 24h change and 7-day sparkline; a price line and a profitability line (zero in the middle) per item; RSI and other indicators; price alerts; the item's order book with a "what does buying N cost" calculator; market overview with the market mood and top movers.
- **Craft**: cost, revenue after the 5% cut, profit, margin and a signal for every recipe your characters know; the cheapest way to get each material (auction house, vendor or crafting it yourself).
- **Signals**: sell now / worth crafting / worth buying / hold or avoid.
- **Portfolio**: what all your characters hold, at market prices.
- **Scanning**: a quick full scan of the whole auction house, an optional deep scan, and "My items" with order books; Auctionator and Mastercraft data are used when they are installed.
- Dark, light and classic styles; compact, standard and full-screen window; a new-version notice; English and Russian.

---

- **Рынок**, **Крафт**, **Сигналы**, **Портфель** и собственный сканер аукциона.
- Тёмный, светлый и классический стили; компактное, стандартное и полноэкранное окно; уведомление о новой версии; русский и английский языки.
