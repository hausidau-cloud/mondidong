import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// Hộp thoại hiển thị mã QR Trạm cho Quản trị viên (Admin)
class StationQrDialog extends StatelessWidget {
  final Station station;

  const StationQrDialog({super.key, required this.station});

  static void show(BuildContext context, Station station) {
    showDialog(
      context: context,
      builder: (_) => StationQrDialog(station: station),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = station.inviteCode ?? 'TG-S${station.id}-8842';
    final qrData = station.qrData ?? 'TG_JOIN:${station.id}:$code';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.air.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.qr_code_2_rounded, color: AppColors.air, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(station.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('Mã QR mời tham gia trạm', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.air.withValues(alpha: 0.2),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 210.0,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0F172A),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderStrong),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        code,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 1.1,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.muted),
                      tooltip: 'Sao chép mã',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Đã sao chép mã trạm "$code" vào bộ nhớ tạm!'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nhân viên dùng camera trên App ThermoGuard quét mã QR này để tự động kết nối vào trạm giám sát.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

/// Hộp thoại Quét mã QR hoặc Nhập mã vào trạm cho Nhân viên (Staff)
class JoinStationDialog extends StatefulWidget {
  final VoidCallback? onSuccess;

  const JoinStationDialog({super.key, this.onSuccess});

  static void show(BuildContext context, {VoidCallback? onSuccess}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => JoinStationDialog(onSuccess: onSuccess),
    );
  }

  @override
  State<JoinStationDialog> createState() => _JoinStationDialogState();
}

class _JoinStationDialogState extends State<JoinStationDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _codeCtrl = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _busy = false;
  String? _err;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeCtrl.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _submitCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) {
      setState(() => _err = 'Vui lòng nhập hoặc quét mã trạm');
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      final res = await Session.I.joinStation(code);
      if (!mounted) return;
      Navigator.pop(context);
      final msg = res['message'] ?? 'Kết nối vào trạm thành công!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.ok, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(msg.toString(), style: const TextStyle(color: Colors.white))),
            ],
          ),
          backgroundColor: const Color(0xFF133E26),
          duration: const Duration(seconds: 4),
        ),
      );
      widget.onSuccess?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _busy = false;
        _scanned = false; // Cho phép quét lại nếu lỗi
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned || _busy) return;
    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _scanned = true;
        _submitCode(raw.trim());
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Kết nối vào trạm', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              tabAlignment: TabAlignment.fill,
              isScrollable: false,
              labelColor: AppColors.air,
              unselectedLabelColor: AppColors.muted,
              indicatorColor: AppColors.air,
              tabs: const [
                Tab(icon: Icon(Icons.camera_alt_rounded, size: 18), text: 'Quét camera'),
                Tab(icon: Icon(Icons.keyboard_rounded, size: 18), text: 'Nhập mã tay'),
              ],
            ),
            const SizedBox(height: 14),
            if (_err != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_err!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5))),
                  ],
                ),
              ),
            SizedBox(
              height: 280,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Camera Scanner
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: MobileScanner(
                            controller: _scannerController,
                            onDetect: _onDetect,
                            placeholderBuilder: (context) => Container(
                              color: const Color(0xFF0F172A),
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: AppColors.air),
                                    SizedBox(height: 12),
                                    Text('Đang khởi động camera...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                            errorBuilder: (context, error) {
                              return Container(
                                color: const Color(0xFF0F172A),
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.videocam_off_rounded, color: AppColors.warn, size: 36),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Không thể mở camera (${error.errorCode.name})\nVui lòng cấp quyền Camera hoặc dùng Tab "Nhập mã tay"',
                                        style: const TextStyle(color: AppColors.text2, fontSize: 12),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 10),
                                      TextButton.icon(
                                        onPressed: () => _tabController.animateTo(1),
                                        icon: const Icon(Icons.keyboard_rounded, size: 16),
                                        label: const Text('Chuyển sang nhập mã tay'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          width: 190,
                          height: 190,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.air, width: 2.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        if (_busy)
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: AppColors.air),
                                  SizedBox(height: 12),
                                  Text('Đang xác thực mã trạm...', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Đưa khung camera vào mã QR của trạm',
                              style: TextStyle(color: Colors.white70, fontSize: 11.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab 2: Manual text code input
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        const Text(
                          'Nhập mã số trạm (ID) hoặc mã mời do Quản trị viên cấp:',
                          style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _codeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'Mã trạm (VD: TG-S1-8842 hoặc 1)',
                            hintText: 'TG-S1-8842',
                            prefixIcon: const Icon(Icons.qr_code_rounded),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.paste_rounded),
                              tooltip: 'Dán từ bộ nhớ tạm',
                              onPressed: () async {
                                final data = await Clipboard.getData('text/plain');
                                if (data?.text != null) {
                                  _codeCtrl.text = data!.text!.trim();
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('Gợi ý mã nhanh:', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ActionChip(
                              label: const Text('Trạm 1 (Pico 2 W)'),
                              avatar: const Icon(Icons.sensors_rounded, size: 16),
                              onPressed: () => _codeCtrl.text = 'TG-S1-8842',
                            ),
                            ActionChip(
                              label: const Text('Trạm 2 (ESP32)'),
                              avatar: const Icon(Icons.memory_rounded, size: 16),
                              onPressed: () => _codeCtrl.text = 'TG-S2-8842',
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : () => _submitCode(_codeCtrl.text),
                            icon: _busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.link_rounded),
                            label: const Text('Xác nhận & Kết nối trạm'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy bỏ'),
        ),
      ],
    );
  }
}
