// Карточка рекомендаций: что сделать с интенсивностью и над чем работать игрокам.

import 'package:flutter/material.dart';

import '../../core/recommendations.dart';
import '../theme.dart';
import 'charts.dart';

class AdviceCard extends StatelessWidget {
  const AdviceCard({super.key, required this.title, required this.items, this.onTap, this.footer});

  final String title;
  final List<Advice> items;

  /// Нажатие на рекомендацию (например, открыть игрока).
  final void Function(Advice a)? onTap;
  final Widget? footer;

  static (IconData, Color) _look(String kind) => switch (kind) {
        'up' => (Icons.trending_up, AppColors.good),
        'down' => (Icons.trending_down, AppColors.warn),
        'keep' => (Icons.check_circle_outline, AppColors.good),
        'work' => (Icons.build_circle_outlined, AppColors.red),
        _ => (Icons.info_outline, AppColors.textMuted),
      };

  @override
  Widget build(BuildContext context) => DashCard(
        title: title,
        trailing: const Icon(Icons.auto_awesome, size: 18, color: AppColors.red),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (items.isEmpty)
            const Text('Пока мало данных: отметьте посещаемость, RPE в отчётах и тесты ОФП.', style: TextStyle(color: AppColors.textMuted)),
          for (final a in items)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap == null || a.playerId == null ? null : () => onTap!(a),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_look(a.kind).$1, color: _look(a.kind).$2, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(a.text, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ]),
                  ),
                  if (onTap != null && a.playerId != null) const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ]),
              ),
            ),
          ?footer,
        ]),
      );
}
