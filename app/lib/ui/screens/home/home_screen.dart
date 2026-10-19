import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(authProvider).name;
    final team = ref.watch(currentTeamProvider);
    return Scaffold(
      appBar: AppBar(title: Text(name.isEmpty ? 'CoachPilot' : 'Привет, $name'), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (team != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(team.name),
              subtitle: Text('${team.ageGroup} · ${team.defaultPlayers} игроков'),
            ),
          ),
      ]),
    );
  }
}
