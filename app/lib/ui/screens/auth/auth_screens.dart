import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: t.colorScheme.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.sports_soccer, size: 46, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                if (AppBrand.clubName.isNotEmpty)
                  Text(
                    AppBrand.clubName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary, letterSpacing: 2),
                  ),
                Text(
                  AppBrand.appName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineLarge?.copyWith(letterSpacing: 1.5),
                ),
                Text('Тренерский штаб · AI-помощник', textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
                const SizedBox(height: 32),
                Text(title, style: t.textTheme.titleLarge),
                const SizedBox(height: 16),
                ...children,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

String? _emailError(String? v) =>
    v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? 'Введите корректный email' : null;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).login(_email.text, _password.text);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(title: 'Вход', children: [
        Form(
          key: _form,
          child: Column(children: [
            TextFormField(
              key: const Key('login_email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: _emailError,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('login_password'),
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль'),
              validator: (v) => (v ?? '').isEmpty ? 'Введите пароль' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('login_submit'),
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Войти'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => context.go('/register'), child: const Text('Нет аккаунта? Зарегистрироваться')),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => ref.read(authProvider.notifier).startDemo(),
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('Попробовать без регистрации'),
        ),
        const SizedBox(height: 4),
        Text(
          'Демо-режим: данные хранятся только на этом устройстве, планы собираются из библиотеки без AI.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ]);
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  String _role = 'coach';

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_consent) {
      showInfo(context, 'Нужно согласие на обработку персональных данных');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).register(_name.text, _email.text, _password.text, role: _role);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(title: 'Регистрация', children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'coach', label: Text('Тренер')),
            ButtonSegment(value: 'parent', label: Text('Родитель')),
            ButtonSegment(value: 'player', label: Text('Игрок')),
          ],
          selected: {_role},
          onSelectionChanged: (v) => setState(() => _role = v.first),
        ),
        if (_role != 'coach')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('После регистрации введите код от тренера — откроется расписание и задания игрока.'),
          ),
        const SizedBox(height: 12),
        Form(
          key: _form,
          child: Column(children: [
            TextFormField(
              key: const Key('reg_name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Имя'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Введите имя' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('reg_email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: _emailError,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('reg_password'),
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль', helperText: 'Не меньше 8 символов'),
              validator: (v) => (v ?? '').length < 8 ? 'Не меньше 8 символов' : null,
            ),
          ]),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('reg_consent'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _consent,
          onChanged: (v) => setState(() => _consent = v ?? false),
          title: const Text('Согласен на обработку персональных данных и с политикой конфиденциальности'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('reg_submit'),
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Создать аккаунт'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => context.go('/login'), child: const Text('Уже есть аккаунт? Войти')),
      ]);
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Icon(Icons.sports_soccer, size: 72, color: AppColors.red)));
}
