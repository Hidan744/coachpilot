import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lineup.dart';
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
  late String _formation = widget.team?.formation ?? '';
  late final List<TeamGoal> _goals = [...widget.team?.seasonGoals ?? const <TeamGoal>[]];
  final _goal = TextEditingController();

  void _addGoal() {
    final t = _goal.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _goals.add(TeamGoal(t));
      _goal.clear();
    });
  }

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
      formation: _formation,
      seasonGoals: [..._goals, if (_goal.text.trim().isNotEmpty) TeamGoal(_goal.text.trim())],
    );
    await ref.read(repoProvider).put(Entities.teams, team);
    if (widget.team == null) ref.read(analyticsProvider).track('team_created', {'age_group': team.ageGroup});
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
          const SizedBox(height: 16),
          Text('Основная игровая схема', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('Не задана'), selected: _formation.isEmpty, onSelected: (_) => setState(() => _formation = '')),
            for (final f in formationsFor(int.tryParse(_players.text) ?? 11))
              ChoiceChip(label: Text(f), selected: _formation == f, onSelected: (_) => setState(() => _formation = f)),
          ]),
          const SizedBox(height: 16),
          Text('Цели на сезон', style: Theme.of(context).textTheme.labelLarge),
          for (var i = 0; i < _goals.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(_goals[i].done ? Icons.check_circle : Icons.flag_outlined),
              title: Text(_goals[i].text),
              trailing: IconButton(
                tooltip: 'Удалить цель',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _goals.removeAt(i)),
              ),
            ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _goal,
                maxLength: 300,
                decoration: const InputDecoration(hintText: 'Например: войти в тройку лиги', counterText: ''),
                onSubmitted: (_) => _addGoal(),
              ),
            ),
            IconButton(tooltip: 'Добавить цель', onPressed: _addGoal, icon: const Icon(Icons.add_circle_outline)),
          ]),
          const SizedBox(height: 24),
          FilledButton(key: const Key('team_save'), onPressed: _save, child: Text(widget.submitLabel)),
        ]),
      );
}
