// Статистика матча, тесты ОФП, профиль игрока, отчёт о прогрессе (PDF), выгрузка Excel и тренерский штаб.
import { readFileSync } from 'node:fs';

import { launch, fill, tap, see, shot, step, registerWithTeam, go } from './lib.mjs';

const { browser, page } = await launch();
try {
  await registerWithTeam(page, { team: 'Амкар U16' });
  await tap(page, 'Команда');
  await tap(page, 'Игрок');
  await fill(page, 'Имя', 'Ваня');
  await fill(page, 'Фамилия (необязательно)', 'Сидоров');
  await tap(page, 'Нападающий');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Ваня Сидоров');
  step('игрок добавлен');

  // 1. Матч и его статистика
  await tap(page, 'Календарь');
  await tap(page, 'Матч', { exact: true });
  await fill(page, 'Соперник', 'Урал U16');
  await tap(page, 'Статистика матча');
  await see(page, 'Статистика: Урал U16');
  await tap(page, 'Играл: Ваня Сидоров');
  await see(page, 'Минуты');
  await tap(page, 'Голы: больше');
  await tap(page, 'Голы: больше');
  await tap(page, 'Удары: больше');
  await shot(page, 'perf-01-match-stats');
  step('статистика матча введена');

  // 2. Профиль игрока: статистика сезона
  await tap(page, 'Команда');
  await tap(page, 'Ваня Сидоров');
  await see(page, 'Обзор');
  await tap(page, 'Статистика', { exact: true });
  await see(page, 'Гол+пас');
  // Гол засчитывается как удар в створ: 3 удара, 2 в створ → 67%.
  await see(page, '67%');
  await shot(page, 'perf-02-player-stats');
  step('статистика попала в профиль');

  // 3. Тестирование ОФП
  await tap(page, 'ОФП', { exact: true });
  await tap(page, 'Новое тестирование');
  await fill(page, 'Бег 10 м, с', '1,85');
  await fill(page, 'Бег 30 м, с', '4.6');
  await fill(page, 'Прыжок в длину с места, см', '215');
  await tap(page, 'Сохранить результаты');
  await see(page, 'Физический профиль');
  await see(page, 'Первое тестирование');
  await shot(page, 'perf-03-physical');
  step('тест ОФП: радар и баллы');

  // 4. Отчёт о прогрессе в PDF
  await tap(page, 'Отчёт о прогрессе');
  await see(page, 'ОТЧЁТ О ПРОГРЕССЕ');
  await shot(page, 'perf-04-report');
  const pdf = page.waitForEvent('download', { timeout: 30000 });
  await tap(page, 'Скачать PDF');
  const d1 = await pdf;
  if (!d1.suggestedFilename().endsWith('.pdf')) throw new Error(`не PDF: ${d1.suggestedFilename()}`);
  const head = readFileSync(await d1.path()).subarray(0, 5).toString();
  if (head !== '%PDF-') throw new Error('файл не PDF: ' + head);
  step(`PDF-отчёт скачан: ${d1.suggestedFilename()}`);
  await go(page, '/team');

  // 5. Дашборд команды и выгрузка Excel
  await tap(page, 'Дашборд', { exact: true });
  await see(page, 'Посещаемость по неделям');
  await shot(page, 'perf-05-dashboard');
  // Отчёты — внизу дашборда: прокручиваем к ним.
  await page.mouse.move(200, 500);
  await page.mouse.wheel(0, 3000);
  await page.waitForTimeout(800);
  const xlsx = page.waitForEvent('download', { timeout: 30000 });
  await tap(page, 'Для штаба: Excel');
  const d2 = await xlsx;
  if (!d2.suggestedFilename().endsWith('.xlsx')) throw new Error(`не Excel: ${d2.suggestedFilename()}`);
  // xlsx — zip-архив: начинается с PK.
  if (readFileSync(await d2.path()).subarray(0, 2).toString() !== 'PK') throw new Error('файл не xlsx');
  step(`Excel скачан: ${d2.suggestedFilename()}`);

  // 6. Тренерский штаб
  await tap(page, 'Профиль');
  await tap(page, 'Добавить', { exact: true });
  await fill(page, 'Имя и фамилия', 'Олег Ткачёв');
  await tap(page, 'Тренер по ОФП');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Олег Ткачёв');
  await shot(page, 'perf-06-staff');
  step('тренер по ОФП добавлен в штаб');
  console.log('PERFORMANCE E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
