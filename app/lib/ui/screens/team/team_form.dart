import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';

/// Форма команды: используется в онбординге, при создании и редактировании.
class TeamForm extends ConsumerStatefulWidget {
  const TeamForm({super.key, this.team, required this.onSaved, this.submitLabel = 'Сохранить'});

  final Team? team;
  final void Function(Team team) onSaved;
  final String submitLabel;

  @override
  ConsumerState<TeamForm> createState() => _TeamFormState();
}

class _TeamFormState extends ConsumerState<TeamForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.team?.name);
  late final _players = TextEditingController(text: '${widget.team?.defaultPlayers ?? 14}');
  late String _age = widget.team?.ageGroup ?? 'U12';
  late String _level = widget.team?.level ?? 'amateur';
  late final Set<String> _equipment = {...widget.team?.equipment ?? ['balls', 'cones', 'bibs', 'goals']};

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final team = Team(
      id: widget.team?.id ?? newId(),
      name: _name.text.trim(),
      ageGroup: _age,
      level: _level,
      defaultPlayers: int.parse(_players.text),
      equipment: _equipment.toList(),
      notes: widget.team?.notes ?? '',
    );
    await ref.read(repoProvider).put(Entities.teams, team);
    ref.read(currentTeamIdProvider.notifier).select(team.id);
    widget.onSaved(team);
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            key: const Key('team_name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Название команды', hintText: 'Например, «Спартак-2014»'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Введите название' : null,
          ),
          const SizedBox(height: 16),
          Text('Возрастная группа', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in AgeGroups.all)
              ChoiceChip(label: Text(AgeGroups.label(g)), selected: _age == g, onSelected: (_) => setState(() => _age = g)),
          ]),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _level,
            decoration: const InputDecoration(labelText: 'Уровень'),
            items: [for (final e in Levels.all.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _level = v!),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('team_players'),
            controller: _players,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Обычно игроков на тренировке'),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < 1 || n > 60 ? 'От 1 до 60' : null;
            },
          ),
          const SizedBox(height: 16),
          Text('Доступный инвентарь', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in Equipment.all.entries)
              FilterChip(
                label: Text(e.value),
                selected: _equipment.contains(e.key),
                onSelected: (v) => setState(() => v ? _equipment.add(e.key) : _equipment.remove(e.key)),
              ),
          ]),
          const SizedBox(height: 24),
          FilledButton(key: const Key('team_save'), onPressed: _save, child: Text(widget.submitLabel)),
        ]),
      );
}
