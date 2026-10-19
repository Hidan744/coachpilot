import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../team/team_form.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(authProvider).name;
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Добро пожаловать${name.isEmpty ? '' : ', $name'}!', style: t.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Создайте первую команду. Её возраст, уровень и инвентарь будут учитываться при подборе упражнений и AI-генерации тренировок.',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TeamForm(submitLabel: 'Создать команду', onSaved: (_) => ref.invalidate(onboardedProvider)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await ref.read(dbProvider).setKv('onboarding_skipped', '1');
                    ref.invalidate(onboardedProvider);
                  },
                  child: const Text('Пропустить'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
