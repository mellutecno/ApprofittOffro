class PlaceCandidate {
  const PlaceCandidate({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.primaryType,
    this.phoneNumber = '',
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String primaryType;
  final String phoneNumber;

  factory PlaceCandidate.fromJson(Map<String, dynamic> json) {
    return PlaceCandidate(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      primaryType: (json['primary_type'] ?? '').toString(),
      phoneNumber: (json['phone_number'] ?? '').toString(),
    );
  }
}
