import 'package:flutter/material.dart';

import '../widgets/common.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: const [SyncBadge()]),
        body: const EmptyState(icon: Icons.construction, title: 'Раздел в разработке'),
      );
}
