import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';

class MessagesScreen extends StatefulWidget {
  final int? initialStationId;
  final bool isActive;
  final ValueChanged<int>? onLatestMessageSeen;
  const MessagesScreen({
    super.key,
    this.initialStationId,
    this.isActive = true,
    this.onLatestMessageSeen,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  List<TeamMessageItem> _messages = [];
  List<Station> _stations = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;

  int? _selectedStationId;
  String _selectedCategory = 'CHAT'; // CHAT | INCIDENT | MAINTENANCE | RESOLVED
  String? _attachedTelemetry;

  @override
  void initState() {
    super.initState();
    _selectedStationId = widget.initialStationId;
    _loadInitial();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollMessages());
  }

  @override
  void didUpdateWidget(covariant MessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      if (_messages.isNotEmpty) {
        final maxId = _messages.map((m) => m.id).reduce((a, b) => a > b ? a : b);
        _notifySeen(maxId);
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _notifySeen(int id) async {
    if (!widget.isActive) return;
    widget.onLatestMessageSeen?.call(id);
    try {
      final sp = await SharedPreferences.getInstance();
      final cur = sp.getInt('last_read_team_message_id') ?? 0;
      if (id > cur) {
        await sp.setInt('last_read_team_message_id', id);
      }
    } catch (_) {}
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final stList = await Session.I.stations();
      final msgs = await Session.I.teamMessages(stationId: _selectedStationId);
      if (!mounted) return;
      setState(() {
        _stations = stList;
        _messages = msgs;
        _loading = false;
        _error = null;
      });
      if (msgs.isNotEmpty) {
        final maxId = msgs.map((m) => m.id).reduce((a, b) => a > b ? a : b);
        _notifySeen(maxId);
      }
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pollMessages() async {
    if (_sending) return;
    try {
      final msgs = await Session.I.teamMessages(stationId: _selectedStationId);
      if (!mounted) return;
      if (msgs.length != _messages.length || (msgs.isNotEmpty && _messages.isNotEmpty && msgs.last.id != _messages.last.id)) {
        setState(() {
          _messages = msgs;
        });
        if (msgs.isNotEmpty) {
          final maxId = msgs.map((m) => m.id).reduce((a, b) => a > b ? a : b);
          _notifySeen(maxId);
        }
        _scrollToBottom();
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    HapticFeedback.lightImpact();

    try {
      final newMsg = await Session.I.sendTeamMessage(
        content: text,
        stationId: _selectedStationId,
        category: _selectedCategory,
        attachedTelemetry: _attachedTelemetry,
      );

      _textCtrl.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(newMsg);
        _attachedTelemetry = null;
        _sending = false;
      });
      _notifySeen(newMsg.id);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, 'Lỗi gửi tin nhắn: $e', error: true);
    }
  }

  Future<void> _deleteMessage(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Xác nhận xóa'),
        content: const Text('Bạn có chắc muốn xóa tin nhắn / báo cáo này không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final ok = await Session.I.deleteTeamMessage(id);
      if (ok && mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == id);
        });
        toast(context, 'Đã xóa tin nhắn');
      }
    } catch (e) {
      if (mounted) toast(context, 'Lỗi xóa tin nhắn: $e', error: true);
    }
  }

  String _getStationTitle() {
    if (_selectedStationId == null || _selectedStationId == 0) {
      return 'Kênh thông báo toàn hệ thống';
    }
    final match = _stations.where((s) => s.id == _selectedStationId).toList();
    if (match.isNotEmpty) {
      return 'Kênh riêng: ${match.first.name}';
    }
    return 'Kênh riêng: Trạm #$_selectedStationId';
  }

