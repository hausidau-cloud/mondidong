import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// Nhan trang thai co cham mau (cham nhap nhay khi NGUY HIEM)
class StatusPill extends StatefulWidget {
  final String status;
  final bool dense;
  const StatusPill(this.status, {super.key, this.dense = false});

  @override
  State<StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<StatusPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.status == 'DANGER') {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StatusStyle.of(widget.status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: widget.dense ? 8 : 10, vertical: widget.dense ? 3 : 5),
      decoration: BoxDecoration(color: s.color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween(begin: 0.25, end: 1.0).animate(_c),
          child: Container(width: 7, height: 7, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 6),
        Text(s.label, style: TextStyle(color: s.color, fontSize: widget.dense ? 11 : 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// O icon theo kich ban (tu dien / ho ca / tu vac-xin)
class ProfileIcon extends StatelessWidget {
  final String profile;
  final double size;
  const ProfileIcon(this.profile, {super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final p = ProfileStyle.of(profile);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.color.withValues(alpha: 0.22), p.color.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: p.color.withValues(alpha: 0.25)),
      ),
      child: Icon(p.icon, color: p.color, size: size * 0.5),
    );
  }
}

/// The co tieu de
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SectionCard({super.key, required this.title, this.subtitle, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ),
            ?trailing,
          ]),
        ),
        const Divider(),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

/// O so lieu nho (nhiet do KK, do am, diem suong...)
class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData? icon;
  const MetricTile({super.key, required this.label, required this.value, required this.unit, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) Icon(icon, size: 12, color: color) else Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label.toUpperCase(),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, letterSpacing: 0.6, color: AppColors.muted, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 3),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            TextSpan(text: unit, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
          style: const TextStyle(fontFeatures: tabular),
          maxLines: 1,
        ),
      ]),
    );
  }
}

/// Man hinh trong / loi
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? sub;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.text, this.sub, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 40, color: AppColors.muted),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.text2, fontWeight: FontWeight.w600)),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
        if (action != null) ...[const SizedBox(height: 14), action!],
      ]),
    );
  }
}

/// Thanh hien thi vi tri gia tri so voi vung nguong an toan
class RangeBar extends StatelessWidget {
  final double? value;
  final double min, max;
  final Color color;
  const RangeBar({super.key, required this.value, required this.min, required this.max, this.color = AppColors.ok});

  @override
  Widget build(BuildContext context) {
    final span = (max - min).abs() < 0.01 ? 1.0 : max - min;
    final lo = min - span * 0.35, hi = max + span * 0.35;
    double pos(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    return Column(children: [
      LayoutBuilder(builder: (ctx, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 14,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              right: 0,
              top: 4,
              child: Container(height: 6, decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(3))),
            ),
            Positioned(
              left: w * pos(min),
              width: w * (pos(max) - pos(min)),
              top: 4,
              child: Container(height: 6, decoration: BoxDecoration(color: color.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(3))),
            ),
            if (value != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                left: (w * pos(value!) - 2).clamp(0.0, w - 4),
                top: 0,
                child: Container(
                  width: 4,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.text,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: AppColors.surface, width: 1),
                  ),
                ),
              ),
          ]),
        );
      }),
      const SizedBox(height: 5),
      DefaultTextStyle(
        style: const TextStyle(fontSize: 10, color: AppColors.muted, fontFeatures: tabular),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${lo.round()}°'),
          Text('ngưỡng ${_n(min)}–${_n(max)}°C'),
          Text('${hi.round()}°'),
        ]),
      ),
    ]);
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Hien loi tai du lieu (vd mat ket noi server)
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorBanner(this.message, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, color: AppColors.danger, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(color: AppColors.text, fontSize: 13))),
        if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Thử lại')),
      ]),
    );
  }
}

/// Logo nhiet ke gradient
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.air, AppColors.probe]),
        boxShadow: [BoxShadow(color: AppColors.probe.withValues(alpha: 0.35), blurRadius: size * 0.5, offset: Offset(0, size * 0.12))],
      ),
      child: Icon(Icons.thermostat_rounded, color: Colors.white, size: size * 0.58),
    );
  }
}
