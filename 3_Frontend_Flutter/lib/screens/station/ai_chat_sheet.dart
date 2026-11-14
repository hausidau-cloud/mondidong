import 'package:flutter/material.dart';

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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          AiChatMessage(
            role: 'assistant',
            content: '⚠️ Đã xảy ra lỗi khi trao đổi với AI: $e\n\nVui lòng thử lại hoặc kiểm tra kết nối mạng của bạn.',
            suggestions: _defaultSuggestions,
          ),
        );
        _sending = false;
      });
      _scrollToBottom();
    }
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
                      Text(
                        'Đang phân tích trực tiếp: ${s.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
