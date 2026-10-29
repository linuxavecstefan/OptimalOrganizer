import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/database_service.dart';
import 'services/theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = DatabaseService();
  await db.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: db),
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: const OptimalOrganizerApp(),
    ),
  );
}