  void _attachStationTelemetry() {
    if (_selectedStationId == null || _selectedStationId == 0) {
      toast(context, 'Vui lòng chọn trạm trước để đính kèm thông số');
      return;
    }

    final match = _stations.where((s) => s.id == _selectedStationId).toList();
    if (match.isEmpty) {
      toast(context, 'Chưa tải được thông số trạm đã chọn');
      return;
    }
    final st = match.first;

    final tStr = st.airTemp != null ? '${st.airTemp!.toStringAsFixed(1)}°C' : '--°C';
    final hStr = st.airHum != null ? '${st.airHum!.toStringAsFixed(0)}%' : '--%';
    final relayStr = st.relayOn ? 'Rơ-le: BẬT' : 'Rơ-le: TẮT';
    final dewStr = st.dewPoint != null ? 'Điểm sương: ${st.dewPoint!.toStringAsFixed(1)}°C' : '';

    setState(() {
      _attachedTelemetry = '$tStr | $hStr | $relayStr ${dewStr.isNotEmpty ? " | $dewStr" : ""}';
    });

    HapticFeedback.mediumImpact();
    toast(context, 'Đã đính kèm thông số hiện thời của ${st.name}');
  }

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'INCIDENT':
        return AppColors.danger;
      case 'MAINTENANCE':
        return AppColors.warn;
      case 'RESOLVED':
        return AppColors.ok;
      default:
        return const Color(0xFF38BDF8);
    }
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'INCIDENT':
        return '🚨 BÁO CÁO SỰ CỐ';
      case 'MAINTENANCE':
        return '📢 THÔNG BÁO BẢO TRÌ';
      case 'RESOLVED':
        return '✅ ĐÃ KHẮC PHỤC';
      default:
        return '💬 TRAO ĐỔI';
    }
  }

  String _formatTime(String raw) {
    try {
      if (raw.contains(' ')) {
        final parts = raw.split(' ');
        if (parts.length >= 2) {
          final tParts = parts[1].split(':');
          if (tParts.length >= 2) {
            return '${tParts[0]}:${tParts[1]}';
          }
        }
      }
      return raw;
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Session.I.user?.id ?? 0;
    final isAdmin = Session.I.isAdmin;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trao đổi & Báo cáo Sự cố', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              _getStationTitle(),
              style: const TextStyle(fontSize: 11.5, color: AppColors.text2),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mark_chat_unread_outlined),
            tooltip: 'Đánh dấu chưa đọc để kiểm tra',
            onPressed: () async {
              final sp = await SharedPreferences.getInstance();
              await sp.setInt('last_read_team_message_id', 0);
              widget.onLatestMessageSeen?.call(0);
              if (context.mounted) {
                toast(context, 'Đã đánh dấu chưa đọc! Về tab Tổng quan sẽ hiện số đỏ.');
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Làm mới',
            onPressed: _loadInitial,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Station Channel Selector Chips
          _buildStationFilterBar(),

          // 2. Messages Chat List (Messenger Compact Style)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Lỗi: $_error', style: const TextStyle(color: AppColors.danger)),
                            const SizedBox(height: 8),
                            ElevatedButton(onPressed: _loadInitial, child: const Text('Thử lại')),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (ctx, i) {
                              final msg = _messages[i];
                              final isMe = msg.userId == currentUserId;
                              return _buildMessageItem(msg, isMe, isAdmin);
                            },
                          ),
          ),

          // 3. Message Input Area (Messenger Sleek Capsule)
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildStationFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Tất cả kênh', style: TextStyle(fontSize: 12)),
              selected: _selectedStationId == null || _selectedStationId == 0,
              visualDensity: VisualDensity.compact,
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _selectedStationId = null;
                    _attachedTelemetry = null;
                  });
                  _loadInitial();
                }
              },
            ),
            const SizedBox(width: 6),
            ..._stations.map((s) {
              final isSel = _selectedStationId == s.id;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    Icons.sensors_rounded,
                    size: 13,
                    color: isSel ? Colors.white : AppColors.primary,
                  ),
                  label: Text(s.name, style: const TextStyle(fontSize: 12)),
                  selected: isSel,
                  onSelected: (val) {
                    setState(() {
                      _selectedStationId = val ? s.id : null;
                      _attachedTelemetry = null;
                    });
                    _loadInitial();
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 48, color: AppColors.muted.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          const Text(
            'Chưa có tin nhắn hoặc báo cáo nào',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text2, fontSize: 13.5),
          ),
          const SizedBox(height: 4),
          const Text(
            'Gửi tin nhắn đầu tiên để trao đổi hiện trường!',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(TeamMessageItem msg, bool isMe, bool isAdmin) {
    final catColor = _categoryColor(msg.category);
    final canDelete = isMe || isAdmin;
    final isSpecialCategory = msg.category != 'CHAT';
    final hasTelemetry = msg.attachedTelemetry != null && msg.attachedTelemetry!.isNotEmpty;
    final hasStation = msg.stationName != null && msg.stationName!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.surface3,
              child: Text(
                msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.primaryLight),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      '${msg.senderName} · ${msg.senderRole == 'admin' ? 'Admin' : 'KTV'}',
                      style: const TextStyle(fontSize: 10.5, color: AppColors.text3, fontWeight: FontWeight.w500),
                    ),
                  ),

                // Bong bóng tin nhắn nhỏ gọn kiểu Messenger
                GestureDetector(
                  onLongPress: canDelete ? () => _deleteMessage(msg.id) : null,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? const LinearGradient(
                              colors: [Color(0xFF0084FF), Color(0xFF006FE6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isMe ? null : const Color(0xFF242A38),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 3),
                        bottomRight: Radius.circular(isMe ? 3 : 18),
                      ),
                      border: isMe
                          ? null
                          : Border.all(
                              color: isSpecialCategory ? catColor.withValues(alpha: 0.5) : AppColors.border.withValues(alpha: 0.6),
                              width: isSpecialCategory ? 1.0 : 0.6,
                            ),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tag phân loại chỉ hiện khi là SỰ CỐ / BẢO TRÌ / ĐÃ KHẮC PHỤC
                        if (isSpecialCategory)
                          Container(
                            margin: const EdgeInsets.only(bottom: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: isMe ? 0.35 : 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: catColor.withValues(alpha: 0.6), width: 0.8),
                            ),
                            child: Text(
                              _categoryLabel(msg.category),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isMe ? Colors.white : catColor,
                              ),
                            ),
                          ),

                        // Tên trạm nếu có
                        if (hasStation)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.place_outlined, size: 11, color: isMe ? Colors.white70 : AppColors.text2),
                                const SizedBox(width: 3),
                                Text(
                                  msg.stationName!,
                                  style: TextStyle(fontSize: 10.5, color: isMe ? Colors.white70 : AppColors.text2, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),

                        // Snapshot thông số đính kèm
                        if (hasTelemetry)
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isMe ? Colors.black26 : AppColors.surface3,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.analytics_outlined, size: 11, color: isMe ? Colors.white : const Color(0xFF38BDF8)),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    msg.attachedTelemetry!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: isMe ? Colors.white : const Color(0xFF38BDF8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Nội dung tin nhắn + Giờ gọn gàng (Wrap inline)
                        Wrap(
                          alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: 7,
                          runSpacing: 2,
                          children: [
                            Text(
                              msg.content,
                              style: TextStyle(
                                fontSize: 14,
                                color: isMe ? Colors.white : AppColors.text,
                                height: 1.3,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 0.5),
                              child: Text(
                                _formatTime(msg.createdAt),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: isMe ? Colors.white70 : AppColors.text3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final hasStation = _selectedStationId != null && _selectedStationId! > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thanh đính kèm số liệu / tag nếu đang chọn
            if (_attachedTelemetry != null || _selectedCategory != 'CHAT')
              Padding(
                padding: const EdgeInsets.only(bottom: 5, left: 6, right: 6),
                child: Row(
                  children: [
                    if (_selectedCategory != 'CHAT')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _categoryColor(_selectedCategory).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _categoryColor(_selectedCategory).withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _categoryLabel(_selectedCategory),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _categoryColor(_selectedCategory)),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => setState(() => _selectedCategory = 'CHAT'),
                              child: const Icon(Icons.close, size: 12, color: AppColors.text3),
                            ),
                          ],
                        ),
                      ),
                    if (_attachedTelemetry != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.analytics_outlined, size: 12, color: Color(0xFF38BDF8)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _attachedTelemetry!,
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF38BDF8), fontFamily: 'monospace'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              InkWell(
                                onTap: () => setState(() => _attachedTelemetry = null),
                                child: const Icon(Icons.close, size: 12, color: AppColors.text3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // Khung chat Messenger
            Row(
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Chọn phân loại tin nhắn',
                  icon: Icon(
                    _selectedCategory == 'INCIDENT'
                        ? Icons.emergency_rounded
                        : (_selectedCategory == 'MAINTENANCE'
                            ? Icons.campaign_rounded
                            : (_selectedCategory == 'RESOLVED' ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded)),
                    color: _selectedCategory == 'CHAT' ? AppColors.text2 : _categoryColor(_selectedCategory),
                    size: 24,
                  ),
                  onSelected: (val) => setState(() => _selectedCategory = val),
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'CHAT', child: Text('💬 Trao đổi')),
                    PopupMenuItem(value: 'INCIDENT', child: Text('🚨 Báo sự cố')),
                    PopupMenuItem(value: 'MAINTENANCE', child: Text('📢 Bảo trì')),
                    PopupMenuItem(value: 'RESOLVED', child: Text('✅ Đã khắc phục')),
                  ],
                ),
                if (hasStation)
                  IconButton(
                    icon: Icon(
                      Icons.analytics_outlined,
                      color: _attachedTelemetry != null ? const Color(0xFF38BDF8) : AppColors.text3,
                      size: 22,
                    ),
                    tooltip: 'Đính kèm số liệu trạm',
                    onPressed: _attachStationTelemetry,
                  ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _textCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      style: const TextStyle(fontSize: 13.5, color: AppColors.text),
                      decoration: InputDecoration(
                        hintText: _selectedCategory == 'INCIDENT'
                            ? 'Mô tả sự cố vi khí hậu...'
                            : (_selectedCategory == 'MAINTENANCE' ? 'Nội dung bảo trì...' : 'Nhắn tin...'),
                        hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.text3),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _sending ? null : _sendMessage,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0084FF),
                      ),
                      alignment: Alignment.center,
                      child: _sending
                          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, size: 17, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
