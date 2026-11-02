import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'alerts_screen.dart';
import 'hub_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _openAlerts = 0;
  Set<int>? _seen;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Kiem tra canh bao moi de bao ngay (du dang o tab nao)
  Future<void> _poll() async {
    try {
      final a = await Session.I.alerts(state: 'open', limit: 20);
      if (!mounted) return;
      final ids = a.rows.map((e) => e.id).toSet();
      if (_seen != null) {
        final fresh = a.rows.where((r) => !_seen!.contains(r.id)).toList();
        if (fresh.isNotEmpty) {
          final r = fresh.first;
          final danger = r.level == 'DANGER';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 6),
            backgroundColor: danger ? const Color(0xFF3A1320) : AppColors.surface3,
            content: Row(children: [
              Icon(danger ? Icons.emergency_rounded : Icons.warning_amber_rounded, color: danger ? AppColors.danger : AppColors.warn),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(r.deviceName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                  Text(r.message, style: const TextStyle(color: AppColors.text2, fontSize: 12.5)),
                ]),
              ),
            ]),
            action: SnackBarAction(label: 'XEM', onPressed: () => setState(() => _tab = 1)),
          ));
        }
        _seen!.addAll(ids);
      } else {
        _seen = ids;
      }
      setState(() => _openAlerts = a.openTotal);
    } catch (_) {
      // Bo qua: man hinh con se tu bao loi ket noi
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = [
      const HubScreen(),
      AlertsScreen(onChanged: _poll),
      const SettingsScreen(),
    ];
    Widget badgeIcon(IconData i) => Badge(
          isLabelVisible: _openAlerts > 0,
          backgroundColor: AppColors.danger,
          label: Text('$_openAlerts'),
          child: Icon(i),
        );

    final body = IndexedStack(index: _tab, children: pages);

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            minWidth: 92,
            leading: const Padding(padding: EdgeInsets.only(top: 12, bottom: 20), child: BrandLogo(size: 42)),
            destinations: [
              const NavigationRailDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: Text('Tổng quan')),
              NavigationRailDestination(icon: badgeIcon(Icons.notifications_none_rounded), selectedIcon: badgeIcon(Icons.notifications_rounded), label: const Text('Cảnh báo')),
              const NavigationRailDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: Text('Tài khoản')),
            ],
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(child: body),
        ]),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'Tổng quan'),
          NavigationDestination(icon: badgeIcon(Icons.notifications_none_rounded), selectedIcon: badgeIcon(Icons.notifications_rounded), label: 'Cảnh báo'),
          const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Tài khoản'),
        ],
      ),
    );
  }
}
