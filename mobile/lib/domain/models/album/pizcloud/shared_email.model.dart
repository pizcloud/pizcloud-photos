class SharedEmailDto {
  final String email;
  final DateTime createdAt;

  const SharedEmailDto({required this.email, required this.createdAt});

  factory SharedEmailDto.fromJson(Map<String, dynamic> json) {
    return SharedEmailDto(
      email: (json['email'] ?? '') as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
