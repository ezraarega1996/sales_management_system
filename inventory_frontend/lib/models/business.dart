class Business {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final bool isActive;
  final String subscriptionStatus;
  final String subscriptionPlan;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionEndsAt;

  Business({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.isActive = true,
    this.subscriptionStatus = 'trial',
    this.subscriptionPlan = 'free',
    this.trialEndsAt,
    this.subscriptionEndsAt,
  });

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      phone: json['phone'],
      email: json['email'],
      isActive: json['isActive'] ?? true,
      subscriptionStatus: json['subscriptionStatus'] ?? 'trial',
      subscriptionPlan: json['subscriptionPlan'] ?? 'free',
      trialEndsAt: json['trialEndsAt'] != null ? DateTime.parse(json['trialEndsAt']) : null,
      subscriptionEndsAt: json['subscriptionEndsAt'] != null ? DateTime.parse(json['subscriptionEndsAt']) : null,
    );
  }

  @override
  String toString() => 'Business(id: $id, name: $name, plan: $subscriptionPlan, status: $subscriptionStatus)';
}
