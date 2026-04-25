import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/auth_provider.dart';
import '../models/user.dart';
import 'profile_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<User> _users = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await apiClient.getUsers();
      setState(() {
        _users = data
            .map((e) => User.fromJson(e as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUser = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ユーザー管理'),
        actions: [
          // 自分のプロフィールへ
          IconButton(
            icon: myUser?.avatarUrl != null
                ? CircleAvatar(
                    radius: 16,
                    backgroundImage: NetworkImage(resolveUrl(myUser!.avatarUrl!)),
                  )
                : const Icon(Icons.person_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.person_add),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadUsers, child: const Text('再読み込み')),
          ],
        ),
      );
    }
    if (_users.isEmpty) {
      return const Center(child: Text('出店者がいません'));
    }
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, index) => _UserTile(
          user: _users[index],
          onTap: () => _showDetailSheet(context, _users[index]),
        ),
      ),
    );
  }

  // 新規作成ダイアログ
  Future<void> _showCreateDialog(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final shopNameCtrl = TextEditingController();
    bool obscure = true;

    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: const Text('出店者アカウントを作成'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'パスワード（8文字以上）*',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: shopNameCtrl,
                  decoration: const InputDecoration(
                    labelText: '屋号（任意）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: isSaving ? null : () async {
                if (emailCtrl.text.trim().isEmpty ||
                    passwordCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('メールアドレスとパスワードは必須です'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                setDialogState(() => isSaving = true);
                try {
                  await apiClient.createUser(
                    email: emailCtrl.text.trim(),
                    password: passwordCtrl.text,
                    shopName: shopNameCtrl.text.trim(),
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('アカウントを作成しました'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _loadUsers();
                  }
                } on ApiException catch (e) {
                  if (ctx.mounted) {
                    setDialogState(() => isSaving = false);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(e.message),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('作成'),
            ),
          ],
        ),
      ),
    );
  }

  // ユーザー詳細 BottomSheet
  Future<void> _showDetailSheet(BuildContext context, User user) async {
    final myId = context.read<AuthProvider>().user?.id;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _UserDetailSheet(
        user: user,
        isSelf: user.id == myId,
        onChanged: () {
          Navigator.pop(ctx);
          _loadUsers();
        },
      ),
    );
  }
}

// ユーザー一覧タイル
class _UserTile extends StatelessWidget {
  final User user;
  final VoidCallback onTap;

  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        backgroundImage: user.avatarUrl != null
            ? NetworkImage(resolveUrl(user.avatarUrl!))
            : null,
        child: user.avatarUrl == null
            ? Text(
                (user.shopName ?? user.email).substring(0, 1).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : null,
      ),
      title: Text(user.shopName ?? '（屋号未設定）'),
      subtitle: Text(user.email, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: user.isActive
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFF0EDEE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              user.isActive ? '有効' : '無効',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: user.isActive
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF888088),
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}

// ユーザー詳細 BottomSheet の中身
class _UserDetailSheet extends StatefulWidget {
  final User user;
  final bool isSelf;
  final VoidCallback onChanged;

  const _UserDetailSheet({
    required this.user,
    required this.isSelf,
    required this.onChanged,
  });

