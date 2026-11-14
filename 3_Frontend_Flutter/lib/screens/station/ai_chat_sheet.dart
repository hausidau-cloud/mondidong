import 'package:flutter/material.dart';
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
  final List<AiChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;

  final List<String> _defaultSuggestions = [
    'Tình trạng tổng quan trạm hiện tại?',
    'Cách hạ nhiệt độ trạm nhanh nhất?',
    'Làm sao để tránh đọng sương bo mạch?',
    'Kiểm tra Rơ-le và Bóng đèn 220V',
    'Khắc phục khi ESP32 mất kết nối Wi-Fi',
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.station;
    final tempStr = s.airTemp != null ? '${s.airTemp!.toStringAsFixed(1)}°C' : 'chưa xác định';
    final humStr = s.airHum != null ? '${s.airHum!.toStringAsFixed(0)}%' : 'chưa xác định';

    _messages.add(
      AiChatMessage(
        role: 'assistant',
        content: '👋 Xin chào! Tôi là **Trợ lý Kỹ thuật AI ThermoGuard**.\n\nTôi đang kết nối trực tiếp với **${s.name}** (Nhiệt độ: `$tempStr`, Độ ẩm: `$humStr`).\n\nBạn gặp vấn đề gì hoặc cần hỗ trợ kỹ thuật nào cho trạm này?',
        suggestions: _defaultSuggestions,
      ),
    );
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
      );

      if (!mounted) return;
      setState(() {
        _messages.add(
          AiChatMessage(
            role: 'assistant',
            content: res.reply,
            suggestions: res.suggestions.isNotEmpty ? res.suggestions : _defaultSuggestions,
          ),
        );
        _sending = false;
      });
      _scrollToBottom();
    } catch (_) {
      // Fallback tu dong: neu server tam thoi ban / mat mang, AI noi bo tren app tu giai quyet ngay lap tuc
      if (!mounted) return;
      final fallbackReply = _generateLocalExpertReply(query, widget.station);
      setState(() {
        _messages.add(
          AiChatMessage(
            role: 'assistant',
            content: fallbackReply,
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
    final t = s.airTemp ?? 32.0;
    final h = s.airHum ?? 60.0;
    final dew = s.dewPoint ?? (t - ((100 - h) / 5.0));
    final margin = (t - dew);
    final relayState = s.relayOn ? 1 : 0;
    final relayMode = s.relayMode;
    final rssi = s.rssi ?? -55;
    final tMax = s.airTempMax;
    final hMax = s.airHumMax;

    if (lower.contains('tổng quan') || lower.contains('tình trạng') || lower.contains('hiện tại') || lower.contains('sức khỏe') || lower.contains('thế nào')) {
      final relayText = relayState == 1 ? 'Đang BẬT' : 'Đang TẮT';
      final dewAlert = margin < 2.0
          ? '⚠️ **Cực kỳ nguy hiểm:** Biên độ sương chỉ còn ${margin.toStringAsFixed(1)}°C! Nguy cơ chập vi mạch.'
          : '✅ **An toàn:** Biên độ đọng sương đạt +${margin.toStringAsFixed(1)}°C (Ngưỡng an toàn tối thiểu là 3.0°C).';

      return '📊 **BÁO CÁO NHANH TÌNH TRẠNG ${s.name.toUpperCase()}:**\n'
          '📍 **Vị trí:** ${s.location ?? "Chưa rõ"}\n'
          '- **Nhiệt độ:** `${t.toStringAsFixed(1)}°C` ${(t > tMax ? "🔴 (VƯỢT NGƯỠNG $tMax°C)" : "🟢 (Bình thường)")}\n'
          '- **Độ ẩm:** `${h.toStringAsFixed(0)}%` ${(h > hMax ? "🟠 (VƯỢT NGƯỠNG $hMax%)" : "🟢 (Lý tưởng 40-70%)")}\n'
          '- **Điểm đọng sương:** `${dew.toStringAsFixed(1)}°C` (Biên an toàn: `+${margin.toStringAsFixed(1)}°C`)\n'
          '- **Tín hiệu Wi-Fi:** `$rssi dBm` ${(rssi >= -65 ? "🟢 (Rất tốt)" : (rssi >= -80 ? "🟡 (Trung bình)" : "🔴 (Yếu)"))}\n'
          '- **Rơ-le / Thiết bị ngoại vi:** `$relayText` (Chế độ: `$relayMode`)\n\n'
          '💡 $dewAlert';
    }

    if (lower.contains('nhiệt độ cao') || lower.contains('quá nhiệt') || lower.contains('nóng') || lower.contains('giảm nhiệt') || lower.contains('nhiệt độ') || lower.contains('hạ nhiệt')) {
      return '🌡️ **HƯỚNG DẪN XỬ LÝ KHI NHIỆT ĐỘ TĂNG CAO:**\n'
          'Nhiệt độ hiện tại của trạm đo được là **${t.toStringAsFixed(1)}°C** (Ngưỡng cảnh báo: **${tMax.toStringAsFixed(1)}°C**).\n\n'
          '**Các bước xử lý kỹ thuật đề xuất:**\n'
          '1. 🌬️ **Kích hoạt tải làm mát:** Chuyển Rơ-le sang chế độ **ON** trên tab *Điều khiển* để bật quạt tản nhiệt hoặc hệ thống thông gió ngay lập tức.\n'
          '2. 🔄 **Cấu hình tự động (AUTO):** Đảm bảo rơ-le đang ở chế độ **AUTO**, trạm sẽ tự động đóng tiếp điểm rơ-le khi nhiệt độ vượt quá `${tMax.toStringAsFixed(1)}°C`.\n'
          '3. 📦 **Kiểm tra vị trí đặt trạm:** Tránh ánh nắng mặt trời chiếu trực diện hoặc đặt cạnh các nguồn phát nhiệt lớn (nguồn xung, biến áp, dàn nóng máy lạnh).\n'
          '4. ⚙️ **Hiệu chuẩn cảm biến:** Nếu nghi ngờ cảm biến DHT11 bị trôi thông số, vào tab *Cấu hình* > chỉnh lại `Offset Nhiệt độ` (-1.0°C đến -2.0°C).';
    }

    if (lower.contains('đọng sương') || lower.contains('sương') || lower.contains('ngưng tụ') || lower.contains('dew point') || lower.contains('ẩm ướt')) {
      return '💧 **HIỆN TƯỢNG ĐỌNG SƯƠNG & CÁCH PHÒNG CHỐNG TRONG IOT:**\n\n'
          '- **Điểm đọng sương hiện tại:** `${dew.toStringAsFixed(1)}°C`\n'
          '- **Biên an toàn (ΔT):** `+${margin.toStringAsFixed(1)}°C` (ΔT = T_không khí - T_điểm sương).\n\n'
          '**Tại sao đọng sương lại nguy hiểm?**\n'
          'Khi nhiệt độ bề mặt linh kiện tụt xuống bằng hoặc thấp hơn điểm đọng sương, hơi nước trong không khí sẽ chuyển pha từ thể khí sang thể lỏng bám trực tiếp lên bo mạch ESP32 và chân cảm biến DHT11, dẫn đến:\n'
          '- Chập điện giữa các đường mạch in (VCC và GND).\n'
          '- Oxy hóa rỉ sét chân hàn và làm sai lệch số đo cảm biến.\n\n'
          '**Biện pháp giải quyết:**\n'
          '1. 💡 **Gia nhiệt nhẹ:** Bật bóng đèn sấy hoặc thanh nhiệt nối qua Rơ-le để nâng nhiệt độ bề mặt bo mạch cao hơn điểm đọng sương ít nhất **3°C**.\n'
          '2. 🌪️ **Tăng đối lưu không khí:** Bật quạt lưu thông để giải tỏa vùng không khí bão hòa hơi ẩm quanh trạm.\n'
          '3. 🧪 **Bổ sung hạt chống ẩm Silica Gel** bên trong hộp kín chứa mạch.';
    }

    if (lower.contains('rơ-le') || lower.contains('relay') || lower.contains('bóng đèn') || lower.contains('không bật') || lower.contains('không nhảy')) {
      return '⚡ **HƯỚNG DẪN KIỂM TRA & ĐIỀU KHIỂN RƠ-LE:**\n'
          'Trạng thái rơ-le hiện tại: **${(relayState == 1 ? "ĐANG BẬT (ON)" : "ĐANG TẮT (OFF)")}** | Chế độ: **$relayMode**\n\n'
          '**Các bước khắc phục sự cố rơ-le:**\n'
          '1. 📱 **Thử bật bằng tay từ App:** Chuyển chế độ rơ-le sang **ON** từ tab *Điều khiển* để kiểm tra lệnh qua mạng Render Cloud có truyền về ESP32 không.\n'
          '2. 🔌 **Kiểm tra nguồn cấp rơ-le:** Cuộn hút rơ-le 5V tiêu thụ dòng khá lớn (70-100mA). Hãy đảm bảo cấp nguồn qua cổng MicroUSB với củ sạc tối thiểu **5V / 1.5A - 2A**, không nên chỉ cắm cổng USB laptop cấp dòng yếu.\n'
          '3. 📌 **Kiểm tra chân điều khiển:**\n'
          '   - Chân tín hiệu Rơ-le nối vào **GPIO 23** của ESP32.\n'
          '   - Đèn LED báo trên mạch ESP32 nối chân **GPIO 2** (sẽ sáng đồng bộ khi rơ-le kích hoạt).\n'
          '4. 🎛️ **Kiểm tra ngưỡng tự động:** Nếu để chế độ AUTO, rơ-le chỉ nhảy khi `Nhiệt độ >= $tMax°C` hoặc `Biên độ sương < 3.0°C`.';
    }

    if (lower.contains('wifi') || lower.contains('wi-fi') || lower.contains('mất mạng') || lower.contains('offline') || lower.contains('ngắt kết nối') || lower.contains('mất kết nối')) {
      return '📶 **KHẮC PHỤC SỰ CỐ MẤT KẾT NỐI WI-FI (OFFLINE):**\n'
          'Cường độ sóng ghi nhận lần cuối: **$rssi dBm** (Trạng thái: **${s.status}**).\n\n'
          '**Checklist xử lý kết nối:**\n'
          '1. 📡 **Kiểm tra băng tần Wi-Fi:** Chip ESP32 **chỉ hỗ trợ băng tần 2.4 GHz**, không hỗ trợ Wi-Fi 5 GHz. Nếu router phát song song 2 băng tần, hãy kết nối vào tên SSID 2.4GHz.\n'
          '2. 🔑 **Kiểm tra danh sách Wi-Fi trong firmware:** Mở file `config.py` trên ESP32 và đảm bảo tên Wi-Fi + Mật khẩu đã được khai báo chính xác trong mảng `WIFI_LIST`.\n'
          '3. 📍 **Khoảng cách truyền dẫn:** Nếu RSSI dưới `-80 dBm`, tín hiệu rất suy hao, dễ mất gói tin HMAC. Hãy dời ESP32 gần cục phát Wi-Fi hơn hoặc dùng bộ kích sóng.\n'
          '4. 🔄 **Cơ chế tự động Failover:** Firmware ESP32 ThermoGuard đã tích hợp thuật toán tự động quét mạng và thử kết nối lại sau mỗi 5 giây khi mất tín hiệu.';
    }

    return '🤖 **TRỢ LÝ KỸ THUẬT IOT THERMOGUARD:**\n'
        'Tôi đã nhận câu hỏi của bạn: *"$q"*.\n\n'
        'Dựa trên dữ liệu hiện trường của **${s.name}** (`${t.toStringAsFixed(1)}°C`, `${h.toStringAsFixed(0)}%`, Điểm sương `${dew.toStringAsFixed(1)}°C`):\n'
        '- Hệ thống vi xử lý ESP32 và cảm biến DHT11 đang gửi gói tin định kỳ 2 giây/lần.\n'
        '- Chế độ rơ-le hiện tại: `$relayMode` (Trạng thái: `${(relayState == 1 ? "BẬT" : "TẮT")}`).\n\n'
        'Bạn có thể chọn một trong các chủ đề cần xử lý bên dưới hoặc đặt câu hỏi chi tiết hơn:';
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
          ],
        ),
      ),
    );
  }
}
