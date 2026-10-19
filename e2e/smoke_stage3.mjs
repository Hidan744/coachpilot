import { launch, fill, tap, see, shot, step, registerWithTeam, apiLogin, go } from './lib.mjs';
import { randomUUID } from 'node:crypto';

const { browser, page } = await launch();
try {
  const email = await registerWithTeam(page);
  await tap(page, 'Команда');
  await see(page, 'Добавьте игроков');

  // Три игрока: «Сохранить и добавить ещё» для быстрого ввода
  await tap(page, 'Игрок');
  for (const [first, last] of [['Саша', 'Петров'], ['Миша', 'Иванов']]) {
    await fill(page, 'Имя', first);
    await fill(page, 'Фамилия (необязательно)', last);
    await tap(page, 'Сохранить и добавить ещё');
  }
  await fill(page, 'Имя', 'Ваня');
  await fill(page, 'Год рождения', '2014');
  await tap(page, 'Нападающий');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Саша Петров');
  await see(page, 'Ваня');
  await shot(page, 's3-01-team');
  step('игроки добавлены');

  // Карточка игрока и оценка навыка
  await tap(page, 'Ваня');
  await see(page, 'Посещаемость');
  await tap(page, 'Оценить');
  await tap(page, '4', { exact: true });
  await fill(page, 'Комментарий (наблюдение)', 'Хорошо открывается');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, '4/5');
  await shot(page, 's3-02-player');
  step('оценка навыка сохранена');

  // Занятие создано «на другом устройстве» (через API) — посещаемость
  await page.waitForTimeout(3000);
  const api = await apiLogin(email);
  let recs = await api.pull();
  const teamId = recs.find((r) => r.entity === 'teams').id;
  const players = recs.filter((r) => r.entity === 'players');
  if (players.length !== 3) throw new Error(`на сервере ${players.length} игроков`);
  if (!recs.some((r) => r.entity === 'player_assessments' && r.data.score === 4)) throw new Error('оценка не на сервере');
  const sessionId = randomUUID();
  await api.push([{ entity: 'training_sessions', id: sessionId, op: 'upsert',
    data: { team_id: teamId, title: 'Вторник', duration_min: 60, status: 'planned' } }]);
  step('данные на сервере, занятие создано');

  await go(page, `/attendance/${sessionId}?team=${teamId}`);
  await tap(page, 'Отметить всех присутствующими');
  await see(page, 'Посещаемость · 3');
  // Миша: «Был» → «Не был»
  await tap(page, 'Миша Иванов');
  await see(page, 'Посещаемость · 2');
  await shot(page, 's3-03-attendance');
  await tap(page, 'Готово');
  step('посещаемость отмечена');

  await page.waitForTimeout(3000);
  recs = await api.pull();
  const att = recs.filter((r) => r.entity === 'attendance');
  const statuses = att.map((r) => r.data.status).sort().join(',');
  if (statuses !== 'absent,present,present') throw new Error('посещаемость на сервере: ' + statuses);
  step('посещаемость синхронизирована');

  await go(page, '/team');
  await see(page, '0%');
  await see(page, '100%');
  await shot(page, 's3-04-team-stats');
  step('процент посещаемости в списке игроков');
  console.log('STAGE 3 E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
