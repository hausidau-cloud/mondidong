import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// Xem truoc man hinh OLED SSD1306 128x64 — noi dung giong het firmware Pico
class OledPreview extends StatefulWidget {
  final Station s;
  final String? topAlert;
  const OledPreview({super.key, required this.s, this.topAlert});

  @override
  State<OledPreview> createState() => _OledPreviewState();
}

class _OledPreviewState extends State<OledPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    const cyan = Color(0xFF9FE6FF);
    const yellow = Color(0xFFFFE27A);
    const style = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.25, color: cyan, fontFeatures: tabular, shadows: [Shadow(color: Color(0x9978DCFF), blurRadius: 4)]);
    final st = s.status == 'OFFLINE' ? 'OFFLINE' : s.status;
    final tStr = s.airTemp == null ? '--.-' : fmt(s.airTemp);
    final hStr = s.airHum == null ? '--.-' : fmt(s.airHum);
    final pStr = s.probeTemp == null ? '--.-' : fmt(s.probeTemp);
    final piVal = s.picoTemp ?? (s.airTemp != null ? s.airTemp! + 4.5 : null);
    final piStr = piVal == null ? '--' : '${piVal.round()}';
    final rStr = s.relayOn ? 'BAT' : 'TAT';
    final mStr = s.relayMode.isNotEmpty ? s.relayMode.substring(0, 1).toUpperCase() : 'A';
    final last = (s.oledMsg ?? '').isNotEmpty
        ? '> ${s.oledMsg}'
        : (widget.topAlert != null
            ? '! ${widget.topAlert}'
            : (s.lastIp != null && s.lastIp!.isNotEmpty ? 'IP: ${s.lastIp}' : 'WiFi ${s.rssi ?? '--'}dBm'));

    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      color: cyan,
      child: Text(st, style: style.copyWith(color: Colors.black, shadows: const [])),
    );
    if (s.status == 'DANGER') badge = FadeTransition(opacity: _blink, child: badge);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF050607),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1D2530)),
        boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 18, spreadRadius: -6)],
      ),
      child: Stack(children: [
        Container(
          width: 264,
          height: 132,
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: DefaultTextStyle(
            style: style,
            maxLines: 1,
            overflow: TextOverflow.clip,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(s.code, style: style.copyWith(color: yellow, shadows: const [Shadow(color: Color(0x99FFDC78), blurRadius: 4)])),
                badge,
              ]),
              const SizedBox(height: 5),
              Text('Air:${tStr}C $hStr%'),
              const SizedBox(height: 2),
              Text('Nuoc:${pStr}C Pi:${piStr}C'),
              const SizedBox(height: 2),
              Text('Toi:${s.lightPct}% R:$rStr [$mStr]'),
              const SizedBox(height: 2),
              Text(last),
            ]),
          ),
        ),
        const Positioned(
          right: 0,
          bottom: -2,
          child: Text('SSD1306 · 128×64', style: TextStyle(fontSize: 8, color: Color(0xFF3A4553), letterSpacing: 0.6)),
        ),
      ]),
    );
  }
}

/// Bieu tuong relay: quat quay / coi rung khi BAT
class RelayVisual extends StatefulWidget {
  final bool on;
  final String profile;
  final double size;
  const RelayVisual({super.key, required this.on, required this.profile, this.size = 72});

  @override
  State<RelayVisual> createState() => _RelayVisualState();
}

class _RelayVisualState extends State<RelayVisual> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RelayVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.on) {
      if (!_c.isAnimating) widget.profile == 'pharma' ? _c.repeat(reverse: true) : _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ProfileStyle.of(widget.profile);
    final col = widget.on ? AppColors.ok : AppColors.muted;
    final icon = Icon(p.relayIcon, size: widget.size * 0.5, color: col);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.size * 0.28),
        color: widget.on ? AppColors.ok.withValues(alpha: 0.13) : AppColors.surface2,
        border: Border.all(color: widget.on ? AppColors.ok.withValues(alpha: 0.4) : AppColors.border),
        boxShadow: widget.on ? [BoxShadow(color: AppColors.ok.withValues(alpha: 0.25), blurRadius: 24, spreadRadius: -4)] : null,
      ),
      child: Center(
        child: widget.profile == 'pharma'
            ? RotationTransition(turns: Tween(begin: -0.04, end: 0.04).animate(_c), child: icon)
            : RotationTransition(turns: _c, child: icon),
      ),
    );
  }
}