  @override
  State<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<_UserDetailSheet> {
  bool _isTogglingActive = false;

  User get user => widget.user;
  bool get isSelf => widget.isSelf;
  VoidCallback get onChanged => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ハンドル
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ユーザー情報
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                backgroundImage: user.avatarUrl != null
                    ? NetworkImage(resolveUrl(user.avatarUrl!))
                    : null,
                child: user.avatarUrl == null
                    ? Text(
                        (user.shopName ?? user.email)
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(fontSize: 22),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.shopName ?? '（屋号未設定）',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      user.email,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 有効化・無効化（自分自身には表示しない）
          if (!isSelf) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(
                  user.isActive ? Icons.block : Icons.check_circle_outline,
                ),
                label: Text(user.isActive ? 'アカウントを無効化' : 'アカウントを有効化'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: user.isActive ? Colors.orange : Colors.green,
                  side: BorderSide(
                    color: user.isActive ? Colors.orange : Colors.green,
                  ),
                ),
                onPressed: _isTogglingActive ? null : () async {
                  setState(() => _isTogglingActive = true);
                  try {
                    await apiClient.setUserActive(user.id, !user.isActive);
                    onChanged();
                  } on ApiException catch (e) {
                    if (mounted) {
                      setState(() => _isTogglingActive = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.message),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
          ],

          // プロフィール編集（全員に表示）
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('プロフィールを編集'),
              onPressed: () {
                Navigator.pop(context);
                _showEditDialog(context);
              },
            ),
          ),

          // パスワードリセット・メールアドレス変更（出店者のみ）
          if (!isSelf) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.lock_reset_outlined),
                label: const Text('パスワードをリセット'),
                onPressed: () {
                  Navigator.pop(context);
                  _showResetPasswordDialog(context);
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.email_outlined),
                label: const Text('メールアドレスを変更（復旧）'),
                onPressed: () {
                  Navigator.pop(context);
                  _showChangeEmailDialog(context);
                },
              ),
            ),
          ],

          // 削除（自分自身には表示しない）
          if (!isSelf) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'アカウントを削除',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: () => _confirmDelete(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final shopNameCtrl = TextEditingController(text: user.shopName);
    final bioCtrl = TextEditingController(text: user.bio);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text('${user.shopName ?? user.email} を編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: shopNameCtrl,
              decoration: const InputDecoration(
                labelText: '屋号',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bioCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '自己紹介',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: isSaving ? null : () async {
              setDialogState(() => isSaving = true);
              try {
                await apiClient.updateProfile(
                  user.id,
                  shopName: shopNameCtrl.text.trim(),
                  bio: bioCtrl.text.trim(),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  onChanged();
                }
              } on ApiException catch (e) {
                if (ctx.mounted) {
                  setDialogState(() => isSaving = false);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('保存'),
          ),
        ],
      ),
    ),
  );
  }

  Future<void> _showResetPasswordDialog(BuildContext context) async {
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          bool loading = false;
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Text('${user.shopName ?? user.email} のパスワードをリセット'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: newCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: '新しいパスワード（8文字以上）',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: obscure,
                    decoration: const InputDecoration(
                      labelText: '確認',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        if (newCtrl.text != confirmCtrl.text) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('パスワードが一致しません'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        setState(() => loading = true);
                        try {
                          await apiClient.adminResetPassword(user.id, newCtrl.text);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('パスワードをリセットしました'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } on ApiException catch (e) {
                          setState(() => loading = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(e.message),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('リセットする'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showChangeEmailDialog(BuildContext context) async {
    final newEmailCtrl = TextEditingController();
    final newEmailConfirmCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          bool loading = false;
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Text('${user.shopName ?? user.email} のメアドを変更（復旧）'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '管理者権限でメールアドレスを直接変更します。\n出展者の既存セッションはすべて無効になります。',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: '新しいメールアドレス',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newEmailConfirmCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: '新しいメールアドレス（確認）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        if (newEmailCtrl.text.trim() != newEmailConfirmCtrl.text.trim()) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('メールアドレスが一致しません'), backgroundColor: Colors.red),
                          );
                          return;
                        }
                        setState(() => loading = true);
                        try {
                          await apiClient.adminChangeEmail(user.id, newEmailCtrl.text.trim());
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            onChanged();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('メールアドレスを変更しました'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } on ApiException catch (e) {
                          setState(() => loading = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                child: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('変更する'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('アカウントを削除'),
        content: Text(
          '「${user.shopName ?? user.email}」を削除しますか？\nこの操作は元に戻せません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await apiClient.deleteUser(user.id);
        onChanged();
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
