import { launch, fill, tap, see, shot, step, registerWithTeam, apiLogin, API, enableSemantics, go } from './lib.mjs';

const clock = async (page) => page.evaluate(() => {
  for (const e of document.querySelectorAll('flt-semantics, [aria-label]')) {
    const m = (e.getAttribute('aria-label') || e.textContent || '').match(/^\s*(\+?\d\d:\d\d)\s*(осталось|пауза|время вышло)/);
    if (m) return m[1];
  }
  return null;
});
const secs = (c) => { const [m, s] = c.replace('+', '').split(':').map(Number); return m * 60 + s; };

const { browser, context, page } = await launch();
try {
  const email = await registerWithTeam(page, { team: 'U14 Торпедо' });
  await tap(page, 'Конструктор тренировки');
  await tap(page, 'Передачи и открывания');
  await tap(page, 'Сгенерировать план');
  await see(page, 'Предложение AI', 30000);
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Провести');
  await page.waitForTimeout(3000); // план ушёл на сервер
  step('план готов');

  // Дальше — без интернета: проведение занятия полностью офлайн
  await context.route(`${API}/**`, (r) => r.abort('internetdisconnected'));
  await tap(page, 'Провести');
  await see(page, '1 / ');
  await tap(page, 'Старт');
  await page.waitForTimeout(2500);
  const c1 = await clock(page);
  await page.waitForTimeout(2000);
  const c2 = await clock(page);
  if (!c1 || !c2 || secs(c2) >= secs(c1)) throw new Error(`таймер не идёт: ${c1} → ${c2}`);
  await tap(page, 'Пауза');
  const p1 = await clock(page);
  await page.waitForTimeout(1500);
  if ((await clock(page)) !== p1) throw new Error('пауза не останавливает таймер');
  await tap(page, '+1 мин');
  if (secs(await clock(page)) !== secs(p1) + 60) throw new Error('+1 мин не сработал');
  await shot(page, 's6-01-run');
  step(`таймер: ${c1} → ${c2}, пауза, +1 мин`);

  await tap(page, 'Заметка', { exact: true });
  await tap(page, 'Не поняли задание');
  await see(page, 'Заметка сохранена');
  await tap(page, 'Продолжить');
  await tap(page, 'Далее');
  await see(page, '2 / ');
  await tap(page, 'Пропустить');
  await see(page, '3 / ');
  step('заметка, переход, пропуск блока');

  // «Перезапуск приложения» посреди занятия — продолжаем с того же блока
  await page.reload();
  await enableSemantics(page);
  await see(page, '3 / ');
  await shot(page, 's6-02-after-reload');
  // Перезапуск через главную: карточка «Идёт занятие» → «Продолжить»
  await go(page, '/home');
  await see(page, 'Идёт занятие');
  await tap(page, 'Продолжить');
  await see(page, '3 / ');
  const c3 = await clock(page);
  await page.waitForTimeout(1500);
  if (secs(await clock(page)) >= secs(c3)) throw new Error('после перезапуска таймер не идёт');
  await shot(page, 's6-02-after-reload');
  step('после перезапуска занятие продолжилось с того же блока');

  await tap(page, 'Завершить', { exact: true });
  await tap(page, 'Завершить', { exact: true });
  await see(page, 'Отчёт о занятии');
  await see(page, 'Не поняли задание');
  step('занятие завершено офлайн → отчёт');

  await tap(page, 'Оценка 4');
  await fill(page, 'Свободная заметка', 'Саша хорошо открывался, в конце упала интенсивность');
  await tap(page, 'Оформить с AI');
  await see(page, 'Нет связи');
  await context.unroute(`${API}/**`);
  await page.waitForTimeout(4500); // подсказка «Нет связи» закрывается сама
  await tap(page, 'Оформить с AI');
  await see(page, 'Предложения AI на следующие занятия', 30000);
  await shot(page, 's7-01-report');
  step('без сети — понятное сообщение; с сетью — AI оформил отчёт');

  await tap(page, 'Подтвердить отчёт');
  await see(page, 'Итоги занятия');
  await see(page, 'пропущен');
  await see(page, 'Не поняли задание');
  await see(page, 'Саша хорошо открывался');
  await shot(page, 's7-02-summary');
  step('итоги: блоки с фактом, заметки, отчёт');

  await page.waitForTimeout(3500);
  const api = await apiLogin(email);
  const recs = await api.pull();
  const s = recs.find((r) => r.entity === 'training_sessions');
  const rep = recs.find((r) => r.entity === 'session_reports');
  const note = recs.find((r) => r.entity === 'session_notes');
  if (s.data.status !== 'done' || !s.data.actual.skipped.length || !s.data.finished_at) throw new Error('занятие: ' + JSON.stringify(s.data.actual));
  if (!rep || !rep.data.coach_confirmed || rep.data.rating !== 4 || !rep.data.ai_suggestions.length) throw new Error('отчёт: ' + JSON.stringify(rep?.data));
  if (!note || note.data.text !== 'Не поняли задание') throw new Error('заметка');
  step('занятие, заметка и подтверждённый отчёт на сервере');

  await tap(page, 'Главная');
  await see(page, 'Конструктор');
  // Недавние занятия — ниже сводки недели и быстрых действий.
  await page.mouse.move(200, 400);
  await page.mouse.wheel(0, 1500);
  await page.waitForTimeout(500);
  await see(page, 'Недавние занятия');
  await shot(page, 's7-03-home');
  console.log('STAGE 6-7 E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
