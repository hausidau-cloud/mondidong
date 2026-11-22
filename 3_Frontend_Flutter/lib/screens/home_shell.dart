import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'alerts_screen.dart';
import 'hub_screen.dart';
import 'map_screen.dart';
import 'messages_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _openAlerts = 0;
  int _unreadMessages = 0;
  int _lastReadMsgId = 0;
  int _latestMsgId = 0;
  int? _lastNotifiedMsgId;
  bool _readIdLoaded = false;
  Set<int>? _seen;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadReadState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    ScaffoldMessenger.of(context).clearSnackBars();
    super.dispose();
  }

  Future<void> _loadReadState() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final saved = sp.getInt('last_read_team_message_id');
      if (saved != null) {
        _lastReadMsgId = saved;
        _readIdLoaded = true;
      }
    } catch (_) {}
  }

  void _setTab(int i) {
    setState(() {
      _tab = i;
      if (_tab == 3) {
        _unreadMessages = 0;
        if (_latestMsgId > _lastReadMsgId) {
          _lastReadMsgId = _latestMsgId;
          SharedPreferences.getInstance().then((sp) {
            sp.setInt('last_read_team_message_id', _lastReadMsgId);
          });
        }
      }
    });
  }

  /// Kiem tra canh bao va tin nhan moi de bao ngay
  Future<void> _poll() async {
    if (!Session.I.loggedIn) return;
    try {
      // 1. Kiem tra canh bao
      final a = await Session.I.alerts(state: 'open', limit: 20);
      if (!mounted || !Session.I.loggedIn) return;

      final user = Session.I.user;
      final bool isAdmin = Session.I.isAdmin;
      final assignedStationIds = user?.stationIds ?? [];

      // Loc danh sach canh bao theo quyen: admin thay het, viewer chi thay tram duoc phan cong
      final userRows = isAdmin
          ? a.rows
          : a.rows.where((r) => assignedStationIds.contains(r.stationId ?? r.deviceId)).toList();

      final ids = userRows.map((e) => e.id).toSet();
      if (_seen != null) {
        final fresh = userRows.where((r) => !_seen!.contains(r.id)).toList();
        if (fresh.isNotEmpty && Session.I.loggedIn) {
          final r = fresh.first;
          final danger = r.level == 'DANGER';
          HapticFeedback.heavyImpact();
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
            action: SnackBarAction(label: 'XEM', onPressed: () => _setTab(2)),
          ));
        }
        _seen!.addAll(ids);
      } else {
        _seen = ids;
      }

      // 2. Kiem tra tin nhan moi de dem so tin chua doc
      int unread = 0;
      try {
        final msgs = await Session.I.teamMessages(limit: 50);
        if (msgs.isNotEmpty) {
          final currentUserId = Session.I.user?.id ?? 0;
          final maxId = msgs.map((m) => m.id).reduce((x, y) => x > y ? x : y);
          _latestMsgId = maxId;

          // Neu lan dau chay app chua co lich su doc, set _lastReadMsgId la tin nhan moi nhat
          if (!_readIdLoaded) {
            _lastReadMsgId = maxId;
            _lastNotifiedMsgId = maxId;
            _readIdLoaded = true;
            final sp = await SharedPreferences.getInstance();
            await sp.setInt('last_read_team_message_id', maxId);
          }

          if (_tab == 3) {
            // Dang o tab Tin nhan
            unread = 0;
            if (maxId > _lastReadMsgId) {
              _lastReadMsgId = maxId;
              final sp = await SharedPreferences.getInstance();
              await sp.setInt('last_read_team_message_id', maxId);
            }
          } else {
            // Dang o tab khac: dem tin nhan tu nguoi khac gui den sau _lastReadMsgId
            final unreadList = msgs.where((m) => m.id > _lastReadMsgId && m.userId != currentUserId).toList();
            unread = unreadList.length;

            if (unreadList.isNotEmpty) {
              final newest = unreadList.last;
              if (_lastNotifiedMsgId == null || newest.id > _lastNotifiedMsgId!) {
                _lastNotifiedMsgId = newest.id;
                final isIncident = newest.category == 'INCIDENT';
                HapticFeedback.mediumImpact();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    duration: const Duration(seconds: 4),
                    backgroundColor: isIncident ? const Color(0xFF3A1320) : AppColors.surface3,
                    content: Row(children: [
                      Icon(
                        isIncident ? Icons.emergency_rounded : Icons.forum_rounded,
                        color: isIncident ? AppColors.danger : const Color(0xFF38BDF8),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('${newest.senderName} (${newest.category})', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 13)),
                          Text(newest.content, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                        ]),
                      ),
                    ]),
                    action: SnackBarAction(label: 'XEM', onPressed: () => _setTab(3)),
                  ));
                }
              }
            }
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _openAlerts = isAdmin ? a.openTotal : userRows.length;
          _unreadMessages = unread;
        });
      }
    } catch (_) {
      // Bo qua: man hinh con se tu bao loi ket noi
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = [
      const HubScreen(),
      const MapScreen(),
      AlertsScreen(onChanged: _poll),
      MessagesScreen(
        onLatestMessageSeen: (latestId) {
          if (latestId > _lastReadMsgId) {
            _lastReadMsgId = latestId;
            _latestMsgId = latestId;
            if (mounted && _unreadMessages > 0) {
              setState(() => _unreadMessages = 0);
            }
            SharedPreferences.getInstance().then((sp) {
              sp.setInt('last_read_team_message_id', latestId);
            });
          }
        },
      ),
      const SettingsScreen(),
    ];
    Widget alertBadge(IconData i) => Badge(
          isLabelVisible: _openAlerts > 0,
          backgroundColor: AppColors.danger,
          label: Text('$_openAlerts'),
          child: Icon(i),
        );
    Widget messageBadge(IconData i) => Badge(
          isLabelVisible: _unreadMessages > 0,
          backgroundColor: AppColors.danger,
          label: Text('$_unreadMessages'),
          child: Icon(i),
        );

    final body = IndexedStack(index: _tab, children: pages);

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: _setTab,
            labelType: NavigationRailLabelType.all,
            minWidth: 92,
            leading: const Padding(padding: EdgeInsets.only(top: 12, bottom: 20), child: BrandLogo(size: 42)),
            destinations: [
              const NavigationRailDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: Text('Tổng quan')),
              const NavigationRailDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: Text('Bản đồ GIS')),
              NavigationRailDestination(icon: alertBadge(Icons.notifications_none_rounded), selectedIcon: alertBadge(Icons.notifications_rounded), label: const Text('Cảnh báo')),
              NavigationRailDestination(icon: messageBadge(Icons.forum_outlined), selectedIcon: messageBadge(Icons.forum_rounded), label: const Text('Tin nhắn')),
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
        onDestinationSelected: _setTab,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'Tổng quan'),
          const NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'Bản đồ GIS'),
          NavigationDestination(icon: alertBadge(Icons.notifications_none_rounded), selectedIcon: alertBadge(Icons.notifications_rounded), label: 'Cảnh báo'),
          NavigationDestination(icon: messageBadge(Icons.forum_outlined), selectedIcon: messageBadge(Icons.forum_rounded), label: 'Tin nhắn'),
          const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Tài khoản'),
        ],
      ),
    );
  }
}
