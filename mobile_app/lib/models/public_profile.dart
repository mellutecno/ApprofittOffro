import 'user_preview.dart';

class ReviewedOfferSummary {
  const ReviewedOfferSummary({
    required this.id,
    required this.mealType,
    required this.localeName,
    required this.address,
    required this.dateTime,
  });

  final int id;
  final String mealType;
  final String localeName;
  final String address;
  final DateTime? dateTime;

  factory ReviewedOfferSummary.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['data_ora'] ?? '').toString().trim();
    return ReviewedOfferSummary(
      id: json['id'] as int? ?? 0,
      mealType: (json['tipo_pasto'] ?? '').toString(),
      localeName: (json['nome_locale'] ?? '').toString(),
      address: (json['indirizzo'] ?? '').toString(),
      dateTime: rawDate.isEmpty ? null : DateTime.tryParse(rawDate)?.toLocal(),
    );
  }
}

class UserReview {
  const UserReview({
    required this.id,
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.editableUntil,
    required this.viewerCanEdit,
    required this.offer,
    required this.reviewer,
    required this.reviewed,
  });

  final int id;
  final int rating;
  final String comment;
  final DateTime? createdAt;
  final DateTime? editableUntil;
  final bool viewerCanEdit;
  final ReviewedOfferSummary? offer;
  final UserPreview? reviewer;
  final UserPreview? reviewed;

  factory UserReview.fromJson(Map<String, dynamic> json) {
    final editableUntilRaw = (json['editable_until'] ?? '').toString().trim();
    return UserReview(
      id: json['id'] as int? ?? 0,
      rating: json['rating'] as int? ?? 0,
      comment: (json['commento'] ?? '').toString(),
      createdAt: json['created_at'] != null &&
              (json['created_at'] as String).isNotEmpty
          ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
          : null,
      editableUntil: editableUntilRaw.isEmpty
          ? null
          : DateTime.tryParse(editableUntilRaw)?.toLocal(),
      viewerCanEdit: json['viewer_can_edit'] == true,
      offer: json['offer'] is Map<String, dynamic>
          ? ReviewedOfferSummary.fromJson(json['offer'] as Map<String, dynamic>)
          : null,
      reviewer: json['reviewer'] is Map<String, dynamic>
          ? UserPreview.fromJson(json['reviewer'] as Map<String, dynamic>)
          : null,
      reviewed: json['reviewed'] is Map<String, dynamic>
          ? UserPreview.fromJson(json['reviewed'] as Map<String, dynamic>)
          : null,
    );
  }
}

class PublicProfile {
  const PublicProfile({
    required this.user,
    required this.offersCount,
    required this.claimsCount,
    required this.reviews,
    required this.followers,
  });

  final UserPreview user;
  final int offersCount;
  final int claimsCount;
  final List<UserReview> reviews;
  final List<UserPreview> followers;

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    return PublicProfile(
      user: UserPreview.fromJson(json['user'] as Map<String, dynamic>),
      offersCount: stats['offerte_totali'] as int? ?? 0,
      claimsCount: stats['recuperi_effettuati'] as int? ?? 0,
      reviews: (json['reviews'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(UserReview.fromJson)
          .toList(),
      followers: (json['followers'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(UserPreview.fromJson)
          .toList(),
    );
  }
}
