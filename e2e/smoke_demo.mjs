// Демо-версия без сервера: весь цикл работает в браузере, данные переживают перезагрузку.
import { launch, open, fill, tap, see, shot, step, enableSemantics, go } from './lib.mjs';

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
  await see(page, 'Локальный подбор по правилам');
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

  // Новое в демо: матч в календаре, доска, сообщение родителям текстом
  await go(page, '/calendar');
  await tap(page, 'Добавить');
  await tap(page, 'Соперник, дата, стадион');
  await fill(page, 'Соперник', 'Звезда U10');
  await tap(page, 'Сохранить', { exact: true });
  await see(page, 'Звезда U10');
  await tap(page, 'Тактическая доска');
  await tap(page, 'Новая доска');
  await see(page, 'Поле тактической доски');
  await go(page, '/team');
  await tap(page, 'Игрок');
  await fill(page, 'Имя', 'Коля');
  await tap(page, 'Сохранить', { exact: true });
  await tap(page, 'Коля');
  await tap(page, 'Родителям', { exact: true });
  await tap(page, 'Написать');
  await fill(page, 'Текст', 'Больше сна перед игрой');
  await tap(page, 'Сохранить', { exact: true });
  await tap(page, 'Ссылка для родителей');
  await see(page, 'В демо-режиме можно отправить родителям текст');
  await see(page, 'Больше сна перед игрой');
  await shot(page, 'demo-parents');
  step('календарь, доска и текст для родителей в демо');

  // Своя команда в демо: одна кнопка — и вся аналитика на своих игроках.
  await page.keyboard.press('Escape');
  await go(page, '/team?tab=1');
  await tap(page, 'Заполнить демо-данными');
  await see(page, 'Готово: история сезона');
  await go(page, '/team?tab=2');
  await see(page, 'Сезон: матчей сыграно 8');
  await tap(page, 'Физика');
  await see(page, 'Км/90');
  await shot(page, 'demo-own-team-stats');
  step('своя команда заполнена демо-данными: статистика и дашборд');
  console.log('DEMO E2E: OK');
} catch (e) {
  await shot(page, 'failure');
  console.error('FAIL:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
