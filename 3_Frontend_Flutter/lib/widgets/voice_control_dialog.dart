import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// Hien thi Modal Dieu khien bang giong noi tieng Viet (Voice Control AI)
Future<void> showVoiceControlDialog(BuildContext context, Station station, {VoidCallback? onCommandExecuted}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => VoiceControlSheet(station: station, onCommandExecuted: onCommandExecuted),
  );
}

class VoiceControlSheet extends StatefulWidget {
  final Station station;
  final VoidCallback? onCommandExecuted;

  const VoiceControlSheet({super.key, required this.station, this.onCommandExecuted});

  @override
  State<VoiceControlSheet> createState() => _VoiceControlSheetState();
}

class _VoiceControlSheetState extends State<VoiceControlSheet> with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _wordsSpoken = '';
  String _statusMessage = 'Chạm nút micro và nói câu lệnh bằng tiếng Việt...';
  String? _executionResult;
  bool _isSuccess = false;
  bool _processing = false;
  String _selectedLocaleId = 'vi_VN';

  late AnimationController _animCtrl;

  final List<String> _quickCommands = [
    'Bật hệ thống phun sương',
    'Tắt hệ thống phun sương',
    'Chuyển sang tự động',
    'Bật máy bơm nước',
    'Tắt rơ-le làm mát',
    'Nhiệt độ hiện tại bao nhiêu?',
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'listening') {
            setState(() {
              _isListening = true;
              _statusMessage = 'Đang lắng nghe giọng nói của bạn...';
            });
          } else if (status == 'notListening' || status == 'done') {
            setState(() {
              _isListening = false;
            });
            if (_wordsSpoken.isNotEmpty && !_processing) {
              _executeVoiceCommand(_wordsSpoken);
            }
          }
        },
        onError: (err) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _statusMessage = 'Lỗi nhận diện âm thanh: ${err.errorMsg}';
          });
        },
      );

      if (available) {
        final locales = await _speech.locales();
        final hasVi = locales.any((l) => l.localeId.startsWith('vi'));
        _selectedLocaleId = hasVi ? 'vi_VN' : (locales.isNotEmpty ? locales.first.localeId : 'vi_VN');
      }

      if (mounted) {
        setState(() {
          _speechEnabled = available;
          if (!available) {
            _statusMessage = 'Thiết bị chưa cấp quyền Micro hoặc thiếu Google Speech Services.';
          }
        });
        // Tu dong bat micro ngay khi mo dialog de nguoi dung tien ra lenh
        if (available) {
          _startListening();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _speechEnabled = false;
          _statusMessage = 'Không thể khởi tạo nhận diện giọng nói: $e';
        });
      }
    }
  }

  Future<void> _startListening() async {
    if (!_speechEnabled) {
      await _initSpeech();
      if (!_speechEnabled) return;
    }

    setState(() {
      _wordsSpoken = '';
      _executionResult = null;
      _isSuccess = false;
      _statusMessage = 'Đang lắng nghe... Hãy nói "Bật hệ thống phun sương"';
    });

    HapticFeedback.mediumImpact();

    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _wordsSpoken = result.recognizedWords;
          });
          if (result.finalResult && _wordsSpoken.isNotEmpty) {
            _executeVoiceCommand(_wordsSpoken);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
          localeId: _selectedLocaleId,
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _statusMessage = 'Lỗi lắng nghe: $e';
        });
      }
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
    });
    if (_wordsSpoken.isNotEmpty && !_processing) {
      _executeVoiceCommand(_wordsSpoken);
    }
  }

  /// Bo phan tich y dinh ngu nghia tieng Viet & Thuc thi dieu khien thiet bi IoT
  Future<void> _executeVoiceCommand(String rawCommand) async {
    final cmd = rawCommand.trim().toLowerCase();
    if (cmd.isEmpty || _processing) return;

    setState(() {
      _processing = true;
      _statusMessage = 'Đang xử lý câu lệnh: "$rawCommand"...';
    });

    try {
      // 1. Nhom lenh: BAT PHUN SUONG / MAY BOM / QUAT / RO-LE (RELAY = ON)
      final isTurnOn = cmd.contains('bật') || cmd.contains('mở') || cmd.contains('start') || cmd.contains('kích hoạt');
      final isTurnOff = cmd.contains('tắt') || cmd.contains('đóng') || cmd.contains('stop') || cmd.contains('dừng') || cmd.contains('ngừng') || cmd.contains('ngắt');
      final isAuto = cmd.contains('tự động') || cmd.contains('auto') || cmd.contains('chế độ tự động');

      final isMistOrPump = cmd.contains('phun sương') || cmd.contains('bơm') || cmd.contains('máy bơm') || cmd.contains('tưới') || cmd.contains('nước');
      final isRelayOrFan = cmd.contains('rơ le') || cmd.contains('rơ-le') || cmd.contains('relay') || cmd.contains('quạt') || cmd.contains('đèn') || cmd.contains('làm mát') || cmd.contains('thiết bị');

      if (isTurnOn && (isMistOrPump || isRelayOrFan)) {
        await Session.I.setRelayMode(widget.station.id, 'ON');
        HapticFeedback.heavyImpact();
        if (!mounted) return;
        setState(() {
          _isSuccess = true;
          final target = isMistOrPump ? 'HỆ THỐNG PHUN SƯƠNG / MÁY BƠM' : 'RƠ-LE THIẾT BỊ';
          _executionResult = '✓ ĐÃ THỰC THI THÀNH CÔNG: BẬT $target (Relay ON)';
          _statusMessage = 'Đã gửi lệnh bật tức thì đến phần cứng trạm ${widget.station.name}!';
        });
        widget.onCommandExecuted?.call();
      } else if (isTurnOff && (isMistOrPump || isRelayOrFan)) {
        await Session.I.setRelayMode(widget.station.id, 'OFF');
        HapticFeedback.heavyImpact();
        if (!mounted) return;
        setState(() {
          _isSuccess = true;
          final target = isMistOrPump ? 'HỆ THỐNG PHUN SƯƠNG / MÁY BƠM' : 'RƠ-LE THIẾT BỊ';
          _executionResult = '✓ ĐÃ THỰC THI THÀNH CÔNG: TẮT $target (Relay OFF)';
          _statusMessage = 'Đã gửi lệnh tắt thiết bị đến phần cứng trạm ${widget.station.name}!';
        });
        widget.onCommandExecuted?.call();
      } else if (isAuto) {
        await Session.I.setRelayMode(widget.station.id, 'AUTO');
        HapticFeedback.heavyImpact();
        if (!mounted) return;
        setState(() {
          _isSuccess = true;
          _executionResult = '✓ ĐÃ THỰC THI THÀNH CÔNG: CHUYỂN CHẾ ĐỘ TỰ ĐỘNG (Relay AUTO)';
          _statusMessage = 'Hệ thống sẽ tự động bật/tắt theo ngưỡng nhiệt độ & độ ẩm an toàn!';
        });
        widget.onCommandExecuted?.call();
      } else {
        // 2. Chuyen tiep cau hoi tu do sang AI Chuyen gia IoT
        _statusMessage = 'AI đang tra cứu thông số và phản hồi...';
        final aiRes = await Session.I.askAiChat(
          stationId: widget.station.id,
          message: rawCommand,
          history: [],
          geminiKey: Session.I.geminiKey,
        );

        if (aiRes.action != null && aiRes.action!.executed && aiRes.action!.mode != null) {
          await Session.I.setRelayMode(widget.station.id, aiRes.action!.mode!);
          widget.onCommandExecuted?.call();
        }

        if (!mounted) return;
        setState(() {
          _isSuccess = true;
          _executionResult = '💡 AI PHẢN HỒI:';
          _statusMessage = aiRes.reply;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSuccess = false;
        _executionResult = 'Lỗi thực thi: $e';
        _statusMessage = 'Vui lòng thử lại hoặc bấm chọn câu lệnh nhanh bên dưới.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 25, offset: Offset(0, -5)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 44,
              height: 4.5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0284C7), Color(0xFF06B6D4)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Điều Khiển Giọng Nói (Voice AI)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text),
                      ),
                      Text(
                        'Trạm: ${widget.station.name} · Tiếng Việt',
                        style: const TextStyle(fontSize: 12, color: AppColors.text3),
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
            const SizedBox(height: 16),

            // Box hien thi giong noi truc tiep
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isListening
                      ? AppColors.primary
                      : (_executionResult != null ? (_isSuccess ? AppColors.ok : AppColors.danger) : AppColors.border),
                  width: _isListening ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isListening ? Icons.hearing_rounded : Icons.record_voice_over_rounded,
                        size: 16,
                        color: _isListening ? AppColors.primary : AppColors.text3,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isListening ? 'ĐANG LẮNG NGHE GIỌNG NÓI...' : 'CÂU LỆNH ĐÃ THU ĐƯỢC:',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _isListening ? AppColors.primary : AppColors.text3,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _wordsSpoken.isNotEmpty ? '"$_wordsSpoken"' : 'Chưa có âm thanh...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _wordsSpoken.isNotEmpty ? AppColors.text : AppColors.text3,
                    ),
                  ),
                  if (_executionResult != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (_isSuccess ? AppColors.ok : AppColors.danger).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _executionResult!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _isSuccess ? AppColors.ok : AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: _isSuccess ? AppColors.text2 : (_isListening ? AppColors.primaryLight : AppColors.muted),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Nut Micro lon o giua voi hieu ung gon song (Pulsing waves)
            Center(
              child: AnimatedBuilder(
                animation: _animCtrl,
                builder: (ctx, child) {
                  final scale = _isListening ? (1.0 + (_animCtrl.value * 0.15)) : 1.0;
                  final glowRadius = _isListening ? (20.0 + (_animCtrl.value * 15.0)) : 8.0;

                  return GestureDetector(
                    onTap: () {
                      if (_isListening) {
                        _stopListening();
                      } else {
                        _startListening();
                      }
                    },
                    child: Container(
                      width: 76 * scale,
                      height: 76 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isListening
                              ? const [Color(0xFFEF4444), Color(0xFFF43F5E)]
                              : const [Color(0xFF0284C7), Color(0xFF38BDF8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening ? const Color(0xFFEF4444) : const Color(0xFF0284C7))
                                .withValues(alpha: 0.45),
                            blurRadius: glowRadius,
                            spreadRadius: _isListening ? 3 : 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isListening ? 'Bấm để Dừng nghe & Thực thi' : 'Chạm micro để Nói câu lệnh',
              style: const TextStyle(fontSize: 12, color: AppColors.text3, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),

            // Goi y cau lenh mau (Quick Command Chips)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CÂU LỆNH MẪU (CHẠM ĐỂ THỬ):',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text3, letterSpacing: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cmd in _quickCommands)
                  ActionChip(
                    backgroundColor: AppColors.surface2,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    label: Text(
                      cmd,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.primaryLight, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _processing
                        ? null
                        : () {
                            setState(() {
                              _wordsSpoken = cmd;
                            });
                            _executeVoiceCommand(cmd);
                          },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
