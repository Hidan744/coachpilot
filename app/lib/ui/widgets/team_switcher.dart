// Переключатель команд на виду: на главной и на экране команды, если команд несколько.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../theme.dart';

class TeamSwitcher extends ConsumerWidget {
  const TeamSwitcher({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    if (teams.length < 2) return const SizedBox.shrink();
    final current = ref.watch(currentTeamProvider);
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, padding: padding, children: [
        for (final t in teams)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(Icons.shield_outlined, size: 16, color: t.id == current?.id ? Colors.white : AppColors.red),
              label: Text(t.name),
              selected: t.id == current?.id,
              showCheckmark: false,
              selectedColor: AppColors.red,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: t.id == current?.id ? Colors.white : AppColors.text,
              ),
              onSelected: (_) => ref.read(currentTeamIdProvider.notifier).select(t.id),
            ),
          ),
      ]),
    );
  }
}
