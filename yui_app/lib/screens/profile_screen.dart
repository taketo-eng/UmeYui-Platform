import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../core/auth_provider.dart';
import '../models/user.dart';
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploadingAvatar = false;

  Future<void> _pickAndUploadAvatar() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?.id;
    if (userId == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploadingAvatar = true);
    try {
      await apiClient.uploadAvatar(userId, File(picked.path));
      // キャッシュをクリアして新しい画像を強制取得
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await auth.refreshUser();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditDialog(context, user),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _AvatarSection(
              user: user,
              isUploading: _isUploadingAvatar,
              onTap: _pickAndUploadAvatar,
            ),
            const SizedBox(height: 0),
            _ProfileInfo(user: user),
            const SizedBox(height: 16),
            _SocialLinks(user: user),
            const Divider(height: 40),
            _ActionButtons(user: user),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, User user) async {
    final shopNameCtrl = TextEditingController(text: user.shopName);
    final bioCtrl = TextEditingController(text: user.bio);
    final websiteCtrl = TextEditingController(text: user.websiteUrl);
    final instagramCtrl = TextEditingController(text: user.instagramUrl);
    final xCtrl = TextEditingController(text: user.xUrl);
    final lineCtrl = TextEditingController(text: user.lineUrl);
    final facebookCtrl = TextEditingController(text: user.facebookUrl);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('プロフィールを編集'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'SNSリンク',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              _SnsField(
                controller: websiteCtrl,
                label: 'ホームページ',
                icon: Icons.language,
              ),
              _SnsField(
                controller: instagramCtrl,
                label: 'Instagram URL',
                icon: Icons.camera_alt_outlined,
              ),
              _SnsField(
                controller: xCtrl,
                label: 'X (Twitter) URL',
                icon: Icons.alternate_email,
              ),
              _SnsField(
                controller: lineCtrl,
                label: 'LINE URL',
                icon: Icons.chat_outlined,
              ),
              _SnsField(
                controller: facebookCtrl,
                label: 'Facebook URL',
                icon: Icons.facebook_outlined,
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
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              try {
                await apiClient.updateProfile(
                  auth.user!.id,
                  shopName: shopNameCtrl.text.trim(),
                  bio: bioCtrl.text.trim(),
                  websiteUrl: websiteCtrl.text.trim().isEmpty
                      ? null
                      : websiteCtrl.text.trim(),
                  instagramUrl: instagramCtrl.text.trim().isEmpty
                      ? null
                      : instagramCtrl.text.trim(),
                  xUrl: xCtrl.text.trim().isEmpty ? null : xCtrl.text.trim(),
                  lineUrl: lineCtrl.text.trim().isEmpty
                      ? null
                      : lineCtrl.text.trim(),
                  facebookUrl: facebookCtrl.text.trim().isEmpty
                      ? null
                      : facebookCtrl.text.trim(),
                );
                await auth.refreshUser();
                if (ctx.mounted) Navigator.pop(ctx);
              } on ApiException catch (e) {
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
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// SNSフィールド（編集ダイアログ内）
class _SnsField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _SnsField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

// ---- 他の出店者のプロフィール画面（チャットから遷移） ----

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  User? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final json = await apiClient.getMe(widget.userId);
      setState(() {
        _user = User.fromJson(json);
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_user?.shopName ?? 'プロフィール')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _user == null
          ? const Center(child: Text('ユーザーが見つかりません'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _AvatarSection(user: _user!),
                  const SizedBox(height: 24),
                  _ProfileInfo(user: _user!),
                  const SizedBox(height: 16),
                  _SocialLinks(user: _user!),
                ],
              ),
            ),
    );
  }
}

// ---- 共通ウィジェット ----

class _AvatarSection extends StatelessWidget {
  final User user;
  final VoidCallback? onTap;
  final bool isUploading;

  const _AvatarSection({
    required this.user,
    this.onTap,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // 背景バー
        Container(
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -40),
          child: GestureDetector(
            onTap: isUploading ? null : onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: user.avatarUrl != null
                        ? NetworkImage(resolveUrl(user.avatarUrl!))
                        : null,
                    child: user.avatarUrl == null
                        ? Text(
                            (user.shopName ?? user.email)
                                .substring(0, 1)
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                ),
                // アップロード中インジケーター
                if (isUploading)
                  const CircularProgressIndicator(strokeWidth: 3),
                // カメラアイコン（タップ可能な場合のみ）
                if (onTap != null && !isUploading)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileInfo extends StatelessWidget {
  final User user;
  const _ProfileInfo({required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          user.shopName ?? '屋号未設定',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (user.bio != null && user.bio!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            user.bio!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ],
    );
  }
}

class _SocialLinks extends StatelessWidget {
  final User user;
  const _SocialLinks({required this.user});

  @override
  Widget build(BuildContext context) {
    final links = user.socialLinks;
    if (links.isEmpty) return const SizedBox.shrink();

    final icons = {
      'website': (Icons.language, '公式サイト'),
      'instagram': (Icons.camera_alt_outlined, 'Instagram'),
      'x': (Icons.alternate_email, 'X'),
      'line': (Icons.chat_outlined, 'LINE'),
      'facebook': (Icons.facebook_outlined, 'Facebook'),
    };

    return Column(
      children: links.entries.map((entry) {
        final (icon, label) = icons[entry.key]!;
        return ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(label),
          subtitle: Text(entry.value, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.open_in_new, size: 16),
          onTap: () async {
            final uri = Uri.tryParse(entry.value);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        );
      }).toList(),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final User user;
  const _ActionButtons({required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.email_outlined),
          label: const Text('メールアドレスを変更'),
          onPressed: () => _showChangeEmailDialog(context),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.lock_outline),
          label: const Text('パスワードを変更'),
          onPressed: () => _showChangePasswordDialog(context),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout, color: Colors.red),
          label: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('ログアウト'),
                content: const Text('ログアウトしますか？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('キャンセル'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('ログアウト'),
                  ),
                ],
              ),
            );
            if (confirmed == true && context.mounted) {
              await context.read<AuthProvider>().logout();
            }
          },
        ),
      ],
    );
  }

  Future<void> _showChangeEmailDialog(BuildContext context) async {
    final passwordCtrl = TextEditingController();

    // ステップ1: 現在のパスワードで本人確認 → 旧メアドに確認コード送信
    final emailHint = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          bool loading = false;
          return AlertDialog(
            title: const Text('メールアドレスを変更'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '本人確認のため現在のパスワードを入力してください。\n確認コードを現在のメールアドレスに送信します。',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '現在のパスワード',
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
                onPressed: loading
                    ? null
                    : () async {
                        setState(() => loading = true);
                        try {
                          final result = await apiClient.requestEmailChange(passwordCtrl.text);
                          if (ctx.mounted) {
                            Navigator.pop(ctx, result['email_hint'] as String?);
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
                    : const Text('確認コードを送信'),
              ),
            ],
          );
        },
      ),
    );

    if (emailHint == null || !context.mounted) return;

    // ステップ2: 確認コード + 新しいメアド（2回入力）
    final codeCtrl = TextEditingController();
    final newEmailCtrl = TextEditingController();
    final newEmailConfirmCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          bool loading = false;
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '確認コードと新しいメアドを入力',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '$emailHint に送信された6桁のコードを入力してください。',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: const InputDecoration(
                    hintText: '000000',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('キャンセル'),
                    ),
                    const SizedBox(width: 8),
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
                                await apiClient.verifyEmailChange(
                                  codeCtrl.text.trim(),
                                  newEmailCtrl.text.trim(),
                                );
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('メールアドレスを変更しました。再ログインしてください。'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  await context.read<AuthProvider>().logout();
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    // ステップ1: パスワード入力
    final emailHint = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          bool loading = false;
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: const Text('パスワードを変更'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '現在のパスワード',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '新しいパスワード（8文字以上）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '新しいパスワード（確認）',
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
                              content: Text('新しいパスワードが一致しません'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        setState(() => loading = true);
                        try {
                          final result = await apiClient.requestPasswordChange(
                            currentCtrl.text,
                            newCtrl.text,
                          );
                          if (ctx.mounted) {
                            Navigator.pop(ctx, result['email_hint'] as String?);
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
                    : const Text('確認コードを送信'),
              ),
            ],
          );
        },
      ),
    );

    if (emailHint == null || !context.mounted) return;

    // ステップ2: 確認コード入力
    final codeCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          bool loading = false;
          return AlertDialog(
            title: const Text('確認コードを入力'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$emailHint に送信された6桁のコードを入力してください。',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: const InputDecoration(
                    hintText: '000000',
                    border: OutlineInputBorder(),
                    counterText: '',
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
                onPressed: loading
                    ? null
                    : () async {
                        setState(() => loading = true);
                        try {
                          await apiClient.verifyPasswordChange(codeCtrl.text.trim());
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('パスワードを変更しました'),
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
                    : const Text('確定する'),
              ),
            ],
          );
        },
      ),
    );
  }
}
