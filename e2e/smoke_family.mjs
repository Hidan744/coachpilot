// Кабинет родителя: тренер выдаёт код, родитель регистрируется, видит расписание ребёнка
// и подтверждает участие; тренер видит подтверждение. Чужой ребёнок родителю недоступен.
import { randomUUID } from 'node:crypto';
import { launch, open, fill, tap, see, shot, step, API } from './lib.mjs';

const { browser, page } = await launch();

async function api(path, { method = 'GET', body, token } = {}) {
  const r = await fetch(`${API}${path}`, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, json: r.status === 204 ? null : await r.json() };
}

try {
  // Тренер и его данные — через API.
  const coachEmail = `coach${Date.now()}@test.ru`;
  const reg = await api('/auth/register', { method: 'POST', body: { email: coachEmail, password: 'secret123', name: 'Тренер', consent_personal_data: true } });
  const coach = reg.json.access_token;
  const tid = randomUUID(), pid = randomUUID(), sid = randomUUID(), otherPid = randomUUID();
  const when = new Date(Date.now() + 2 * 86400e3).toISOString();
  const up = (entity, id, data) => ({ entity, id, op: 'upsert', data });
  const pushed = await api('/sync/push', { method: 'POST', token: coach, body: { changes: [
    up('teams', tid, { name: 'Сочи U12', age_group: 'U12', level: 'amateur', default_players: 14 }),
    up('players', pid, { team_id: tid, first_name: 'Миша', last_name: 'Иванов', parent_consent: { given: true, by: 'Иванова' } }),
    up('players', otherPid, { team_id: tid, first_name: 'Чужой', parent_consent: { given: true, by: 'X' } }),
    up('training_sessions', sid, { team_id: tid, title: 'Передачи в движении', duration_min: 60, status: 'planned', scheduled_at: when }),
  ] } });
  if (!pushed.json.results.every((r) => r.status === 'applied')) throw new Error('push: ' + JSON.stringify(pushed.json));
  const code = (await api(`/players/${pid}/invite`, { method: 'POST', token: coach, body: { role: 'parent' } })).json.code;
  step('тренер выдал код родителю');

  // Родитель — через интерфейс.
  await open(page);
  await tap(page, 'Зарегистрироваться');
  await tap(page, 'Родитель');
  const parentEmail = `parent${Date.now()}@test.ru`;
  await fill(page, 'Имя', 'Анна');
  await fill(page, 'Email', parentEmail);
  await fill(page, 'Пароль', 'secret123');
  await tap(page, 'Согласен на обработку');
  await tap(page, 'Создать аккаунт');
  await see(page, 'Кабинет родителя', 30000);
  await see(page, 'Пока нет подключённых игроков');
  await tap(page, 'Ввести код');
  await fill(page, 'Код', code);
  await tap(page, 'Подключить');
  await see(page, 'Миша Иванов', 20000);
  step('родитель подключил ребёнка по коду');

  await tap(page, 'Миша Иванов');
  await see(page, 'Передачи в движении', 20000);
  await tap(page, 'Буду');
  await see(page, 'Тренер увидит: Буду');
  await shot(page, 'family-01-child');
  const rs = (await api(`/teams/${tid}/rsvp`, { token: coach })).json;
  if (rs[`session:${sid}`]?.yes !== 1) throw new Error('rsvp: ' + JSON.stringify(rs));
  step('подтверждение участия дошло до тренера');

  // Чужой ребёнок: подстановка id в запросе — 404.
  const login = (await api('/auth/login', { method: 'POST', body: { email: parentEmail, password: 'secret123' } })).json.access_token;
  const other = await api(`/family/children/${otherPid}`, { token: login });
  if (other.status !== 404) throw new Error('чужой ребёнок доступен: ' + other.status);
  step('чужой ребёнок недоступен');
  console.log('FAMILY E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
