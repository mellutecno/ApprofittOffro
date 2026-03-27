import 'user_preview.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.nome,
    required this.email,
    required this.isAdmin,
    required this.photoFilename,
    required this.galleryFilenames,
    required this.etaDisplay,
    required this.gender,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.bio,
    required this.phoneNumber,
    required this.isVerified,
    required this.preferredFoods,
    required this.intolerances,
    required this.followersCount,
    required this.followingCount,
    required this.ratingAverage,
    required this.ratingCount,
    required this.followers,
    required this.offersCount,
    required this.claimsCount,
  });

  final int id;
  final String nome;
  final String email;
  final bool isAdmin;
  final String photoFilename;
  final List<String> galleryFilenames;
  final String etaDisplay;
  final String gender;
  final String city;
  final double? latitude;
  final double? longitude;
  final String bio;
  final String phoneNumber;
  final bool isVerified;
  final String preferredFoods;
  final String intolerances;
  final int followersCount;
  final int followingCount;
  final double ratingAverage;
  final int ratingCount;
  final List<UserPreview> followers;
  final int offersCount;
  final int claimsCount;

  bool get hasAnyProfilePhoto =>
      photoFilename.trim().isNotEmpty ||
      galleryFilenames.any((filename) => filename.trim().isNotEmpty);

  bool get needsMandatoryProfileSetup =>
      !hasAnyProfilePhoto ||
      phoneNumber.trim().isEmpty ||
      city.trim().isEmpty ||
      bio.trim().isEmpty ||
      preferredFoods.trim().isEmpty;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    return AppUser(
      id: json['id'] as int,
      nome: (json['nome'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      isAdmin: json['is_admin'] == true,
      photoFilename: (json['foto'] ?? '').toString(),
      galleryFilenames: (json['gallery_filenames'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      etaDisplay: (json['eta_display'] ?? json['eta'] ?? '').toString(),
      gender: (json['sesso'] ?? 'non_dico').toString(),
      city: (json['citta'] ?? '').toString(),
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lon'] as num?)?.toDouble(),
      bio: (json['bio'] ?? '').toString(),
      phoneNumber: (json['numero_telefono'] ?? '').toString(),
      isVerified: json['verificato'] == true,
      preferredFoods: (json['cibi_preferiti'] ?? '').toString(),
      intolerances: (json['intolleranze'] ?? '').toString(),
      followersCount: json['followers_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
      ratingAverage: (json['rating_average'] as num?)?.toDouble() ?? 0,
      ratingCount: json['rating_count'] as int? ?? 0,
      followers: (json['followers'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(UserPreview.fromJson)
          .toList(),
      offersCount: stats['offerte_totali'] as int? ?? 0,
      claimsCount: stats['recuperi_effettuati'] as int? ?? 0,
    );
  }
}
