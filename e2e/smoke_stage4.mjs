import { tapField, launch, fill, tap, see, shot, step, registerWithTeam, apiLogin, API, rawPointer } from './lib.mjs';

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
  await tap(page, 'Своё упражнение');
  await fill(page, 'Название', 'Квадрат 3×1 у ворот');
  await tap(page, 'Нарисовать схему');
  await see(page, 'Выбор и перемещение');
  // Два игрока, мяч у первого; движение: пас партнёру касанием.
  await tap(page, 'Игрок (красные)');
  await tapField(page, 0.3, 0.6);
  await tapField(page, 0.7, 0.6);
  await tap(page, 'Мяч');
  await tapField(page, 0.3, 0.6);
  await tap(page, 'Движение игрока');
  await tapField(page, 0.3, 0.6);
  await tap(page, 'Пас', { exact: true });
  await tapField(page, 0.7, 0.6);
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
  if (types !== 'arrow_pass,ball,player_a,player_a') throw new Error('схема на сервере: ' + types);
  // Связи сохраняются на сервере: пас знает, кто и кому, мяч — чей.
  const items = own.data.scheme.items;
  const pass = items.find((i) => i.type === 'arrow_pass'), ball = items.find((i) => i.type === 'ball');
  const [a, b] = items.filter((i) => i.type === 'player_a');
  if (!pass.actor || pass.actor !== a.id || pass.target !== b.id || ball.holder !== a.id) {
    throw new Error('связи схемы потеряны: ' + JSON.stringify(items));
  }
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
