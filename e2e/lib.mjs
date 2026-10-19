// Помощники для e2e-проверок Flutter web через дерево доступности (semantics).
import { chromium } from 'playwright';

export const APP = process.env.APP_URL ?? 'http://localhost:8080';
export const API = process.env.API_URL ?? 'http://localhost:8000';
export const SHOTS = process.env.SHOTS ?? '/tmp';

export async function launch() {
  // CHROME="" — использовать Chromium, установленный Playwright (CI).
  const chrome = process.env.CHROME ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
  const browser = await chromium.launch(chrome ? { executablePath: chrome } : {});
  const context = await browser.newContext({ viewport: { width: 400, height: 860 }, locale: 'ru-RU' });
  const page = await context.newPage();
  page.on('pageerror', (e) => console.log('pageerror:', e.message));
  return { browser, context, page };
}

export async function open(page, url = APP) {
  await page.goto(url);
  await enableSemantics(page);
}

/** Переход внутри приложения (hash-маршрут) без перезагрузки страницы. */
export async function go(page, route) {
  await page.evaluate((r) => { window.location.hash = r; }, route);
  await page.waitForTimeout(800);
}

export async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 30000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(500);
}

// Flutter дописывает к aria-label подсказку поля, поэтому ищем по префиксу.
const byLabel = (label) => `input[aria-label^="${label}"], textarea[aria-label^="${label}"]`;

export async function fill(page, label, value) {
  const el = page.locator(byLabel(label)).first();
  await el.waitFor({ state: 'attached', timeout: 15000 });
  // Flutter пересоздаёт DOM-поле при фокусе, поэтому вводим текст в активный элемент
  // с клавиатуры и проверяем результат.
  for (let attempt = 0; attempt < 3; attempt++) {
    await clickLoc(page, el);
    await page.waitForTimeout(150);
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Delete');
    if (value) await page.keyboard.insertText(value);
    await page.waitForTimeout(150);
    const got = await page.evaluate(() => document.activeElement?.value ?? null);
    if (got === value) return;
  }
  throw new Error(`не удалось ввести текст в поле «${label}»`);
}

async function clickLoc(page, loc) {
  // Элемент может быть за пределами экрана: Flutter сам не прокручивает список — крутим колесом.
  for (let i = 0; ; i++) {
    try {
      await loc.click({ timeout: 2500 });
      break;
    } catch (e) {
      // Видимый элемент перекрыт контейнером semantics — кликаем по координатам,
      // Flutter сам определит, что находится под указателем.
      if (String(e.message).includes('intercepts pointer events')) {
        const box = await loc.boundingBox();
        if (box && box.y + box.height / 2 > 0 && box.y + box.height / 2 < 780) {
          await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
          break;
        }
      }
      if (i >= 10) throw e;
      await page.mouse.move(200, 400);
      await page.mouse.wheel(0, i < 5 ? 250 : -350);
      await page.waitForTimeout(300);
    }
  }
}

/** Клик по элементу с текстом (кнопки, плитки, вкладки). */
export async function tap(page, text, { exact = false } = {}) {
  const loc = target(page, text, exact).last();
  await loc.waitFor({ state: 'attached', timeout: 15000 });
  await clickLoc(page, loc);
  await page.waitForTimeout(400);
}

export async function see(page, text, timeout = 15000) {
  await target(page, text, false).first().waitFor({ timeout });
}

function target(page, text, exact) {
  const byText = page.locator('flt-semantics').filter({ hasText: exact ? new RegExp(`^${text}$`) : text });
  const byAria = page.locator(exact ? `[aria-label="${text}"]` : `[aria-label*="${text}"]`);
  return byText.or(byAria);
}

export async function shot(page, name) {
  await page.screenshot({ path: `${SHOTS}/${name}.png` });
}

export function step(name) {
  console.log('✓', name);
}

/** Регистрация через UI до главного экрана с созданной командой. */
export async function registerWithTeam(page, { name = 'Алексей', team = 'Спартак-2014' } = {}) {
  const email = `e2e${Date.now()}${Math.floor(Math.random() * 1000)}@test.ru`;
  await open(page);
  await tap(page, 'Зарегистрироваться');
  await fill(page, 'Имя', name);
  await fill(page, 'Email', email);
  await fill(page, 'Пароль', 'secret123');
  await tap(page, 'Согласен на обработку');
  await tap(page, 'Создать аккаунт');
  await see(page, 'Добро пожаловать');
  await fill(page, 'Название команды', team);
  await tap(page, 'Создать команду');
  await see(page, `Привет, ${name}`);
  return email;
}

export async function apiLogin(email) {
  const r = await fetch(`${API}/auth/login`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password: 'secret123' }),
  });
  const { access_token } = await r.json();
  const headers = { authorization: `Bearer ${access_token}`, 'content-type': 'application/json' };
  return {
    pull: async () => (await (await fetch(`${API}/sync/pull?limit=1000`, { headers })).json()).records,
    push: async (changes) => (await (await fetch(`${API}/sync/push`, { method: 'POST', headers, body: JSON.stringify({ changes }) })).json()).results,
  };
}

/** Настоящие события указателя (рисование на холсте): слой semantics не перехватывает клики. */
export async function rawPointer(page, fn) {
  await page.evaluate(() => document.querySelectorAll('flt-semantics').forEach((e) => { e.style.pointerEvents = 'none'; }));
  try {
    await fn();
  } finally {
    await page.evaluate(() => document.querySelectorAll('flt-semantics').forEach((e) => { e.style.pointerEvents = ''; }));
  }
}
