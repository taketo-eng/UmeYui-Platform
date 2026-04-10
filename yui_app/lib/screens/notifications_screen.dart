import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../models/app_notification.dart';
import '../models/join_request.dart';
import 'profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onRefreshed;
  const NotificationsScreen({super.key, this.onRefreshed});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<AppNotification> _announcements = [];
  List<JoinRequest> _incoming = [];
  List<JoinRequest> _outgoing = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        apiClient.getNotifications(),
        apiClient.getIncomingRequests(),
        apiClient.getOutgoingRequests(),
      ]);
      // 全通知を既読に
      await apiClient.markAllNotificationsRead();
      setState(() {
        _announcements = results[0]
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        _incoming = results[1]
            .map((e) => JoinRequest.fromJson(e as Map<String, dynamic>))
            .toList();
        _outgoing = results[2]
            .map((e) => JoinRequest.fromJson(e as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
      widget.onRefreshed?.call();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  int get _unreadCount => _announcements.where((n) => !n.isRead).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('お知らせ'),
                  if (_unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge(label: Text('$_unreadCount')),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('受信'),
                  if (_incoming.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Badge(label: Text('${_incoming.length}')),
                  ],
                ],
              ),
            ),
            const Tab(text: '送信'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                      onPressed: _load, child: const Text('再読み込み')),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _AnnouncementsTab(notifications: _announcements),
                _IncomingTab(requests: _incoming, onChanged: _load),
                _OutgoingTab(requests: _outgoing),
              ],
            ),
    );
  }
}

// ---- お知らせタブ（システム通知） ----

class _AnnouncementsTab extends StatelessWidget {
  final List<AppNotification> notifications;
  const _AnnouncementsTab({required this.notifications});

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return const Center(child: Text('お知らせはありません'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: notifications.length,
      itemBuilder: (context, index) {
        final n = notifications[index];
        final (icon, color) = switch (n.type) {
          'recruitment_started' => (Icons.campaign_outlined, const Color(0xFFE07B00)),
          'request_approved' => (Icons.check_circle_outline, const Color(0xFF2E7D32)),
          'request_rejected' => (Icons.cancel_outlined, const Color(0xFFC62828)),
          _ => (Icons.notifications_outlined, Colors.grey),
        };
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(n.message, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              n.createdAt.substring(0, 10),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            // 未読は左端に色付きバー
            tileColor: n.isRead ? null : color.withValues(alpha: 0.04),
          ),
        );
      },
    );
  }
}

// ---- 受信タブ（発起人として受け取った申請） ----

class _IncomingTab extends StatelessWidget {
  final List<JoinRequest> requests;
  final VoidCallback onChanged;

  const _IncomingTab({required this.requests, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const Center(child: Text('受け取った申請はありません'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) => _IncomingCard(
        request: requests[index],
        onChanged: onChanged,
      ),
    );
  }
}

class _IncomingCard extends StatefulWidget {
  final JoinRequest request;
  final VoidCallback onChanged;

  const _IncomingCard({required this.request, required this.onChanged});

  @override
  State<_IncomingCard> createState() => _IncomingCardState();
}

class _IncomingCardState extends State<_IncomingCard> {
  bool _isLoading = false;

  Future<void> _respond(String action) async {
    String? responseMessage;

    if (action == 'reject') {
      responseMessage = await _showResponseDialog(isApprove: false);
      if (responseMessage == null) return; // キャンセル
    } else {
      responseMessage = await _showResponseDialog(isApprove: true);
      if (responseMessage == null) return; // キャンセル
    }

    setState(() => _isLoading = true);
    try {
      await apiClient.respondToRequest(
        widget.request.id,
        action: action,
        responseMessage: responseMessage,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'approve' ? '承認しました' : '却下しました'),
            backgroundColor:
                action == 'approve' ? Colors.green : Colors.orange,
          ),
        );
        widget.onChanged();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _showResponseDialog({required bool isApprove}) async {
    final msgCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(isApprove ? '申請を承認' : '申請を却下'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: msgCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'メッセージ（任意）',
                  hintText: isApprove
                      ? '当日よろしくお願いします！'
                      : '今回は定員に達したため...',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('戻る'),
          ),
          FilledButton(
            style: isApprove
                ? null
                : FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, msgCtrl.text),
            child: Text(isApprove ? '承認する' : '却下する'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 枠情報
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    req.slotDate ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                if (req.startTime != null && req.endTime != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${req.startTime} 〜 ${req.endTime}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // 申請者情報（タップでプロフィール表示）
            InkWell(
              onTap: req.requesterId != null
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UserProfileScreen(userId: req.requesterId!),
                        ),
                      )
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: req.avatarUrl != null
                          ? NetworkImage(resolveUrl(req.avatarUrl!))
                          : null,
                      child: req.avatarUrl == null
                          ? Text(
                              (req.shopName ?? req.email ?? '?')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(fontSize: 14),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            req.shopName ?? req.email ?? '名前未設定',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (req.email != null)
                            Text(req.email!,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    if (req.requesterId != null)
                      const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  ],
                ),
              ),
            ),
            // PR メッセージ
            if (req.message != null && req.message!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(req.message!,
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
            const SizedBox(height: 14),
            // 承認 / 却下ボタン
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                    ),
                    onPressed: _isLoading ? null : () => _respond('reject'),
                    child: const Text('却下'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isLoading ? null : () => _respond('approve'),
                    child: _isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('承認'),
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

// ---- 送信タブ（自分が送った申請） ----

class _OutgoingTab extends StatelessWidget {
  final List<JoinRequest> requests;
  const _OutgoingTab({required this.requests});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const Center(child: Text('送った申請はありません'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) =>
          _OutgoingCard(request: requests[index]),
    );
  }
}

class _OutgoingCard extends StatelessWidget {
  final JoinRequest request;
  const _OutgoingCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final req = request;
    final theme = Theme.of(context);

    final (statusLabel, statusBg, statusFg) = switch (req.status) {
      'pending' => ('審査中', const Color(0xFFFFF3E0), const Color(0xFFE07B00)),
      'approved' => ('承認済み', const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'rejected' => ('却下', const Color(0xFFFFEBEE), const Color(0xFFC62828)),
      _ => ('不明', const Color(0xFFF0EDEE), const Color(0xFF888088)),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 枠情報 + ステータス
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    req.slotDate ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusFg,
                    ),
                  ),
                ),
              ],
            ),
            if (req.startTime != null && req.endTime != null) ...[
              const SizedBox(height: 4),
              Text(
                '${req.startTime} 〜 ${req.endTime}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            // 自分のメッセージ
            if (req.message != null && req.message!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(req.message!,
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
            // 発起人からの返信
            if (req.responseMessage != null &&
                req.responseMessage!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.reply, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      req.responseMessage!,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF616161)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
