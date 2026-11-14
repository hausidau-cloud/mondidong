import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'station_screen.dart';

class AiTab extends StatefulWidget {
  final Station station;
  final VoidCallback? onActionDone;

  const AiTab({
    super.key,
    required this.station,
    this.onActionDone,
  });

  @override
  State<AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<AiTab> {
  AiDiagnosis? _diag;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await Session.I.diagnoseStation(widget.station.id);
      if (!mounted) return;
      setState(() {
        _diag = res;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleAction(String actionKey) async {
    try {
      if (actionKey == 'RELAY_ON') {
        await Session.I.setRelayMode(widget.station.id, 'ON');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã bật rơ-le theo khuyến nghị trợ lý AI')),
          );
        }
      } else if (actionKey == 'RELAY_OFF') {
        await Session.I.setRelayMode(widget.station.id, 'OFF');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã ngắt rơ-le theo khuyến nghị trợ lý AI')),
          );
        }
      }
      widget.onActionDone?.call();
      _fetch(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Thao tác thất bại: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _diag == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _diag == null) {
      return TabBody(children: [
        ErrorBanner(_error!, onRetry: () => _fetch()),
      ]);
    }

    final d = _diag!;

    return TabBody(
      onRefresh: () => _fetch(),
      children: [
        // 1. Health Score Header Gauge
        _buildHealthScoreCard(d),
        const SizedBox(height: 16),

        // 2. Dew Point & Condensation Prediction
        _buildDewPointRiskCard(d),
        const SizedBox(height: 16),

        // 3. AI Predictive 1-Hour Forecast
        _buildForecastCard(d),
        const SizedBox(height: 16),

        // 4. Anomalies Warning (if any)
        if (d.anomalies.isNotEmpty) ...[
          _buildAnomaliesCard(d),
          const SizedBox(height: 16),
        ],

        // 5. Smart Actionable Recommendations
        _buildRecommendationsSection(d),
      ],
    );
  }

  Widget _buildHealthScoreCard(AiDiagnosis d) {
    final score = d.healthScore;
    final color = score >= 80 ? AppColors.ok : (score >= 60 ? AppColors.warn : AppColors.danger);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Chỉ số Sức khỏe Trạm IoT (AI Health)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.text),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.sync_rounded, size: 20, color: AppColors.text2),
                tooltip: 'Phân tích lại',
                onPressed: () => _fetch(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Circular Score Gauge
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: CircularProgressIndicator(
                      value: score / 100.0,
                      strokeWidth: 9,
                      backgroundColor: AppColors.surface2,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        score.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: color,
                          fontFeatures: tabular,
                        ),
                      ),
                      const Text('Điểm', style: TextStyle(fontSize: 10, color: AppColors.text3, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'ĐÁNH GIÁ: ${d.healthStatus.toUpperCase()}',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      d.isOnline
                          ? 'Mạch ESP32 hoạt động ổn định, tín hiệu Wi-Fi ${d.wifiQuality.toLowerCase()}.'
                          : 'Trạm đang ngắt kết nối với máy chủ Render Cloud.',
                      style: const TextStyle(fontSize: 13, color: AppColors.text2, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDewPointRiskCard(AiDiagnosis d) {
    final margin = d.dewMargin;
    final isDanger = margin < 2.0;
    final isWarn = margin < 3.5;
    final statusColor = isDanger ? AppColors.danger : (isWarn ? AppColors.warn : AppColors.ok);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop_rounded, color: Colors.cyan, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Dự báo Nguy cơ Đọng sương Vi mạch',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  d.condensationRisk,
                  style: TextStyle(color: statusColor, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _subMetricBox(
                  'Nhiệt độ hiện tại',
                  '${d.currentTemp.toStringAsFixed(1)}°C',
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _subMetricBox(
                  'Điểm đọng sương',
                  '${d.dewPoint.toStringAsFixed(1)}°C',
                  Colors.amber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _subMetricBox(
                  'Biên độ an toàn',
                  '+${margin.toStringAsFixed(1)}°C',
                  statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isDanger
                ? '⚠️ BÁO ĐỘNG: Chênh lệch nhiệt độ và điểm đọng sương dưới 2.0°C! Hơi ẩm đang ngưng tụ thành hạt nước bám trên mạch in, gây chập rơ-le hoặc hỏng cảm biến DHT11.'
                : 'Khoảng cách an toàn biên độ sương là ${margin.toStringAsFixed(1)}°C. Không khí thông thoáng, môi trường cách ly hơi ẩm hiệu quả.',
            style: TextStyle(
              fontSize: 12.5,
              color: isDanger ? AppColors.danger : AppColors.text2,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subMetricBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.text3), maxLines: 1),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color, fontFeatures: tabular),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCard(AiDiagnosis d) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            const Color(0xFF1E1B4B).withValues(alpha: 0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFF818CF8), size: 20),
              SizedBox(width: 8),
              Text(
                'Dự báo Vi khí hậu 60 Phút Tới',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            d.forecast1h,
            style: const TextStyle(fontSize: 13, color: AppColors.text2, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, size: 14, color: AppColors.text3),
              const SizedBox(width: 6),
              Text(
                'Xu hướng nhiệt độ: ${d.tempTrend}',
                style: const TextStyle(fontSize: 12, color: AppColors.text3, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                'Cập nhật: ${d.analyzedAt.split(' ').last}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.text3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnomaliesCard(AiDiagnosis d) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
              const SizedBox(width: 8),
              Text(
                'Phát hiện ${d.anomalies.length} rủi ro bất thường',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.danger),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...d.anomalies.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(a, style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildRecommendationsSection(AiDiagnosis d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.tips_and_updates_rounded, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'Khuyến nghị Vận hành Tự động',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...d.recommendations.map((rec) => _buildRecommendationItem(rec)),
      ],
    );
  }

  Widget _buildRecommendationItem(AiRecommendation rec) {
    Color iconColor;
    IconData iconData;

    switch (rec.type) {
      case 'danger':
        iconColor = AppColors.danger;
        iconData = Icons.error_outline_rounded;
        break;
      case 'warning':
        iconColor = AppColors.warn;
        iconData = Icons.warning_amber_rounded;
        break;
      case 'success':
        iconColor = AppColors.ok;
        iconData = Icons.check_circle_outline_rounded;
        break;
      default:
        iconColor = AppColors.primary;
        iconData = Icons.info_outline_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text),
                ),
                const SizedBox(height: 4),
                Text(
                  rec.description,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.text2, height: 1.35),
                ),
                if (rec.actionKey != null) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor.withValues(alpha: 0.2),
                      foregroundColor: iconColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      elevation: 0,
                      side: BorderSide(color: iconColor.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: Text(
                      rec.actionKey == 'RELAY_ON' ? 'Bật Rơ-le ngay' : 'Thực hiện xử lý',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => _handleAction(rec.actionKey!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
