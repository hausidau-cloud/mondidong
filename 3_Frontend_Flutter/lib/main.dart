import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'widgets/common.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint(">> Note tai file .env: $e");
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
  ));
  Session.I.load();
  runApp(const ThermoGuardApp());
}

class ThermoGuardApp extends StatelessWidget {
  const ThermoGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThermoGuard',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: const AuthGate(),
    );
  }
}

/// Chuyen giua man dang nhap va man chinh theo trang thai phien
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.I,
      builder: (context, _) {
        final s = Session.I;
        Widget child;
        if (!s.ready) {
          child = const _Splash(key: ValueKey('splash'));
        } else if (!s.loggedIn) {
          child = const LoginScreen(key: ValueKey('login'));
        } else {
          child = const HomeShell(key: ValueKey('home'));
        }
        return AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: child);
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          BrandLogo(size: 64),
          SizedBox(height: 20),
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
        ]),
      ),
    );
  }
}
