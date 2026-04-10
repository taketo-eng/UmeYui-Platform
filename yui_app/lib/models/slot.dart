class SlotVendor {
  final String userId;
  final String? shopName;
  final String? avatarUrl;
  final bool isInitiator;

  const SlotVendor({
    required this.userId,
    this.shopName,
    this.avatarUrl,
    required this.isInitiator,
  });

  factory SlotVendor.fromJson(Map<String, dynamic> json) => SlotVendor(
    userId: json['user_id'] as String,
    shopName: json['shop_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    isInitiator: (json['is_initiator'] as int) == 1,
  );
}

class Slot {
  final String id;
  final String date;
  final String? name;
  final String? startTime;
  final String? endTime;
  final int? minVendors;
  final int? maxVendors;
  final String status;
  final int currentCount;
  final List<SlotVendor> vendors;
  final String? description;

  const Slot({
    required this.id,
    required this.date,
    this.name,
    this.startTime,
    this.endTime,
    this.minVendors,
    this.maxVendors,
    required this.status,
    required this.currentCount,
    this.vendors = const [],
    this.description,
  });

  factory Slot.fromJson(Map<String, dynamic> json) => Slot(
    id: json['id'] as String,
    date: json['date'] as String,
    name: json['name'] as String?,
    startTime: json['start_time'] as String?,
    endTime: json['end_time'] as String?,
    minVendors: json['min_vendors'] as int?,
    maxVendors: json['max_vendors'] as int?,
    status: json['status'] as String,
    currentCount: (json['current_count'] as num).toInt(),
    vendors:
        (json['vendors'] as List<dynamic>?)
            ?.map((v) => SlotVendor.fromJson(v as Map<String, dynamic>))
            .toList() ??
        [],
    description: json['description'] as String?,
  );

  bool get isOpen => status == 'open';
  bool get isRecruiting => status == 'recruiting';
  bool get isConfirmed => status == 'confirmed';
  bool get isCancelled => status == 'cancelled';
}
