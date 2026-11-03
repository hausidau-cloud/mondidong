import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<AppUser>? _users;
  List<Station>? _stations;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final u = await Session.I.users();
      final s = await Session.I.stations();
      if (!mounted) return;
      setState(() {
        _users = u;
        _stations = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }



  void _showEditStationsDialog(AppUser user) {
    final selectedStationIds = Set<int>.from(user.stationIds);
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, color: AppColors.hum),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đổi trạm: ${user.fullName}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tài khoản @${user.username} sẽ chỉ giám sát các trạm được tick chọn bên dưới:',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    if (_stations == null || _stations!.isEmpty)
                      const Text('Không có trạm nào trong hệ thống', style: TextStyle(color: AppColors.muted))
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: _stations!.map((st) {
                            final checked = selectedStationIds.contains(st.id);
                            return CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: checked,
                              title: Text(st.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              subtitle: Text('${st.code} · ${st.location ?? "Chưa rõ vị trí"}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    selectedStationIds.add(st.id);
                                  } else {
                                    selectedStationIds.remove(st.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        try {
                          await Session.I.updateUserStations(user.id, selectedStationIds.toList());
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            toast(context, 'Đã cập nhật phân công cho ${user.fullName}!');
                            _loadData();
                          }
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (mounted) toast(context, e.toString(), error: true);
                        }
                      },
                icon: saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Cập nhật'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteUser(AppUser user) async {
    if (user.role == 'admin') {
      toast(context, 'Không thể xóa tài khoản Quản trị viên tối cao!', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Xác nhận xóa nhân viên?'),
        content: Text('Bạn có chắc muốn xóa tài khoản "${user.fullName} (@${user.username})"?\nNhân viên này sẽ bị hủy phân công khỏi toàn bộ các trạm.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await Session.I.deleteUser(user.id);
        if (mounted) {
          toast(context, 'Đã xóa nhân viên ${user.fullName}');
          _loadData();
        }
      } catch (e) {
        if (mounted) toast(context, e.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w >= 600 ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: pad,
        title: const Text('Quản lý nhân sự & Phân công trạm'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _loadData, child: const Text('Thử lại')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withAlpha(20),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.accent.withAlpha(60)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 20),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Nhân viên tự đăng ký tài khoản tại màn hình đăng nhập (xác thực OTP). Tại đây, Admin quản lý phân công các trạm giám sát hoặc xóa tài khoản nhân viên.',
                                        style: TextStyle(fontSize: 12.5, color: AppColors.text, height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Danh sách nhân sự (${_users?.length ?? 0})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    'Tổng số trạm: ${_stations?.length ?? 0}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_users == null || _users!.isEmpty)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Text('Chưa có nhân viên nào trong hệ thống', style: TextStyle(color: AppColors.muted)),
                                  ),
                                )
                              else
                                ..._users!.map((u) {
                                  final isAdmin = u.role == 'admin';
                                  final assignedStations = _stations?.where((s) => u.stationIds.contains(s.id)).toList() ?? [];

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                radius: 22,
                                                backgroundColor: isAdmin ? AppColors.accent.withAlpha(40) : AppColors.hum.withAlpha(40),
                                                child: Icon(
                                                  isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                                                  color: isAdmin ? AppColors.accent : AppColors.hum,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            u.fullName,
                                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: isAdmin ? AppColors.accent.withAlpha(30) : AppColors.hum.withAlpha(30),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            isAdmin ? 'Admin' : 'Viewer',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w700,
                                                              color: isAdmin ? AppColors.accent : AppColors.hum,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '@${u.username}',
                                                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (!isAdmin)
                                                PopupMenuButton<String>(
                                                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                                                  onSelected: (val) {
                                                    if (val == 'edit') {
                                                      _showEditStationsDialog(u);
                                                    } else if (val == 'delete') {
                                                      _confirmDeleteUser(u);
                                                    }
                                                  },
                                                  itemBuilder: (ctx) => [
                                                    const PopupMenuItem(
                                                      value: 'edit',
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.swap_horiz_rounded, size: 18, color: AppColors.hum),
                                                          SizedBox(width: 8),
                                                          Text('Đổi trạm phụ trách'),
                                                        ],
                                                      ),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                                          SizedBox(width: 8),
                                                          Text('Xóa nhân viên', style: TextStyle(color: AppColors.danger)),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          const Divider(height: 1),
                                          const SizedBox(height: 10),
                                          if (isAdmin)
                                            const Text(
                                              '⭐ Quản trị viên tối cao: Toàn quyền quản lý tất cả các trạm và thiết bị.',
                                              style: TextStyle(fontSize: 12, color: AppColors.accent),
                                            )
                                          else ...[
                                            Row(
                                              children: [
                                                const Icon(Icons.location_on_outlined, size: 15, color: AppColors.muted),
                                                const SizedBox(width: 5),
                                                const Text(
                                                  'Các trạm được phân công:',
                                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                                ),
                                                const Spacer(),
                                                InkWell(
                                                  onTap: () => _showEditStationsDialog(u),
                                                  child: const Padding(
                                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    child: Text(
                                                      'Chỉnh sửa',
                                                      style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            if (assignedStations.isEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warn.withAlpha(20),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppColors.warn.withAlpha(60)),
                                                ),
                                                child: const Text(
                                                  '⚠️ Chưa được phân công trạm nào (Nhân viên sẽ thấy danh sách trống)',
                                                  style: TextStyle(fontSize: 11.5, color: AppColors.warn),
                                                ),
                                              )
                                            else
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: assignedStations.map((st) {
                                                  return Chip(
                                                    visualDensity: VisualDensity.compact,
                                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                                    avatar: const Icon(Icons.sensors_rounded, size: 14, color: AppColors.accent),
                                                    label: Text(
                                                      '${st.code}: ${st.name}',
                                                      style: const TextStyle(fontSize: 11.5),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
