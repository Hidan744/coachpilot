// Демо на широком экране: приложение показывается в рамке планшета, рядом — витрина возможностей.
// Планшет подбирается по высоте окна и всегда целиком помещается на экране.
// На телефоне и планшете рамки нет — приложение занимает весь экран.

import 'package:flutter/material.dart';

import '../theme.dart';

class DemoFrame extends StatelessWidget {
  const DemoFrame({super.key, required this.child, required this.onOpen});

  final Widget child;

  /// Переход на экран приложения по ссылке из витрины (например, '/team?tab=1').
  final ValueChanged<String> onOpen;

  static const _features = [
    (Icons.space_dashboard_outlined, 'Дашборд тренера', 'Посещаемость, нагрузка, ОФП, результаты — на главной', '/'),
    (Icons.insights_outlined, 'Дашборд команды', 'Графики по неделям, структура нагрузки, лидеры', '/team?tab=1'),
    (Icons.query_stats, 'Статистика игроков', 'Голы, передачи, удары, рейтинг — как в профи', '/team?tab=2'),
    (Icons.person_search_outlined, 'Профиль игрока', 'ОФП-радар, программа развития, отчёт для родителей', '/team'),
    (Icons.calendar_month_outlined, 'Календарь сезона', 'Матчи, расписание команд, тренировки', '/calendar'),
    (Icons.draw_outlined, 'Тактическая доска', 'Расстановка, рисование пальцем, замены', '/tactics'),
    (Icons.groups_2_outlined, 'Состав под тактику', 'Схема и стиль игры → лучший игрок на каждое место', '/tactics/lineup'),
    (Icons.auto_awesome, 'Конструктор тренировки', 'Цель, формат, интенсивность → план с таймингом и пояснениями', '/sessions/new'),
    (Icons.menu_book_outlined, 'Библиотека упражнений', 'Анимированные схемы, свои упражнения', '/library'),
  ];

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    // Узкий экран — обычное приложение на весь экран.
    if (size.width < 900 || size.height < 600) return child;

    // Планшет в портрете 3:4 по высоте окна; витрина слева, если хватает ширины.
    const bezel = 14.0, margin = 24.0, showcaseWidth = 420.0, gap = 56.0;
    var frameH = (size.height - 2 * margin).clamp(560.0, 1180.0);
    var frameW = frameH * 0.75;
    final showcase = size.width >= frameW + showcaseWidth + gap + 2 * margin;
    if (!showcase && frameW > size.width - 2 * margin) {
      frameW = size.width - 2 * margin;
      frameH = frameW / 0.75;
    }
    final screen = Size(frameW - 2 * bezel, frameH - 2 * bezel);
    final tablet = Container(
      width: frameW,
      height: frameH,
      padding: const EdgeInsets.all(bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFF2A2A2E), width: 2),
        boxShadow: [
          BoxShadow(color: AppColors.red.withValues(alpha: 0.22), blurRadius: 90, spreadRadius: 4),
          const BoxShadow(color: Colors.black, blurRadius: 30, offset: Offset(0, 20)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: MediaQuery(
          data: mq.copyWith(size: screen, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
          child: SizedBox.fromSize(size: screen, child: child),
        ),
      ),
    );

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
                if (showcase) ...[
                  // На невысоком экране витрина прокручивается, а не обрезается.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: showcaseWidth, maxHeight: size.height),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: margin),
                      child: _Showcase(onOpen: onOpen),
                    ),
                  ),
                  const SizedBox(width: gap),
                ],
                tablet,
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
        if (AppBrand.build.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Версия от ${AppBrand.build}', style: TextStyle(fontSize: 12, color: Color(0xFF5A5A62))),
          ),
      ],
    ),
  );
}
