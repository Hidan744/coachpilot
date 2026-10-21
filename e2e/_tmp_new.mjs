import { launch, open, tap, see, shot, go } from './lib.mjs';
const { browser, page } = await launch();
try {
  await open(page, 'http://localhost:8091/');
  await see(page, 'Основной состав');
  await tap(page, 'Календарь');
  await page.waitForTimeout(1500);
  await shot(page, 'n1-calendar');
  await go(page, '/team?tab=1');
  await see(page, 'Рекомендации тренеру');
  await shot(page, 'n2-advice');
  await go(page, '/library');
  await page.waitForTimeout(1200);
  await shot(page, 'n3-library-adults');
  await tap(page, 'Дети и юноши');
  await page.waitForTimeout(800);
  await shot(page, 'n4-library-kids');
  await tap(page, 'Рондо');
  await see(page, 'Рекомендации по возрасту');
  await page.mouse.move(200, 500); await page.mouse.wheel(0, 600); await page.waitForTimeout(800);
  await shot(page, 'n5-drill-kids');
  await go(page, '/calendar?tab=1');
  console.log('OK');
} catch (e) { console.error('FAIL', e.message); await shot(page, 'failure'); } finally { await browser.close(); }
