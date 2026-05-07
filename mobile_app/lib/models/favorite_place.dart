class FavoritePlace {
  const FavoritePlace({
    required this.id,
    required this.nomeLocale,
    required this.indirizzo,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  final int id;
  final String nomeLocale;
  final String indirizzo;
  final double latitude;
  final double longitude;
  final DateTime? createdAt;

  factory FavoritePlace.fromJson(Map<String, dynamic> json) {
    final createdAtValue = (json['created_at'] ?? '').toString();
    return FavoritePlace(
      id: json['id'] as int? ?? 0,
      nomeLocale: (json['nome_locale'] ?? '').toString(),
      indirizzo: (json['indirizzo'] ?? '').toString(),
      latitude: (json['lat'] as num?)?.toDouble() ?? 0,
      longitude: (json['lon'] as num?)?.toDouble() ?? 0,
      createdAt:
          createdAtValue.isEmpty ? null : DateTime.tryParse(createdAtValue),
    );
  }
}
