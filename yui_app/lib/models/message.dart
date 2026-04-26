class Message {
  final String id;
  final String body;
  final String userId;
  final String? shopName;
  final String? avatarUrl;
  final String createdAt;
  final String? imageUrl;

  const Message({
    required this.id,
    required this.body,
    required this.userId,
    this.shopName,
    this.avatarUrl,
    required this.createdAt,
    this.imageUrl,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    body: json['body'] as String? ?? '',
    userId: json['user_id'] as String,
    shopName: json['shop_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    createdAt: json['created_at'] as String,
    imageUrl: json['image_url'] as String?,
  );
}
