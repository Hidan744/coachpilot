import { launch, open, fill, tap, see, shot, step, enableSemantics, API } from './lib.mjs';

const { browser, context, page } = await launch();
try {
  const email = `e2e${Date.now()}@test.ru`;
  await open(page);
  await tap(page, 'Зарегистрироваться');
  await fill(page, 'Имя', 'Алексей');
  await fill(page, 'Email', email);
  await fill(page, 'Пароль', 'secret123');
  await tap(page, 'Согласен на обработку');
  await shot(page, 's2-01-register');
  await tap(page, 'Создать аккаунт');
  await see(page, 'Добро пожаловать, Алексей');
  step('регистрация → онбординг');

  await fill(page, 'Название команды', 'Спартак-2014');
  await tap(page, 'U10', { exact: true });
  await shot(page, 's2-02-onboarding');
  await tap(page, 'Создать команду');
  await see(page, 'Привет, Алексей');
  await see(page, 'Спартак-2014');
  await shot(page, 's2-03-home');
  step('онбординг → главная, команда создана');

  // Команда дошла до сервера
  await page.waitForTimeout(3500);
  const login = await (await fetch(`${API}/auth/login`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password: 'secret123' }),
  })).json();
  const pull = await (await fetch(`${API}/sync/pull`, { headers: { authorization: `Bearer ${login.access_token}` } })).json();
  if (!pull.records.some((r) => r.entity === 'teams' && r.data.name === 'Спартак-2014' && r.data.age_group === 'U10')) {
    throw new Error('команда не синхронизирована: ' + JSON.stringify(pull));
  }
  step('команда синхронизирована с сервером');

  // Офлайн: API недоступен, перезагрузка — сессия и данные на месте
  await context.route(`${API}/**`, (r) => r.abort('internetdisconnected'));
  await page.reload();
  await enableSemantics(page);
  await see(page, 'Привет, Алексей');
  await see(page, 'Спартак-2014');
  await tap(page, 'Профиль');
  await see(page, 'Нет связи с сервером');
  await shot(page, 's2-04-offline-profile');
  step('офлайн: вход и данные доступны без сети');

  await context.unroute(`${API}/**`);
  await tap(page, 'Сейчас');
  await see(page, 'Синхронизировано');
  step('связь восстановлена → синхронизировано');

  await tap(page, 'Выйти');
  await tap(page, 'Выйти', { exact: true });
  await see(page, 'Вход');
  await fill(page, 'Email', email);
  await fill(page, 'Пароль', 'secret123');
  await tap(page, 'Войти', { exact: true });
  await see(page, 'Спартак-2014');
  step('выход и повторный вход: данные загружены с сервера');
  console.log('STAGE 2 E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
