import 'favorite_place.dart';
import 'offer.dart';

class PremiumRadar {
  const PremiumRadar({
    required this.windowHours,
    required this.radiusKm,
    required this.locationSource,
    required this.favoritePlacesCount,
    required this.favoritePlaces,
    required this.lastMinuteCount,
    required this.lastMinuteOffers,
    required this.clubTitle,
    required this.clubStatus,
    required this.clubDescription,
  });

  final int windowHours;
  final double radiusKm;
  final String locationSource;
  final int favoritePlacesCount;
  final List<FavoritePlace> favoritePlaces;
  final int lastMinuteCount;
  final List<Offer> lastMinuteOffers;
  final String clubTitle;
  final String clubStatus;
  final String clubDescription;

  factory PremiumRadar.fromJson(Map<String, dynamic> json) {
    final club = json['club'] as Map<String, dynamic>? ?? {};
    return PremiumRadar(
      windowHours: json['window_hours'] as int? ?? 8,
      radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 0,
      locationSource: (json['location_source'] ?? '').toString(),
      favoritePlacesCount: json['favorite_places_count'] as int? ?? 0,
      favoritePlaces: (json['favorite_places'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(FavoritePlace.fromJson)
          .toList(),
      lastMinuteCount: json['last_minute_count'] as int? ?? 0,
      lastMinuteOffers: (json['last_minute_offers'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(Offer.fromJson)
          .toList(),
      clubTitle: (club['title'] ?? 'ApprofittOffro Club').toString(),
      clubStatus: (club['status'] ?? 'In arrivo').toString(),
      clubDescription: (club['description'] ?? '').toString(),
    );
  }
}
