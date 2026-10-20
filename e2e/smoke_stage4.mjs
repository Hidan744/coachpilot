import { launch, fill, tap, see, shot, step, registerWithTeam, apiLogin, API, rawPointer } from './lib.mjs';

const { browser, context, page } = await launch();
try {
  const email = await registerWithTeam(page, { team: 'Юниоры' });

  // Библиотека встроена в приложение: работает без сети сразу после установки
  await context.route(`${API}/**`, (r) => r.abort('internetdisconnected'));
  await tap(page, 'Библиотека');
  await see(page, 'Светофор с мячом');
  await fill(page, 'Поиск', 'рондо');
  await see(page, 'Рондо 5×2');
  await shot(page, 's4-01-library-search');
  await tap(page, 'Рондо 5×2');
  await see(page, 'Как выполнять');
  await see(page, 'Подсказки тренера');
  await shot(page, 's4-02-drill');
  await tap(page, 'В избранное');
  await page.goBack();
  await page.waitForTimeout(500);
  await fill(page, 'Поиск', '');
  await tap(page, 'Избранное', { exact: true });
  await see(page, 'Рондо 5×2');
  step('библиотека офлайн: поиск, карточка, избранное');
  await context.unroute(`${API}/**`);

  // Своё упражнение со схемой
  await tap(page, 'Все', { exact: true });
  await tap(page, 'Своё');
  await fill(page, 'Название', 'Квадрат 3×1 у ворот');
  await tap(page, 'Нарисовать схему');
  await see(page, 'Выбор и перемещение');
  await tap(page, 'Игрок (красные)');
  await rawPointer(page, async () => {
    await page.mouse.click(120, 330);
    await page.mouse.click(280, 330);
  });
  await tap(page, 'Пас');
  await rawPointer(page, async () => {
    await page.mouse.move(125, 340);
    await page.mouse.down();
    await page.mouse.move(200, 342, { steps: 8 });
    await page.mouse.move(272, 340, { steps: 8 });
    await page.mouse.up();
  });
  await shot(page, 's4-03-scheme-editor');
  await tap(page, 'Готово', { exact: true });
  await fill(page, 'Как выполнять (шаги)', 'Пас партнёру\nОткрывание под пас');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Пас партнёру');
  await shot(page, 's4-04-own-drill');
  step('своё упражнение со схемой создано');

  await page.waitForTimeout(3500);
  const api = await apiLogin(email);
  const recs = await api.pull();
  const own = recs.find((r) => r.entity === 'drills' && r.data.title === 'Квадрат 3×1 у ворот');
  if (!own) throw new Error('упражнение не на сервере');
  const types = own.data.scheme.items.map((i) => i.type).sort().join(',');
  if (types !== 'arrow_pass,player_a,player_a') throw new Error('схема на сервере: ' + types);
  if (!recs.some((r) => r.entity === 'favorites')) throw new Error('избранное не синхронизировано');
  step('упражнение, схема и избранное синхронизированы');
  console.log('STAGE 4 E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
