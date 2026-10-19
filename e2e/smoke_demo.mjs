// Демо-версия без сервера: весь цикл работает в браузере, данные переживают перезагрузку.
import { launch, open, fill, tap, see, shot, step, enableSemantics } from './lib.mjs';

const URL = process.env.DEMO_URL ?? 'http://localhost:8081';
const { browser, page } = await launch();
try {
  await open(page, URL);
  await see(page, 'Добро пожаловать, Тренер');
  await fill(page, 'Название команды', 'Динамо U10');
  await tap(page, 'U10', { exact: true });
  await tap(page, 'Создать команду');
  await see(page, 'Привет, Тренер');
  step('демо открылось без регистрации, команда создана');

  await tap(page, 'Создать тренировку с AI');
  await tap(page, 'Удары по воротам');
  await tap(page, 'Сгенерировать план');
  await see(page, 'План собран по правилам из библиотеки');
  await see(page, 'Σ 75 / 75 мин');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Провести');
  step('план из библиотеки');

  await page.waitForTimeout(3000);
  await tap(page, 'Провести');
  await see(page, '1 / ');
  await tap(page, 'Старт');
  await page.waitForTimeout(1500);
  await tap(page, 'Далее');
  await tap(page, 'Завершить', { exact: true });
  await tap(page, 'Завершить', { exact: true });
  await see(page, 'Отчёт о занятии');
  await fill(page, 'Что получилось', 'Хорошая концентрация');
  await tap(page, 'Подтвердить отчёт');
  await see(page, 'Итоги занятия');
  step('проведение и отчёт');

  await page.reload();
  await enableSemantics(page);
  await see(page, 'Хорошая концентрация');
  await tap(page, 'Главная');
  await see(page, 'Недавние занятия');
  await tap(page, 'Профиль');
  await see(page, 'Вы в демо-режиме');
  await shot(page, 'demo-profile');
  step('после перезагрузки данные на месте');
  console.log('DEMO E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
