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
  final TextEditingController _inputCtrl = TextEditingController();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _wordsSpoken = '';
  String _statusMessage = 'Chạm nút micro và nói hoặc bấm câu lệnh gợi ý bên dưới...';
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
    'Tắt máy bơm nước',
    'Bật quạt thông gió',
    'Tắt quạt thông gió',
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
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        debugLogging: false,
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'listening') {
            setState(() {
              _isListening = true;
              _statusMessage = 'Đang lắng nghe giọng nói... Hãy nói "Bật hệ thống phun sương"';
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
            if (err.errorMsg == 'error_speech_timeout') {
              _statusMessage = 'Hết thời gian chờ. Bạn hãy chạm lại micro hoặc chọn nút gợi ý bên dưới.';
            } else if (err.errorMsg == 'error_no_match') {
              _statusMessage = 'Chưa nghe rõ câu lệnh. Vui lòng nói to rõ hơn hoặc chọn lệnh mẫu.';
            } else {
              _statusMessage = 'Lưu ý: Máy ảo Android có thể chưa bật mic host. Bạn có thể bấm chọn nút gợi ý hoặc gõ lệnh!';
            }
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
            _statusMessage = 'Chế độ mô phỏng giọng nói sẵn sàng! Chạm nút micro hoặc chọn gợi ý bên dưới để ra lệnh.';
          }
        });
        if (available) {
          _startListening();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _speechEnabled = false;
          _statusMessage = 'Chế độ mô phỏng giọng nói sẵn sàng! Chạm nút micro hoặc chọn gợi ý bên dưới để ra lệnh.';
        });
      }
    }
  }

  Future<void> _startListening() async {
    if (!_speechEnabled) {
      // Neu may ao khong co Google Speech Service -> chay che do mo phong thong minh
      _simulateVoicePrompt();
      return;
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
          _statusMessage = 'Lỗi thu âm: $e. Bạn có thể chọn câu lệnh bên dưới để thực thi ngay!';
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

  /// Mo phong giong noi nhanh khi chay tren may ao Emulator khong co Google Speech Services
  void _simulateVoicePrompt() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.record_voice_over_rounded, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text('Chọn câu lệnh giọng nói muốn thực thi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.text)),
                ],
              ),
              const SizedBox(height: 12),
              for (final c in _quickCommands)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.bolt_rounded, color: Color(0xFF06B6D4), size: 18),
                  title: Text(c, style: const TextStyle(fontSize: 13.5, color: AppColors.text)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _wordsSpoken = c;
                    });
                    _executeVoiceCommand(c);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bo phan tich y dinh ngu nghia tieng Viet & Dong bo toan dien Relay + Thiet bi chap hanh (Actuators)
  Future<void> _executeVoiceCommand(String rawCommand) async {
    final cmd = rawCommand.trim().toLowerCase();
    if (cmd.isEmpty || _processing) return;

    setState(() {
      _processing = true;
      _statusMessage = 'Đang xử lý câu lệnh: "$rawCommand"...';
    });

    try {
      final isTurnOn = cmd.contains('bật') || cmd.contains('mở') || cmd.contains('start') || cmd.contains('kích hoạt');
      final isTurnOff = cmd.contains('tắt') || cmd.contains('đóng') || cmd.contains('stop') || cmd.contains('dừng') || cmd.contains('ngừng') || cmd.contains('ngắt');
      final isAuto = cmd.contains('tự động') || cmd.contains('auto') || cmd.contains('chế độ tự động');

      final isMist = cmd.contains('phun sương') || cmd.contains('tưới sương');
      final isPump = cmd.contains('máy bơm') || cmd.contains('bơm') || cmd.contains('tưới cây') || cmd.contains('nước');
      final isFan = cmd.contains('quạt') || cmd.contains('thông gió') || cmd.contains('đối lưu');
      final isLight = cmd.contains('đèn') || cmd.contains('sưởi');
      final isSiren = cmd.contains('còi') || cmd.contains('báo động');
      final isRelay = cmd.contains('rơ le') || cmd.contains('rơ-le') || cmd.contains('relay') || cmd.contains('làm mát') || cmd.contains('thiết bị');

      if (isTurnOn) {
        String targetName = 'HỆ THỐNG PHUN SƯƠNG';

        // 1. Phun suong
        if (isMist || (!isPump && !isFan && !isLight && !isSiren)) {
          targetName = 'HỆ THỐNG PHUN SƯƠNG';
          await Session.I.setRelayMode(widget.station.id, 'ON');
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'misting', state: true, mode: 'MANUAL');
          } catch (_) {}
        }

        // 2. May bom
        if (isPump) {
          targetName = 'MÁY BƠM NƯỚC';
          await Session.I.setRelayMode(widget.station.id, 'ON');
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'pump', state: true, mode: 'MANUAL');
          } catch (_) {}
        }

        // 3. Quat thong gio
        if (isFan) {
          targetName = 'QUẠT THÔNG GIÓ';
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'fan', state: true, mode: 'MANUAL');
          } catch (_) {}
        }

        // 4. Den suoi
        if (isLight) {
          targetName = 'ĐÈN SƯỞI BỨC XẠ';
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'light', state: true, mode: 'MANUAL');
          } catch (_) {}
        }

        // 5. Coi hu
        if (isSiren) {
          targetName = 'CÒI HÚ BÁO ĐỘNG';
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'siren', state: true, mode: 'MANUAL');
          } catch (_) {}
        }

        if (isRelay) {
          await Session.I.setRelayMode(widget.station.id, 'ON');
        }

        HapticFeedback.heavyImpact();
        if (!mounted) return;
        setState(() {
          _isSuccess = true;
          _executionResult = '✓ ĐÃ THỰC THI: BẬT $targetName (ON)';
          _statusMessage = 'Đã kích hoạt $targetName và Rơ-le thành công cho trạm ${widget.station.name}!';
        });

        widget.onCommandExecuted?.call();
      } else if (isTurnOff) {
        String targetName = 'HỆ THỐNG PHUN SƯƠNG';

        // 1. Phun suong
        if (isMist || (!isPump && !isFan && !isLight && !isSiren)) {
          targetName = 'HỆ THỐNG PHUN SƯƠNG';
          await Session.I.setRelayMode(widget.station.id, 'OFF');
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'misting', state: false, mode: 'MANUAL');
          } catch (_) {}
        }

        // 2. May bom
        if (isPump) {
          targetName = 'MÁY BƠM NƯỚC';
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'pump', state: false, mode: 'MANUAL');
          } catch (_) {}
        }

        // 3. Quat thong gio
        if (isFan) {
          targetName = 'QUẠT THÔNG GIÓ';
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'fan', state: false, mode: 'MANUAL');
          } catch (_) {}
        }

        // 4. Den suoi
        if (isLight) {
          targetName = 'ĐÈN SƯỞI BỨC XẠ';
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'light', state: false, mode: 'MANUAL');
          } catch (_) {}
        }

        // 5. Coi hu
        if (isSiren) {
          targetName = 'CÒI HÚ BÁO ĐỘNG';
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'siren', state: false, mode: 'MANUAL');
          } catch (_) {}
        }

        if (isRelay) {
          await Session.I.setRelayMode(widget.station.id, 'OFF');
        }

        HapticFeedback.heavyImpact();
        if (!mounted) return;
        setState(() {
          _isSuccess = true;
          _executionResult = '✓ ĐÃ THỰC THI: TẮT $targetName (OFF)';
          _statusMessage = 'Đã tắt $targetName và Rơ-le thành công cho trạm ${widget.station.name}!';
        });

        widget.onCommandExecuted?.call();
      } else if (isAuto) {
        await Session.I.setRelayMode(widget.station.id, 'AUTO');
        for (final actId in ['misting', 'fan', 'light', 'pump', 'siren']) {
          try {
            await Session.I.updateActuator(stationId: widget.station.id, actuatorId: actId, mode: 'AUTO');
          } catch (_) {}
        }
        HapticFeedback.heavyImpact();
        if (!mounted) return;
        setState(() {
          _isSuccess = true;
          _executionResult = '✓ ĐÃ THỰC THI: CHUYỂN CHẾ ĐỘ TỰ ĐỘNG (AUTO)';
          _statusMessage = 'Tất cả cơ cấu chấp hành đã chuyển sang tự động kiểm soát theo nhiệt độ và độ ẩm!';
        });

        widget.onCommandExecuted?.call();
      } else {
        // Tra loi cau hoi qua AI
        _statusMessage = 'AI đang phân tích câu hỏi và soạn phản hồi...';
        final aiRes = await Session.I.askAiChat(
          stationId: widget.station.id,
          message: rawCommand,
          history: [],
          geminiKey: Session.I.geminiKey,
        );

        if (aiRes.action != null && aiRes.action!.executed && aiRes.action!.mode != null) {
          await Session.I.setRelayMode(widget.station.id, aiRes.action!.mode!);
          if (aiRes.action!.mode == 'ON') {
            try { await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'misting', state: true, mode: 'MANUAL'); } catch (_) {}
          } else if (aiRes.action!.mode == 'OFF') {
            try { await Session.I.updateActuator(stationId: widget.station.id, actuatorId: 'misting', state: false, mode: 'MANUAL'); } catch (_) {}
          }
          widget.onCommandExecuted?.call();
        }

        if (!mounted) return;
        setState(() {
          _isSuccess = true;
          _executionResult = '💡 TRỢ LÝ AI TRẢ LỜI:';
          _statusMessage = aiRes.reply;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSuccess = false;
        _executionResult = 'Lỗi thực thi: $e';
        _statusMessage = 'Vui lòng thử lại hoặc chọn một câu lệnh nhanh bên dưới.';
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
            const SizedBox(height: 14),

            // Box hien thi giong noi & ket qua thuc thi
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
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
                        _isListening ? 'ĐANG LẮNG NGHE GIỌNG NÓI...' : 'CÂU LỆNH ĐƯỢC CHỌN:',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _isListening ? AppColors.primary : AppColors.text3,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _wordsSpoken.isNotEmpty ? '"$_wordsSpoken"' : 'Chạm micro hoặc nút gợi ý bên dưới...',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _wordsSpoken.isNotEmpty ? AppColors.text : AppColors.text3,
                    ),
                  ),
                  if (_executionResult != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                  const SizedBox(height: 6),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _isSuccess ? AppColors.text2 : (_isListening ? AppColors.primaryLight : AppColors.muted),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Thanh go lenh bang chu (Text input fallback)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          setState(() { _wordsSpoken = val.trim(); });
                          _inputCtrl.clear();
                          _executeVoiceCommand(_wordsSpoken);
                        }
                      },
                      style: const TextStyle(fontSize: 13, color: AppColors.text),
                      decoration: const InputDecoration(
                        hintText: 'Hoặc gõ câu lệnh (vd: bật hệ thống phun sương)...',
                        hintStyle: TextStyle(fontSize: 12, color: AppColors.text3),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: AppColors.primaryLight, size: 18),
                    onPressed: () {
                      final val = _inputCtrl.text.trim();
                      if (val.isNotEmpty) {
                        setState(() { _wordsSpoken = val; });
                        _inputCtrl.clear();
                        _executeVoiceCommand(_wordsSpoken);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Nut Micro lon o giua voi hieu ung gon song
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
                      width: 68 * scale,
                      height: 68 * scale,
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
                        size: 30,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isListening ? 'Bấm để Dừng nghe & Thực thi' : 'Chạm micro để Nói (hoặc chạm gợi ý)',
              style: const TextStyle(fontSize: 11.5, color: AppColors.text3, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),

            // Goi y cau lenh mau (Quick Command Chips)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CHẠM ĐỂ THỰC THI NHANH (MÔ PHỎNG GIỌNG NÓI):',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.text3, letterSpacing: 0.6),
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
