// Новые функции: импорт игроков из Word, импорт упражнений текстом, анимация схем.
import { launch, fill, tap, see, shot, step, registerWithTeam, rawPointer } from './lib.mjs';

const DOCX = process.env.DOCX ?? '/tmp/sostav.docx';
const { browser, page } = await launch();
// Снимок области схемы (верх экрана) — меняется, когда игроки двигаются.
const canvasHash = async () => (await page.screenshot({ clip: { x: 16, y: 64, width: 368, height: 306 } })).toString('base64');
try {
  await registerWithTeam(page, { team: 'Амкар U12' });

  // 1. Импорт игроков из Word
  await tap(page, 'Команда');
  const chooser = page.waitForEvent('filechooser');
  await tap(page, 'Загрузить список из Excel или Word');
  await tap(page, 'Выбрать файл');
  await (await chooser).setFiles(DOCX);
  await see(page, 'найдено: 4');
  await see(page, 'Иван Сидоров');
  await shot(page, 'f2-01-import-preview');
  // строка-заголовок «Состав U12» не отмечена автоматически
  await tap(page, 'Добавить в команду: 3');
  await see(page, 'Олег Белов');
  await see(page, 'Анна Кузнецова');
  await shot(page, 'f2-02-team-imported');
  step('игроки загружены из Word');

  // 2. Импорт упражнений текстом
  await tap(page, 'Библиотека');
  await tap(page, 'Импорт упражнений из файла');
  await fill(page, 'или вставьте текст',
    'Квадрат 4 на 2\nЦель: удержание мяча\nВремя: 12 мин\n1. Четверо по периметру держат мяч\n2. Двое в центре отбирают\nПодсказки:\n- открывайся до паса\n\nУдары после обводки\nОбвести стойку и пробить по воротам. Подобрать мяч и встать в конец колонны.');
  await tap(page, 'Разобрать текст');
  await see(page, 'Найдено упражнений: 2');
  await shot(page, 'f2-03-drills-parsed');
  await tap(page, 'Добавить в «Мои»: 2');
  await see(page, 'Квадрат 4 на 2');
  await see(page, 'Удары после обводки');
  step('упражнения разобраны и добавлены в «Мои»');

  // 3. Анимация схемы из библиотеки
  await tap(page, 'Все', { exact: true });
  await fill(page, 'Поиск', 'Рондо 5');
  await tap(page, 'Рондо 5×2');
  await see(page, 'Показать движение');
  const before = await canvasHash();
  // Нажатие пальцем по кнопке «▶» в углу схемы (настоящее событие указателя).
  const playBox = await page.locator('[aria-label="Показать движение"], flt-semantics:has-text("Показать движение")').last().boundingBox()
    .catch(() => null);
  await rawPointer(page, () => page.mouse.click(playBox ? playBox.x + playBox.width / 2 : 352, playBox ? playBox.y + playBox.height / 2 : 338));
  await page.waitForTimeout(900);
  await shot(page, 'f2-04-animation-step1');
  const mid = await canvasHash();
  await see(page, 'Шаг 2 из 2', 8000);
  await page.waitForTimeout(2200);
  await shot(page, 'f2-05-animation-end');
  if (before === mid) throw new Error('схема не меняется во время анимации');
  step('анимация схемы: шаги проигрываются');

  // 4. Своё упражнение: рисуем два шага и проигрываем
  await page.goBack();
  await tap(page, 'Своё упражнение');
  await fill(page, 'Название', 'Стенка и рывок');
  await tap(page, 'Нарисовать схему');
  // Поле меняет размер, когда появляются панели, — координаты считаем по текущему положению.
  const fieldAt = async (x, y) => {
    const r = await page.evaluate(() => {
      const nodes = [...document.querySelectorAll('flt-semantics, [aria-label]')].filter((e) =>
        ((e.getAttribute('aria-label') || '') + (e.textContent || '')).includes('Поле схемы'));
      const inner = nodes.filter((e) => !nodes.some((o) => o !== e && e.contains(o)));
      const b = inner[0].getBoundingClientRect();
      return { x: b.x, y: b.y, w: b.width, h: b.height };
    });
    return [r.x + r.w * x, r.y + r.h * y];
  };
  const clickField = async (x, y) => {
    const [px, py] = await fieldAt(x, y);
    await rawPointer(page, () => page.mouse.click(px, py));
    await page.waitForTimeout(250);
  };
  // Нападающий и партнёр, мяч у нападающего.
  await tap(page, 'Игрок (красные)');
  await clickField(0.3, 0.7);
  await clickField(0.75, 0.5);
  await tap(page, 'Мяч');
  await clickField(0.3, 0.7);
  // Движение 1: ведение по точкам.
  await tap(page, 'Движение игрока');
  await clickField(0.3, 0.7);
  await see(page, 'Ведение (1 с мячом)');
  await clickField(0.4, 0.5);
  await clickField(0.5, 0.35);
  await see(page, 'Точек: 2');
  await tap(page, 'Путь готов');
  // Движение 2: пас партнёру касанием.
  await clickField(0.5, 0.35);
  await tap(page, 'Пас', { exact: true });
  await see(page, 'Пас от 1');
  await clickField(0.75, 0.5);
  await shot(page, 'f2-06-editor-steps');
  await tap(page, 'Проиграть движение');
  await see(page, 'Нажмите ▶');
  const box2 = await page.locator('[aria-label="Показать движение"], flt-semantics:has-text("Показать движение")').last().boundingBox();
  await rawPointer(page, () => page.mouse.click(box2.x + box2.width / 2, box2.y + box2.height / 2));
  await see(page, 'Шаг 1 из 2');
  await page.waitForTimeout(800);
  await shot(page, 'f2-07-editor-preview');
  step('своя схема в два шага проигрывается');
  console.log('FEATURES2 E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
