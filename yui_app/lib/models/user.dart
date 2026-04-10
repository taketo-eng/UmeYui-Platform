class User {
  final String id;
  final String email;
  final String role;
  final String? shopName;
  final String? bio;
  final String? avatarUrl;
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
    this.avatarUrl,
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
    avatarUrl: json['avatar_url'] as String?,
    isActive: (json['is_active'] as int) == 1,
    websiteUrl: json['website_url'] as String?,
    instagramUrl: json['instagram_url'] as String?,
    xUrl: json['x_url'] as String?,
    lineUrl: json['line_url'] as String?,
    facebookUrl: json['facebook_url'] as String?,
  );

  bool get isAdmin => role == 'admin';

  Map<String, String> get socialLinks => {
    if (websiteUrl != null) 'website': websiteUrl!,
    if (instagramUrl != null) 'instagram': instagramUrl!,
    if (xUrl != null) 'x': xUrl!,
    if (lineUrl != null) 'line': lineUrl!,
    if (facebookUrl != null) 'facebook': facebookUrl!,
  };
}
