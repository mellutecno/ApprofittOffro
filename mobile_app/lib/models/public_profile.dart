import 'user_preview.dart';

class UserReview {
  const UserReview({
    required this.id,
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.reviewer,
  });

  final int id;
  final int rating;
  final String comment;
  final DateTime? createdAt;
  final UserPreview? reviewer;

  factory UserReview.fromJson(Map<String, dynamic> json) {
    return UserReview(
      id: json['id'] as int? ?? 0,
      rating: json['rating'] as int? ?? 0,
      comment: (json['commento'] ?? '').toString(),
      createdAt: json['created_at'] != null && (json['created_at'] as String).isNotEmpty
          ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
          : null,
      reviewer: json['reviewer'] is Map<String, dynamic>
          ? UserPreview.fromJson(json['reviewer'] as Map<String, dynamic>)
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
  });

  final UserPreview user;
  final int offersCount;
  final int claimsCount;
  final List<UserReview> reviews;

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
    );
  }
}
