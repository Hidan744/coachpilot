// Демо на широком экране: приложение показывается в рамке телефона, рядом — витрина возможностей.
// На телефоне и планшете в портрете рамки нет — приложение занимает весь экран.

import 'package:flutter/material.dart';

import '../theme.dart';

class DemoFrame extends StatelessWidget {
  const DemoFrame({super.key, required this.child, required this.onOpen});

  final Widget child;

  /// Переход на экран приложения по ссылке из витрины (например, '/team?tab=1').
  final ValueChanged<String> onOpen;

  static const _phoneWidth = 400.0;

  static const _features = [
    (Icons.space_dashboard_outlined, 'Дашборд тренера', 'Посещаемость, нагрузка, ОФП, результаты — на главной', '/'),
    (Icons.insights_outlined, 'Дашборд команды', 'Графики по неделям, структура нагрузки, лидеры', '/team?tab=1'),
    (Icons.query_stats, 'Статистика игроков', 'Голы, передачи, удары, рейтинг — как в профи', '/team?tab=2'),
    (Icons.person_search_outlined, 'Профиль игрока', 'ОФП-радар, программа развития, отчёт для родителей', '/team'),
    (Icons.calendar_month_outlined, 'Календарь сезона', 'Матчи, расписание команд, тренировки', '/calendar'),
    (Icons.draw_outlined, 'Тактическая доска', 'Расстановка, рисование пальцем, замены', '/tactics'),
    (Icons.auto_awesome, 'Тренировка с AI', 'План занятия за минуту из библиотеки упражнений', '/sessions/new'),
    (Icons.menu_book_outlined, 'Библиотека упражнений', 'Анимированные схемы, свои упражнения', '/library'),
  ];

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    // Узкий экран — обычное приложение на весь экран.
    if (size.width < 760 || size.height < 560) return child;

    final phoneHeight = (size.height - 48).clamp(560.0, 900.0);
    final phone = Container(
      width: _phoneWidth + 16,
      height: phoneHeight + 16,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(44),
        border: Border.all(color: const Color(0xFF2A2A2E), width: 2),
        boxShadow: [
          BoxShadow(color: AppColors.red.withValues(alpha: 0.25), blurRadius: 80, spreadRadius: 4),
          const BoxShadow(color: Colors.black, blurRadius: 30, offset: Offset(0, 20)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: MediaQuery(
          data: mq.copyWith(
            size: Size(_phoneWidth, phoneHeight),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
          ),
          child: child,
        ),
      ),
    );

    final showcase = size.width >= 1080;
    return ColoredBox(
      color: const Color(0xFF0B0B0D),
      child: Stack(
        children: [
          // Красное свечение на фоне — фирменный стиль.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.35, -0.2),
                  radius: 1.1,
                  colors: [AppColors.red.withValues(alpha: 0.22), Colors.transparent],
                ),
              ),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showcase) ...[SizedBox(width: 440, child: _Showcase(onOpen: onOpen)), const SizedBox(width: 64)],
                phone,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Showcase extends StatelessWidget {
  const _Showcase({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(8)),
          child: const Text(
            'ДЕМО',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 2, fontSize: 12),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'CoachPilot AI',
          style: TextStyle(
            fontFamily: AppTheme.display,
            fontSize: 44,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Рабочее место футбольного тренера: тренировки, календарь, статистика и отчёты — '
          'понятно игроку, родителю, штабу и руководителю.',
          style: TextStyle(fontSize: 15, height: 1.4, color: Color(0xFFB8B8C0)),
        ),
        const SizedBox(height: 22),
        for (final f in DemoFrame._features)
          InkWell(
            // Без фокуса: иначе фокус остаётся вне приложения и мешает переходу между вкладками.
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(12),
            onTap: () => onOpen(f.$4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(f.$1, color: AppColors.red, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.$2,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
                        ),
                        Text(f.$3, style: const TextStyle(color: Color(0xFF8E8E98), fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF5A5A62), size: 20),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        const Text(
          'Все данные — пример команды. Нажимайте, меняйте, создавайте: демо работает прямо в браузере.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF8E8E98)),
        ),
      ],
    ),
  );
}
