import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';

Future<void> showStationReportDialog(BuildContext context, Station station) {
  return showDialog(
    context: context,
    builder: (ctx) => _StationReportModal(station: station),
  );
}

class _StationReportModal extends StatefulWidget {
  final Station station;
  const _StationReportModal({required this.station});

  @override
  State<_StationReportModal> createState() => _StationReportModalState();
}

class _StationReportModalState extends State<_StationReportModal> {
  StationReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final r = await Session.I.stationReport(widget.station.id);
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _downloadCsv() async {
    final url = Session.I.csvReportUrl(widget.station.id);
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở liên kết tải tệp CSV')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải CSV: $e')));
      }
    }
  }

  Future<void> _openPdfReport() async {
    final url = Session.I.htmlReportUrl(widget.station.id);
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở liên kết báo cáo PDF')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi mở PDF: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: _loading
            ? const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 40),
                        const SizedBox(height: 12),
                        Text('Không thể tải báo cáo: $_error', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.text)),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _fetch, child: const Text('Thử lại')),
                      ],
                    ),
                  )
                : _buildContent(_report!),
      ),
    );
  }

  Widget _buildContent(StationReport r) {
    return Column(
      children: [
        // Modal Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assessment_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.reportTitle,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.text),
                    ),
                    Text(
                      r.projectName,
                      style: const TextStyle(fontSize: 12, color: AppColors.primaryLight, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.text2),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),

        // Scrollable Report Body
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Thông tin định danh trạm & Tọa độ
              _sectionTitle('1. ĐỊNH DANH TRẠM & PHẦN CỨNG IOT'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _infoRow('Tên trạm:', r.stationName),
                    _infoRow('Mã vi điều khiển:', r.deviceCode),
                    _infoRow('Firmware:', r.firmware),
                    _infoRow('Vị trí GIS:', r.location),
                    _infoRow('Trạng thái hiện tại:', r.status),
                    _infoRow('Thiết bị tải ngoại vi:', r.relayLabel),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Thống kê số đo vi khí hậu
              _sectionTitle('2. THỐNG KÊ VI KHÍ HẬU (24H QUA)'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _statBox(
                      'Nhiệt độ khí (°C)',
                      'Min: ${r.minTemp ?? '--'}°C\nMax: ${r.maxTemp ?? '--'}°C\nTB: ${r.avgTemp ?? '--'}°C',
                      AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statBox(
                      'Độ ẩm không khí (%)',
                      'Min: ${r.minHum ?? '--'}%\nMax: ${r.maxHum ?? '--'}%\nTB: ${r.avgHum ?? '--'}%',
                      Colors.cyan,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _infoRow('Tổng số mẫu đo:', '${r.sampleCount} bản tin'),
                    _infoRow('Tỷ lệ Uptime:', '${r.uptimePercent}%'),
                    _infoRow('Số lần đóng/ngắt Rơ-le:', '${r.relaySwitchCount} lần'),
                    _infoRow('Sự cố cảnh báo kích hoạt:', '${r.totalAlerts} lần (Chưa giải quyết: ${r.unresolvedAlerts})'),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Đánh giá kiểm định đồ án
              _sectionTitle('3. KẾT LUẬN KIỂM ĐỊNH ĐỒ ÁN CHUYÊN NGÀNH'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.ok.withValues(alpha: 0.12),
                      AppColors.primary.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.ok.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: AppColors.ok, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'XẾP LOẠI: ${r.grade}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.ok),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('• Tiêu chuẩn: ${r.standardCompliance}', style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
                    const SizedBox(height: 4),
                    Text('• Độ tin cậy: ${r.stabilityRating}', style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
                    const SizedBox(height: 6),
                    Text('• Nhận xét đồ án: ${r.examinerNotes}', style: const TextStyle(fontSize: 12, color: AppColors.text2, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Thời điểm kết xuất: ${r.generatedAt}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.text3),
              ),
            ],
          ),
        ),

        // Action Buttons Footer
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('In / Lưu PDF A4', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      onPressed: _openPdfReport,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.file_download_rounded, size: 18),
                      label: const Text('Tải File CSV', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      onPressed: _downloadCsv,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Đóng', style: TextStyle(color: AppColors.text2)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primaryLight, letterSpacing: 0.5),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text3)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String title, String content, Color accent) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
          const SizedBox(height: 6),
          Text(
            content,
            style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.4, fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}
