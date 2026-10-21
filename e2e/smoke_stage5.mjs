import { launch, fill, tap, see, shot, step, registerWithTeam, apiLogin, API, go } from './lib.mjs';

const { browser, context, page } = await launch();
try {
  const email = await registerWithTeam(page, { team: 'U12 Звезда' });
  await tap(page, 'Календарь');
  await tap(page, 'Тренировки', { exact: true });
  await see(page, 'Запланированных тренировок нет');
  await tap(page, 'Конструктор', { exact: true });
  await see(page, 'Цель занятия');
  await tap(page, 'Удары по воротам');
  await shot(page, 's5-01-wizard');
  await tap(page, 'Сгенерировать план');
  await see(page, 'Предложение AI', 30000);
  await see(page, 'Σ 75 / 75 мин');
  await shot(page, 's5-02-plan');
  step('AI-план сгенерирован, длительность сходится');

  // Правка длительности блока и автоматическая проверка суммы
  await tap(page, 'Больше');
  await see(page, 'Σ 76 / 75 мин');
  await see(page, 'План длиннее занятия на 1 мин');
  await tap(page, 'Меньше');
  await see(page, 'Σ 75 / 75 мин');
  step('редактирование длительности и проверка суммы');

  // Карточка блока с упражнением, заметка (блоки ниже полосы времени — прокручиваем)
  await page.mouse.move(200, 600);
  await page.mouse.wheel(0, 400);
  await page.waitForTimeout(500);
  await tap(page, 'Игровая часть');
  await see(page, 'Как выполнять');
  await fill(page, 'Заметка / адаптация к группе', 'Двое вратарей по очереди');
  // Панель блока закрывается с анимацией — ждём, прежде чем сохранять сам план.
  await tap(page, 'Сохранить', { exact: true });
  await page.waitForTimeout(900);
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Провести');
  await shot(page, 's5-03-plan-saved');
  step('заметка к блоку, план сохранён');

  await page.waitForTimeout(3500);
  const api = await apiLogin(email);
  const s = (await api.pull()).find((r) => r.entity === 'training_sessions');
  if (!s || s.data.status !== 'planned' || !s.data.ai_generated) throw new Error('план не на сервере: ' + JSON.stringify(s?.data));
  if (!s.data.blocks.some((b) => b.notes === 'Двое вратарей по очереди')) throw new Error('заметка не сохранилась');
  if (s.data.blocks.reduce((a, b) => a + b.duration_min, 0) !== 75) throw new Error('сумма на сервере');
  step('план с заметкой синхронизирован');

  // Без сети: план из библиотеки без AI
  await context.route(`${API}/**`, (r) => r.abort('internetdisconnected'));
  await go(page, '/sessions/new');
  await tap(page, 'Владение мячом');
  await tap(page, 'Сгенерировать план');
  await see(page, 'Нет связи с сервером');
  await tap(page, 'Собрать без AI');
  await see(page, 'Локальный подбор по правилам');
  await see(page, 'Σ 75 / 75 мин');
  await shot(page, 's5-04-offline-plan');
  step('без сети: план собран из библиотеки на телефоне');
  console.log('STAGE 5 E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
