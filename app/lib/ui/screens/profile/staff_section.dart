import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../team/performance_providers.dart';
import '../team/team_dashboard.dart';

/// Тренерский штаб и отчётность в профиле.
class StaffAndReportsSection extends ConsumerWidget {
  const StaffAndReportsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = [...ref.watch(staffProvider).value ?? const <StaffMember>[]]
      ..sort((a, b) => StaffRoles.all.keys.toList().indexOf(a.role).compareTo(StaffRoles.all.keys.toList().indexOf(b.role)));
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final teamNames = {for (final t in teams) t.id: t.name};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        'Тренерский штаб',
        trailing: TextButton.icon(
          onPressed: () => showStaffForm(context, ref),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Добавить'),
        ),
      ),
      if (staff.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Ассистенты, тренер вратарей, тренер по ОФП, врач — с контактами и командами, с которыми работают.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      for (final s in staff)
        ListTile(
          leading: CircleAvatar(
            backgroundColor: s.role == 'fitness' ? AppColors.red : AppColors.surfaceHighest,
            child: Icon(switch (s.role) {
              'goalkeeper' => Icons.sports_handball,
              'fitness' => Icons.fitness_center,
              'doctor' => Icons.medical_services_outlined,
              'analyst' => Icons.insights,
              _ => Icons.sports,
            }, color: Colors.white, size: 20),
          ),
          title: Text(s.name),
          subtitle: Text([
            StaffRoles.all[s.role] ?? s.role,
            if (s.teamIds.isNotEmpty) s.teamIds.map((id) => teamNames[id]).whereType<String>().join(', '),
            if (s.phone.isNotEmpty) s.phone,
          ].where((x) => x.isNotEmpty).join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showStaffForm(context, ref, member: s),
        ),
      const SectionTitle('Отчётность'),
      for (final t in teams)
        ListTile(
          leading: const Icon(Icons.table_chart_outlined, color: AppColors.red),
          title: Text('Excel: ${t.name}'),
          subtitle: const Text('Игроки, посещаемость, тренировки, статистика матчей, ОФП, штаб'),
          trailing: const Icon(Icons.download_outlined),
          onTap: () => exportTeamExcel(context, ref, t),
        ),
      ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.red),
        title: const Text('Отчёт о прогрессе игрока (PDF)'),
        subtitle: const Text('Команда → игрок → значок отчёта, или «Дашборд» → «Для игрока и родителей»'),
        onTap: () => context.go('/team'),
      ),
    ]);
  }
}

Future<void> showStaffForm(BuildContext context, WidgetRef ref, {StaffMember? member}) async {
  final name = TextEditingController(text: member?.name);
  final phone = TextEditingController(text: member?.phone);
  final email = TextEditingController(text: member?.email);
  var role = member?.role ?? 'assistant';
  final teamIds = {...?member?.teamIds};
  final teams = ref.read(teamsProvider).value ?? const <Team>[];
  final res = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(member == null ? 'Новый тренер' : 'Тренер', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              autofocus: member == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Имя и фамилия'),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in StaffRoles.all.entries)
                ChoiceChip(label: Text(e.value), selected: role == e.key, onSelected: (_) => set(() => role = e.key)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Телефон')),
            const SizedBox(height: 12),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            if (teams.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Команды', style: Theme.of(c).textTheme.labelLarge),
              Wrap(spacing: 6, children: [
                for (final t in teams)
                  FilterChip(
                    label: Text(t.name),
                    selected: teamIds.contains(t.id),
                    onSelected: (v) => set(() => v ? teamIds.add(t.id) : teamIds.remove(t.id)),
                  ),
              ]),
            ],
            const SizedBox(height: 16),
            Row(children: [
              if (member != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Удалить')),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Сохранить')),
            ]),
          ]),
        ),
      ),
    ),
  );
  final repo = ref.read(repoProvider);
  if (res == 'delete' && member != null) {
    await repo.remove(Entities.staff, member.id);
  } else if (res == 'save' && name.text.trim().isNotEmpty) {
    await repo.put(
      Entities.staff,
      StaffMember(
        id: member?.id ?? newId(),
        name: name.text.trim(),
        role: role,
        phone: phone.text.trim(),
        email: email.text.trim(),
        teamIds: teamIds.toList(),
        notes: member?.notes ?? '',
      ),
    );
  }
}
