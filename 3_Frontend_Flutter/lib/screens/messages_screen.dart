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
  final ValueChanged<int>? onLatestMessageSeen;
  const MessagesScreen({super.key, this.initialStationId, this.onLatestMessageSeen});

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
  void dispose() {
    _pollTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _notifySeen(int id) async {
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

          // 2. Messages Chat List
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: _messages.length,
                            itemBuilder: (ctx, i) {
                              final msg = _messages[i];
                              final isMe = msg.userId == currentUserId;
                              return _buildMessageItem(msg, isMe, isAdmin);
                            },
                          ),
          ),

          // 3. Message Input Area with Category Tagging & Telemetry Attachment
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildStationFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Tất cả kênh'),
              selected: _selectedStationId == null || _selectedStationId == 0,
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
            const SizedBox(width: 8),
            ..._stations.map((s) {
              final isSel = _selectedStationId == s.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(
                    Icons.sensors_rounded,
                    size: 14,
                    color: isSel ? Colors.white : AppColors.primary,
                  ),
                  label: Text(s.name),
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
          Icon(Icons.forum_outlined, size: 56, color: AppColors.muted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text(
            'Chưa có tin nhắn hoặc báo cáo nào',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text2, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Hãy gửi tin nhắn đầu tiên để thông báo hoặc trao đổi công việc!',
            style: TextStyle(color: AppColors.text3, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(TeamMessageItem msg, bool isMe, bool isAdmin) {
    final catColor = _categoryColor(msg.category);
    final canDelete = isMe || isAdmin;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.surface3,
              child: Text(
                msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primaryLight),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF0F766E).withValues(alpha: 0.25) : AppColors.surface2,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMe ? 14 : 2),
                  bottomRight: Radius.circular(isMe ? 2 : 14),
                ),
                border: Border.all(
                  color: isMe ? const Color(0xFF14B8A6).withValues(alpha: 0.4) : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender info & Category tag
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isMe ? 'Bạn' : msg.senderName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (msg.senderRole == 'admin' ? const Color(0xFF8B5CF6) : AppColors.primary).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          msg.senderRole == 'admin' ? 'Admin' : 'KTV',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: msg.senderRole == 'admin' ? const Color(0xFFA78BFA) : AppColors.primaryLight,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (canDelete)
                        InkWell(
                          onTap: () => _deleteMessage(msg.id),
                          child: const Icon(Icons.close_rounded, size: 14, color: AppColors.text3),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Category Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: catColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _categoryLabel(msg.category),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: catColor),
                    ),
                  ),

                  // Station Tag (if attached)
                  if (msg.stationName != null && msg.stationName!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.place_outlined, size: 12, color: AppColors.text2),
                        const SizedBox(width: 4),
                        Text(
                          msg.stationName!,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.text2, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],

                  // Telemetry snapshot badge
                  if (msg.attachedTelemetry != null && msg.attachedTelemetry!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.analytics_outlined, size: 14, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              msg.attachedTelemetry!,
                              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: Color(0xFF38BDF8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Message content
                  const SizedBox(height: 8),
                  SelectableText(
                    msg.content,
                    style: const TextStyle(fontSize: 13.5, color: AppColors.text, height: 1.4),
                  ),

                  // Time
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      msg.createdAt,
                      style: const TextStyle(fontSize: 10, color: AppColors.text3),
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

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category Selector & Telemetry Attach bar
            Row(
              children: [
                DropdownButton<String>(
                  value: _selectedCategory,
                  underline: const SizedBox(),
                  dropdownColor: AppColors.surface2,
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                  items: const [
                    DropdownMenuItem(value: 'CHAT', child: Text('💬 Trao đổi')),
                    DropdownMenuItem(value: 'INCIDENT', child: Text('🚨 Báo sự cố')),
                    DropdownMenuItem(value: 'MAINTENANCE', child: Text('📢 Bảo trì')),
                    DropdownMenuItem(value: 'RESOLVED', child: Text('✅ Khắc phục')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
                const Spacer(),
                if (_selectedStationId != null && _selectedStationId! > 0)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.add_chart_rounded, size: 14, color: Color(0xFF38BDF8)),
                    label: Text(
                      _attachedTelemetry == null ? 'Đính kèm số liệu' : 'Đã đính kèm',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF38BDF8)),
                    ),
                    onPressed: _attachStationTelemetry,
                  ),
              ],
            ),

            if (_attachedTelemetry != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 13, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _attachedTelemetry!,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _attachedTelemetry = null),
                      child: const Icon(Icons.close, size: 14, color: AppColors.text3),
                    ),
                  ],
                ),
              ),
            ],

            // Input TextField + Send button
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    style: const TextStyle(fontSize: 13.5, color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: _selectedCategory == 'INCIDENT'
                          ? 'Mô tả chi tiết sự cố vi khí hậu cần báo cáo...'
                          : (_selectedCategory == 'MAINTENANCE'
                              ? 'Nội dung thông báo bảo trì, sửa chữa trạm...'
                              : 'Nhập nội dung tin nhắn trao đổi...'),
                      hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.text3),
                      filled: true,
                      fillColor: AppColors.surface2,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: _sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  onPressed: _sending ? null : _sendMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
