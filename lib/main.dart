import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/permission_service.dart';
import 'ui/main_screen.dart';
import 'config/theme_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _permissionsOk = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    bool ok = await PermissionService.hasAllPermissions();
    if (!ok) {
      ok = await PermissionService.requestAll();
    }
    setState(() => _permissionsOk = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionsOk) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: _checkPermissions,
              child: const Text('Włącz wymagane uprawnienia'),
            ),
          ),
        ),
      );
    }

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Indoor Navigator',
          theme: themeProvider.currentTheme,
          home: MainScreen(),
        );
      },
    );
  }
}