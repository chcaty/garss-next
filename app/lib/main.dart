import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ui/home.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: GarssApp()));
}

class GarssApp extends StatelessWidget {
  const GarssApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '嘎!RSS',
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    theme: appTheme,
    home: const HomeScreen(),
  );
}
