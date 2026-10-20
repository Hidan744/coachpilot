// Сезон: календарь (расписание, матчи, импорт), тактическая доска с заменой,
// индивидуальный план развития и страница для родителей по ссылке.
import { launch, fill, tap, see, shot, step, registerWithTeam, rawPointer } from './lib.mjs';

const { browser, context, page } = await launch();
const ruDay = (d) => d.toLocaleDateString('ru-RU', { day: 'numeric', month: 'long' });

try {
  await registerWithTeam(page, { team: 'Амкар U16' });

  // Состав: вратарь, защитник, нападающий и запасной
  await tap(page, 'Команда');
  await tap(page, 'Игрок');
  for (const [first, last, pos] of [['Саша', 'Петров', 'Вратарь'], ['Миша', 'Иванов', 'Защитник'], ['Ваня', 'Сидоров', 'Нападающий']]) {
    await fill(page, 'Имя', first);
    await fill(page, 'Фамилия (необязательно)', last);
    await tap(page, pos);
    await tap(page, 'Сохранить и добавить ещё');
  }
  await fill(page, 'Имя', 'Олег');
  await fill(page, 'Фамилия (необязательно)', 'Белов');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Олег Белов');
  step('состав из 4 игроков');

  // 1. Регулярная тренировка: пн и ср 10:00–12:00
  await tap(page, 'Календарь');
  await see(page, 'Добавьте матчи сезона');
  await tap(page, 'Добавить');
  await tap(page, 'Регулярная тренировка');
  await see(page, 'Дни недели');
  await tap(page, 'Пн', { exact: true });
  await tap(page, 'Ср', { exact: true });
  await tap(page, '120 мин');
  await see(page, 'до 12:00');
  await fill(page, 'Место (поле, манеж)', 'Манеж Звезда');
  await shot(page, 'cal-01-slot-form');
  await tap(page, 'Сохранить', { exact: true });

  // Ближайший понедельник в календаре
  const now = new Date();
  const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + ((8 - now.getDay()) % 7 || 7));
  if (monday.getMonth() !== now.getMonth()) await tap(page, 'Следующий месяц');
  await tap(page, ruDay(monday));
  await see(page, 'Тренировка Амкар U16');
  await see(page, '10:00–12:00');
  await see(page, 'Нажмите, чтобы составить план');
  step('регулярная тренировка видна в календаре по понедельникам');

  // 2. Матч в этот день
  await tap(page, 'Добавить');
  await tap(page, 'Соперник, дата, стадион');
  await fill(page, 'Соперник', 'Зенит U16');
  await tap(page, 'В гостях');
  await fill(page, 'Стадион / адрес', 'Смена');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, '@ Зенит U16');
  await see(page, '18:00–19:30');
  await shot(page, 'cal-02-day');
  step('матч добавлен в календарь');

  // 3. Из расписания — план тренировки на этот день
  await tap(page, 'Нажмите, чтобы составить план');
  await see(page, 'Тренировка Амкар U16');
  await page.goBack();
  await page.waitForTimeout(800);
  await see(page, 'ЗАПЛАНИРОВАНА');
  step('тренировка из расписания открыта как план');

  // 4. Календарь игр текстом
  await tap(page, 'Добавить');
  await tap(page, 'Календарь игр из файла');
  await fill(page, 'Или вставьте список матчей', '5 декабря 16:00 Амкар — Урал U16\n12.12 Крылья Советов U16 (г)');
  await tap(page, 'Разобрать текст');
  await see(page, 'Найдено матчей: 2');
  await see(page, 'Урал U16');
  await shot(page, 'cal-03-import');
  await tap(page, 'Добавить в календарь: 2');
  await see(page, 'Добавлено матчей: 2');
  step('календарь игр загружен из текста');

  // 5. Тактика на матч: доска с составом, рисунок и замена.
  // Снова выбираем день матча: после загрузки календаря список дня мог перестроиться.
  // Список календаря мог быть прокручен вниз (клик с прокруткой колесом) — возвращаемся к сетке месяца.
  await page.waitForTimeout(1500);
  await page.mouse.move(200, 400);
  for (let i = 0; i < 4; i++) {
    await page.mouse.wheel(0, -1000);
    await page.waitForTimeout(200);
  }
  await tap(page, ruDay(monday));
  await see(page, '@ Зенит U16');
  await tap(page, '@ Зенит U16');
  await tap(page, 'Тактика на матч');
  await see(page, 'Поле тактической доски');
  await see(page, 'Матч: Зенит U16');
  const field = await page.evaluate(() => {
    const nodes = [...document.querySelectorAll('flt-semantics, [aria-label]')].filter((e) =>
      ((e.getAttribute('aria-label') || '') + (e.textContent || '')).includes('Поле тактической доски'));
    const inner = nodes.filter((e) => !nodes.some((o) => o !== e && e.contains(o)));
    const r = inner[0].getBoundingClientRect();
    return { x: r.x, y: r.y, width: r.width, height: r.height };
  });
  const at = (x, y) => [field.x + field.width * x, field.y + field.height * y];
  const fieldShot = async () => (await page.screenshot({ clip: field })).toString('base64');
  await shot(page, 'cal-04-board');

  const before = await fieldShot();
  await tap(page, 'Рисовать');
  await rawPointer(page, async () => {
    const [x1, y1] = at(0.3, 0.6);
    await page.mouse.move(x1, y1);
    await page.mouse.down();
    for (let i = 1; i <= 12; i++) {
      const [x, y] = at(0.3 + i * 0.03, 0.6 - i * 0.02 + (i % 3) * 0.01);
      await page.mouse.move(x, y, { steps: 2 });
    }
    await page.mouse.up();
  });
  await page.waitForTimeout(500);
  if ((await fieldShot()) === before) throw new Error('рисунок не появился на доске');
  step('рисование пальцем на доске');

  // Белов уходит на скамейку, затем выходит вместо вратаря: касание фишки → «Замена»
  await tap(page, 'Двигать');
  await rawPointer(page, async () => {
    const [x, y] = at(0.5, 0.78);
    await page.mouse.click(x, y);
  });
  await tap(page, 'Убрать с поля');
  await page.waitForTimeout(500);
  await rawPointer(page, async () => {
    const [x, y] = at(0.5, 0.93);
    await page.mouse.click(x, y);
  });
  await tap(page, 'Замена');
  await see(page, 'Кто выходит вместо Петров');
  await tap(page, 'Олег Белов');
  await see(page, 'Замена: вышел Белов, ушёл Петров');
  await shot(page, 'cal-05-substitution');
  step('замена со скамейки');

  // Расстановка соперника
  await tap(page, 'Схема');
  await tap(page, 'Соперник');
  await tap(page, '4-4-2');
  await page.waitForTimeout(600);
  await shot(page, 'cal-06-board-opponent');
  step('расстановка соперника');
  await page.goBack();
  await page.waitForTimeout(600);
  await page.goBack();
  await page.waitForTimeout(600);

  // 6. Индивидуальный план развития
  await tap(page, 'Команда');
  await tap(page, 'Ваня Сидоров');
  await tap(page, 'Развитие', { exact: true });
  await tap(page, 'План', { exact: true });
  await see(page, 'Над чем работаем');
  await fill(page, 'Название', 'Игра левой ногой');
  await tap(page, 'Передачи');
  await fill(page, 'Задание', '100 передач левой у стенки');
  await tap(page, 'Добавить пункт');
  await tap(page, 'Цель', { exact: true });
  await fill(page, 'Цель', 'Уверенный приём левой');
  await tap(page, 'Добавить пункт');
  await see(page, '100 передач левой у стенки');
  await shot(page, 'cal-07-plan');
  await tap(page, 'Сохранить план');
  await see(page, 'Игра левой ногой');
  await see(page, 'Выполнено 0 из 2');
  step('план развития игрока');

  // 7. Сообщение родителям
  await tap(page, 'Родителям', { exact: true });
  await tap(page, 'Написать');
  await tap(page, 'Питание');
  await fill(page, 'Текст', 'Завтрак за 2–3 часа до игры, больше воды');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Завтрак за 2–3 часа до игры');
  await shot(page, 'cal-08-player');
  step('сообщение родителям');

  // 8. Ссылка для родителей: страница без входа
  await tap(page, 'Ссылка для родителей');
  await see(page, 'Ссылка для игрока и родителей', 30000);
  await shot(page, 'cal-09-share');
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await tap(page, 'Скопировать', { exact: true });
  await see(page, 'Ссылка скопирована');
  const url = (await page.evaluate(() => navigator.clipboard.readText())).match(/https?:\/\/\S+\/p\/[\w-]+/)?.[0];
  if (!url) throw new Error('ссылка не найдена');
  const parent = await context.newPage();
  await parent.goto(url);
  const body = await parent.textContent('body');
  for (const s of ['Ваня Сидоров', 'Амкар U16', 'Завтрак за 2–3 часа', 'Игра левой ногой', '100 передач левой у стенки', 'Зенит U16']) {
    if (!body.includes(s)) throw new Error(`на странице для родителей нет «${s}»`);
  }
  await parent.screenshot({ path: `${process.env.SHOTS ?? '/tmp'}/cal-10-parent-page.png`, fullPage: true });
  step('страница для родителей открывается по ссылке');
  console.log('OK');
} catch (e) {
  await shot(page, 'cal-fail');
  console.error(e);
  process.exitCode = 1;
} finally {
  await browser.close();
}
