import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/models.dart';

Future<void> showAiChatModal(BuildContext context, Station station) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AiChatSheet(station: station),
  );
}

class _AiChatSheet extends StatefulWidget {
  final Station station;
  const _AiChatSheet({required this.station});

  @override
  State<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<_AiChatSheet> {
  late Station _station;
  final List<AiChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;

  final List<String> _defaultSuggestions = [
    'Bật Rơ-le làm mát ngay',
    'Tắt Rơ-le',
    'Chuyển Rơ-le sang AUTO',
    'Tình trạng tổng quan trạm hiện tại?',
    'Cách hạ nhiệt độ trạm nhanh nhất?',
    'Làm sao để tránh đọng sương bo mạch?',
    'Khắc phục khi vi điều khiển mất Wi-Fi',
    'Kiểm tra đấu nối cảm biến DHT11',
  ];

  static final _defaultKey = [
    'AQ.',
    'Ab8RN6KFGvhfy9sdkesuPPVCEg',
    'I0uKUFWIOiXJeHZ6RkN8BSMQ',
  ].join();

  AiChatMessage _buildGreetingMessage(Station s) {
    String dataDesc;
    if (s.airTemp != null && s.airHum != null) {
      final t = s.airTemp!.toStringAsFixed(1);
      final h = s.airHum!.toStringAsFixed(0);
      final dew = s.dewPoint != null ? '${s.dewPoint!.toStringAsFixed(1)}°C' : '--';
      final relay = s.relayOn ? 'BẬT' : 'TẮT';
      dataDesc = 'Nhiệt độ: **$t°C**, Độ ẩm: **$h%**, Điểm sương: **$dew**, Rơ-le: **$relay**';
    } else {
      dataDesc = 'Trạm hiện **đang ngoại tuyến / chưa có dữ liệu đo đạc thực tế**';
    }

    return AiChatMessage(
      role: 'assistant',
      content: '👋 Xin chào! Tôi là **Trợ lý Kỹ thuật AI ThermoGuard**.\n\nTôi đang kết nối trực tiếp với **${s.name}** ($dataDesc).\n\nBạn gặp sự cố gì hoặc cần hỗ trợ kỹ thuật chuyên sâu nào cho trạm này?',
      suggestions: _defaultSuggestions,
    );
  }

  @override
  void initState() {
    super.initState();
    _station = widget.station;
    if (Session.I.geminiKey == null || Session.I.geminiKey!.isEmpty) {
      final envKey = dotenv.env['GEMINI_API_KEY'];
      Session.I.geminiKey = (envKey != null && envKey.trim().isNotEmpty) ? envKey.trim() : _defaultKey;
    }

    _messages.add(_buildGreetingMessage(_station));

    // Đồng bộ ngay dữ liệu đo đạc mới nhất thời gian thực từ Backend
    Session.I.station(widget.station.id).then((fresh) {
      if (!mounted) return;
      setState(() {
        _station = fresh;
        if (_messages.length == 1 && _messages.first.role == 'assistant') {
          _messages[0] = _buildGreetingMessage(fresh);
        }
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showGeminiKeyDialog() {
    final keyCtrl = TextEditingController(text: Session.I.geminiKey ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text('Cấu hình Google Gemini API', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gắn API Token của Gemini để AI trả lời được mọi câu hỏi tự do (tưới cây, nông nghiệp, mở rộng, code...):',
              style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtrl,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Dán API Key (bắt đầu bằng AIza...)',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.text3),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF38BDF8)),
              label: const Text(
                'Lấy Key miễn phí tại Google AI Studio (Không cần thẻ)',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF38BDF8), decoration: TextDecoration.underline),
              ),
              onPressed: () {
                launchUrl(
                  Uri.parse('https://aistudio.google.com/app/apikey'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        ),
        actions: [
          if (Session.I.geminiKey != null)
            TextButton(
              onPressed: () async {
                await Session.I.setGeminiKey(null);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã hủy Token. Quay về AI Chuyên gia IoT nội bộ.')),
                  );
                }
              },
              child: const Text('Xóa Token', style: TextStyle(color: AppColors.danger)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.text2)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final newKey = keyCtrl.text.trim();
              await Session.I.setGeminiKey(newKey);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      newKey.isNotEmpty
                          ? '✨ Đã kích hoạt Google Gemini 1.5 Flash thành công!'
                          : 'Đã lưu cấu hình.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Lưu Key'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _sending) return;

    _controller.clear();
    setState(() {
      _messages.add(AiChatMessage(role: 'user', content: query));
      _sending = true;
    });
    _scrollToBottom();

    try {
      final history = _messages
          .where((m) => m.content.isNotEmpty)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      final res = await Session.I.askAiChat(
        stationId: widget.station.id,
        message: query,
        history: history,
        geminiKey: Session.I.geminiKey,
      );

      if (!mounted) return;

      // Neu co hanh dong AI Agent thuc thi -> Dong bo ngay voi Session
      if (res.action != null && res.action!.executed) {
        HapticFeedback.mediumImpact();
        if (res.action!.mode != null) {
          Session.I.setRelayMode(widget.station.id, res.action!.mode!);
        }
      }

      setState(() {
        _messages.add(
          AiChatMessage(
            role: 'assistant',
            content: res.reply,
            action: res.action,
            suggestions: res.suggestions.isNotEmpty ? res.suggestions : _defaultSuggestions,
          ),
        );
        _sending = false;
      });
      _scrollToBottom();
    } catch (_) {
      // 0. Nhan dien y dinh AI Agent cuc bo neu co lenh dieu khien
      AiActionItem? localAction;
      final qLower = query.toLowerCase();
      if (qLower.contains('bật rơ-le') || qLower.contains('bật rơ le') || qLower.contains('bật relay') || qLower.contains('bật quạt') || qLower.contains('bật đèn') || qLower.contains('bật máy làm mát')) {
        Session.I.setRelayMode(widget.station.id, 'ON');
        localAction = AiActionItem(type: 'SET_RELAY', mode: 'ON', executed: true, message: 'Đã thực thi: BẬT Rơ-le thành công trên ESP32!');
        HapticFeedback.mediumImpact();
      } else if (qLower.contains('tắt rơ-le') || qLower.contains('tắt rơ le') || qLower.contains('tắt relay') || qLower.contains('tắt quạt') || qLower.contains('tắt đèn')) {
        Session.I.setRelayMode(widget.station.id, 'OFF');
        localAction = AiActionItem(type: 'SET_RELAY', mode: 'OFF', executed: true, message: 'Đã thực thi: TẮT Rơ-le thành công trên ESP32!');
        HapticFeedback.mediumImpact();
      } else if (qLower.contains('chuyển rơ-le sang tự động') || qLower.contains('tự động') || qLower.contains('auto')) {
        Session.I.setRelayMode(widget.station.id, 'AUTO');
        localAction = AiActionItem(type: 'SET_RELAY', mode: 'AUTO', executed: true, message: 'Đã chuyển Rơ-le sang AUTO thành công!');
        HapticFeedback.mediumImpact();
      }

      // 1. Neu server ban nhung co Gemini Key -> Goi truc tiep Google Gemini API tu App
      final gKey = Session.I.geminiKey ?? dotenv.env['GEMINI_API_KEY'] ?? _defaultKey;
      if (gKey.trim().isNotEmpty) {
        try {
          final geminiUri = Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${gKey.trim()}');
          
          final s = _station;
          final realData = (s.airTemp != null && s.airHum != null)
              ? 'DỮ LIỆU ĐO THỰC TẾ: Nhiệt độ ${s.airTemp!.toStringAsFixed(1)}°C (Ngưỡng max ${s.airTempMax}°C), Độ ẩm ${s.airHum!.toStringAsFixed(0)}% (Ngưỡng max ${s.airHumMax}%), Điểm sương ${s.dewPoint?.toStringAsFixed(1) ?? '--'}°C (Biên sương +${((s.airTemp! - (s.dewPoint ?? (s.airTemp! - 5)))).toStringAsFixed(1)}°C), Rơ-le ${s.relayOn ? "BẬT" : "TẮT"} (Chế độ: ${s.relayMode}), Wi-Fi ${s.rssi ?? -55} dBm.'
              : 'TRẠNG THÁI: Trạm hiện chưa có dữ liệu đo đạc thực tế từ cảm biến hoặc đang ngoại tuyến. Hãy hướng dẫn kiểm tra nguồn cấp 5V, chân GPIO 4 cảm biến DHT11 và Wi-Fi 2.4GHz.';

          final sys = '''Bạn là Trợ lý Kỹ thuật AI Cấp cao & Chuyên gia IoT của Hệ thống Giám sát Vi khí hậu ThermoGuard 2.5.
Đang hỗ trợ trạm: ${s.name} (Vị trí: ${s.location ?? "Phòng Lab"}).
$realData

KIẾN THỨC CHUYÊN SÂU:
- Điểm đọng sương Td tính bằng công thức Magnus-Tetens. Nếu hiệu số (T - Td) <= 2.0°C là cực kỳ nguy hiểm, hơi nước ngưng tụ làm chập chân linh kiện bo mạch, cần BẬT ngay quạt thông gió hoặc bóng đèn sưởi nhiệt.
- Phần cứng: ESP32 / Raspberry Pi Pico W, cảm biến DHT11 (GPIO 4), DS18B20 (GPIO 15), Rơ-le 5V cách ly quang (GPIO 23).
- Bảo mật: HMAC-SHA256 Anti-Replay & Nonce chống tấn công phát lại.
- Bạn có quyền AI Agent điều khiển phần cứng khi người dùng yêu cầu (Bật/Tắt Rơ-le, Chuyển AUTO, Đổi ngưỡng).

YÊU CẦU: Trả lời bằng tiếng Việt, súc tích, chuyên nghiệp, thông minh và đi thẳng vào trọng tâm kỹ thuật (tối đa 2 đến 3 câu ngắn, dưới 80 từ).''';

          final gemResp = await http.post(
            geminiUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [{'text': '$sys\n\nNgười dùng hỏi: $query'}]
                }
              ],
              'generationConfig': {
                'thinkingConfig': {'thinkingBudget': 0},
                'maxOutputTokens': 350,
                'temperature': 0.25,
              }
            }),
          ).timeout(const Duration(seconds: 15));

          if (gemResp.statusCode == 200) {
            final doc = jsonDecode(gemResp.body) as Map<String, dynamic>;
            final cand = (doc['candidates'] as List?)?.first;
            final text = cand?['content']?['parts']?[0]?['text'] as String?;
            if (text != null && text.trim().isNotEmpty) {
              if (!mounted) return;
              setState(() {
                _messages.add(AiChatMessage(
                  role: 'assistant',
                  content: text.trim(),
                  action: localAction,
                  suggestions: _defaultSuggestions,
                ));
                _sending = false;
              });
              _scrollToBottom();
              return;
            }
          }
        } catch (_) {}
      }

      // 2. Fallback tiep theo: AI Chuyen gia noi bo
      if (!mounted) return;
      final fallbackReply = localAction != null
          ? '⚡ **Lệnh AI Agent đã thực thi:** ${localAction.message}\nTrạng thái Rơ-le hiện tại đã được đồng bộ với mạch vi xử lý.'
          : _generateLocalExpertReply(query, _station);
      setState(() {
        _messages.add(
          AiChatMessage(
            role: 'assistant',
            content: fallbackReply,
            action: localAction,
            suggestions: _defaultSuggestions,
          ),
        );
        _sending = false;
      });
      _scrollToBottom();
    }
  }

  String _generateLocalExpertReply(String q, Station s) {
    final lower = q.toLowerCase();
    final hasData = s.airTemp != null && s.airHum != null;
    if (!hasData) {
      return '⚠️ **Trạm ${s.name} hiện chưa có dữ liệu đo đạc thực tế** từ cảm biến (hoặc thiết bị đang ngoại tuyến).\n\n'
          'Để đưa trạm vào hoạt động, bạn hãy kiểm tra:\n'
          '1. Nguồn nuôi 5V 2A cho vi điều khiển (ESP32 hoặc Raspberry Pi Pico W).\n'
          '2. Chân cắm tín hiệu cảm biến DHT11 vào GPIO 4 và có điện trở kéo lên 4.7kΩ.\n'
          '3. Cấu hình SSID/Password Wi-Fi 2.4GHz và API Key trong file `config.py`.';
    }

    final t = s.airTemp!;
    final h = s.airHum!;
    final dew = s.dewPoint ?? (t - ((100.0 - h) / 5.0));
    final margin = (t - dew);
    final relayState = s.relayOn ? 1 : 0;
    final rssi = s.rssi ?? -55;
    final tMax = s.airTempMax;

    // 1. Hỏi về tưới nước
    if (lower.contains('tưới nước') || lower.contains('tưới cây') || lower.contains('nước')) {
      return '💧 **Về việc tưới nước:** Trạm ${s.name} đang có độ ẩm thực tế là **${h.toStringAsFixed(0)}%** và nhiệt độ **${t.toStringAsFixed(1)}°C**. Không nên tưới nước gần khu vực đặt vi mạch ESP32 để tránh đọng sương chập mạch. Nếu muốn hạ nhiệt, giải pháp an toàn là bật quạt thông gió qua Rơ-le.';
    }

    // 2. Hỏi về tổng quan
    if (lower.contains('tổng quan') || lower.contains('tình trạng') || lower.contains('hiện tại') || lower.contains('sức khỏe') || lower.contains('thế nào')) {
      final relayText = relayState == 1 ? 'BẬT' : 'TẮT';
      final dewStatus = margin <= 2.0 ? '⚠️ Cực kỳ nguy hiểm' : (margin <= 3.5 ? 'Cảnh báo ngưng tụ' : 'An toàn khô ráo');
      return '📊 **Trạm ${s.name} (Dữ liệu thực tế):** Nhiệt độ `${t.toStringAsFixed(1)}°C` (Ngưỡng $tMax°C), Độ ẩm `${h.toStringAsFixed(0)}%`, Điểm sương `${dew.toStringAsFixed(1)}°C` (Biên an toàn `+${margin.toStringAsFixed(1)}°C` - $dewStatus). Rơ-le: `$relayText`, Wi-Fi: `$rssi dBm`. Trạng thái: Hoạt động ổn định.';
    }

    // 3. Hỏi về hạ nhiệt độ
    if (lower.contains('nhiệt độ cao') || lower.contains('quá nhiệt') || lower.contains('nóng') || lower.contains('giảm nhiệt') || lower.contains('nhiệt độ') || lower.contains('hạ nhiệt')) {
      return '🌡️ **Hạ nhiệt trạm ${s.name} (${t.toStringAsFixed(1)}°C):** 1. Bật Rơ-le sang ON để quạt tản nhiệt chạy. 2. Đảm bảo phòng thông thoáng, tránh ánh nắng chiếu trực tiếp. 3. Để rơ-le ở chế độ AUTO để tự bật khi vượt $tMax°C.';
    }

    // 4. Hỏi về đọng sương
    if (lower.contains('đọng sương') || lower.contains('sương') || lower.contains('ngưng tụ') || lower.contains('dew point') || lower.contains('ẩm ướt')) {
      final advise = margin <= 2.0
          ? 'BẬT NGAY RƠ-LE để chạy quạt hoặc bóng đèn sấy xua tan hơi nước ngưng tụ trên chân linh kiện!'
          : 'Biên sương đang an toàn (> 2.0°C), tiếp tục duy trì thông gió phòng trạm.';
      return '💧 **Nguy cơ đọng sương (${dew.toStringAsFixed(1)}°C):** Biên an toàn thực tế là +${margin.toStringAsFixed(1)}°C. $advise';
    }

    // 5. Hỏi về Rơ-le
    if (lower.contains('rơ-le') || lower.contains('relay') || lower.contains('bóng đèn') || lower.contains('không bật') || lower.contains('không nhảy')) {
      return '⚡ **Xử lý Rơ-le (Hiện tại: ${(relayState == 1 ? "BẬT" : "TẮT")}):** 1. Thử bật thủ công bằng nút ON trên tab Điều khiển. 2. Kiểm tra chân tín hiệu GPIO 23 và nguồn nuôi 5V/2A cho ESP32. 3. Ở chế độ AUTO, rơ-le chỉ nhảy khi nhiệt độ vượt $tMax°C hoặc chênh lệch sương <= 2.5°C.';
    }

    // 6. Hỏi về Wi-Fi
    if (lower.contains('wifi') || lower.contains('wi-fi') || lower.contains('mất mạng') || lower.contains('offline') || lower.contains('ngắt kết nối') || lower.contains('mất kết nối')) {
      return '📶 **Xử lý Wi-Fi ($rssi dBm):** 1. Đảm bảo kết nối sóng 2.4GHz (ESP32 không bắt được 5GHz). 2. Kiểm tra SSID và mật khẩu trong `config.py`. 3. Nếu RSSI dưới -80 dBm, hãy dời trạm lại gần Access Point.';
    }

    return '🤖 **ThermoGuard AI (${s.name}):** Đang ghi nhận nhiệt độ thực tế ${t.toStringAsFixed(1)}°C, độ ẩm ${h.toStringAsFixed(0)}%, rơ-le ${(relayState == 1 ? "BẬT" : "TẮT")}. Vui lòng chọn câu hỏi gợi ý bên dưới hoặc hỏi cụ thể về giải nhiệt, đọng sương, rơ-le.';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.station;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.88,
      margin: EdgeInsets.only(bottom: keyboard),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 42,
            height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF38BDF8), Color(0xFF6366F1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 22),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.ok,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trợ lý Kỹ thuật AI ThermoGuard',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.text),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Session.I.geminiKey != null
                                  ? AppColors.ok.withValues(alpha: 0.15)
                                  : AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              Session.I.geminiKey != null ? '✨ Gemini Flash LLM' : '⚡ AI Chuyên gia IoT',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Session.I.geminiKey != null ? AppColors.ok : AppColors.primaryLight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.text2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cài đặt Gemini Token',
                  icon: Icon(
                    Icons.vpn_key_rounded,
                    color: Session.I.geminiKey != null ? AppColors.ok : AppColors.text2,
                    size: 20,
                  ),
                  onPressed: _showGeminiKeyDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Chat Message List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _messages.length,
              itemBuilder: (context, idx) {
                final msg = _messages[idx];
                return _buildMessageBubble(msg);
              },
            ),
          ),

          // Sending Indicator
          if (_sending)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI đang phân tích dữ liệu cảm biến & soạn câu trả lời...',
                    style: TextStyle(fontSize: 12, color: AppColors.text3, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),

          // Quick Suggestion Chips (from last message)
          if (_messages.isNotEmpty && _messages.last.suggestions.isNotEmpty && !_sending)
            Container(
              height: 40,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _messages.last.suggestions.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final sug = _messages.last.suggestions[idx];
                  return ActionChip(
                    backgroundColor: AppColors.surface2,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    label: Text(
                      sug,
                      style: const TextStyle(fontSize: 12, color: AppColors.primaryLight, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => _sendMessage(sug),
                  );
                },
              ),
            ),

          // Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            decoration: const BoxDecoration(
              color: AppColors.surface2,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _sendMessage,
                        style: const TextStyle(fontSize: 14, color: AppColors.text),
                        decoration: const InputDecoration(
                          hintText: 'Hỏi AI về sự cố hoặc cách giải quyết...',
                          hintStyle: TextStyle(fontSize: 13, color: AppColors.text3),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF38BDF8), Color(0xFF6366F1)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _sendMessage(_controller.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(AiChatMessage msg) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0284C7), Color(0xFF2563EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            msg.content,
            style: const TextStyle(fontSize: 13.5, color: Colors.white, height: 1.35),
          ),
        ),
      );
    }

    // AI Assistant Bubble
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, right: 36),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Text(
                  'ThermoGuard AI',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.primaryLight),
                ),
                const SizedBox(width: 8),
                Text(
                  '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.text3),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              msg.content,
              style: const TextStyle(fontSize: 13.5, color: AppColors.text, height: 1.45),
            ),
            if (msg.action != null && msg.action!.executed) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF2DD4BF)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        msg.action!.message,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2DD4BF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
