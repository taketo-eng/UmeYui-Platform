const shopCategories = [
  'その他',
  '飲食・ドリンク',
  'スイーツ・パン',
  'ハンドメイド・クラフト',
  'アクセサリー・ジュエリー',
  '衣類・ファッション',
  '雑貨・インテリア',
  '植物・フラワー',
  'アート・イラスト',
  '音楽・パフォーマンス',
  'ワークショップ',
  'セミナー',
];

class User {
  final String id;
  final String email;
  final String role;
  final String? shopName;
  final String? bio;
  final String? homepageBio;
  final String category;
  final String? avatarUrl;
  final String? homepageAvatarUrl;
  final bool isActive;
  final String? websiteUrl;
  final String? instagramUrl;
  final String? xUrl;
  final String? lineUrl;
  final String? facebookUrl;

  const User({
    required this.id,
    required this.email,
    required this.role,
    this.shopName,
    this.bio,
    this.homepageBio,
    this.category = 'その他',
    this.avatarUrl,
    this.homepageAvatarUrl,
    required this.isActive,
    this.websiteUrl,
    this.instagramUrl,
    this.xUrl,
    this.lineUrl,
    this.facebookUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    email: json['email'] as String,
    role: json['role'] as String,
    shopName: json['shop_name'] as String?,
    bio: json['bio'] as String?,
    homepageBio: json['homepage_bio'] as String?,
    category: json['category'] as String? ?? 'その他',
    avatarUrl: json['avatar_url'] as String?,
    homepageAvatarUrl: json['homepage_avatar_url'] as String?,
    isActive: (json['is_active'] as int) == 1,
    websiteUrl: json['website_url'] as String?,
    instagramUrl: json['instagram_url'] as String?,
    xUrl: json['x_url'] as String?,
    lineUrl: json['line_url'] as String?,
    facebookUrl: json['facebook_url'] as String?,
  );

  bool get isAdmin => role == 'admin';

  Map<String, String> get socialLinks => {
    if (websiteUrl case final v?) 'website': v,
    if (instagramUrl case final v?) 'instagram': v,
    if (xUrl case final v?) 'x': v,
    if (lineUrl case final v?) 'line': v,
    if (facebookUrl case final v?) 'facebook': v,
  };
}
