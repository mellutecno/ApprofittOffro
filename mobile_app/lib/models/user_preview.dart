class UserPreview {
  const UserPreview({
    required this.id,
    required this.nome,
    required this.photoFilename,
    required this.galleryFilenames,
    required this.etaDisplay,
    required this.city,
    required this.cityLabel,
    required this.bio,
    required this.preferredFoods,
    required this.intolerances,
    required this.isVerified,
    required this.followersCount,
    required this.followingCount,
    required this.ratingAverage,
    required this.ratingCount,
    required this.isFollowing,
    required this.isSelf,
  });

  final int id;
  final String nome;
  final String photoFilename;
  final List<String> galleryFilenames;
  final String etaDisplay;
  final String city;
  final String cityLabel;
  final String bio;
  final String preferredFoods;
  final String intolerances;
  final bool isVerified;
  final int followersCount;
  final int followingCount;
  final double ratingAverage;
  final int ratingCount;
  final bool isFollowing;
  final bool isSelf;

  UserPreview copyWith({
    bool? isFollowing,
    int? followersCount,
  }) {
    return UserPreview(
      id: id,
      nome: nome,
      photoFilename: photoFilename,
      galleryFilenames: galleryFilenames,
      etaDisplay: etaDisplay,
      city: city,
      cityLabel: cityLabel,
      bio: bio,
      preferredFoods: preferredFoods,
      intolerances: intolerances,
      isVerified: isVerified,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      isSelf: isSelf,
    );
  }

  factory UserPreview.fromJson(Map<String, dynamic> json) {
    return UserPreview(
      id: json['id'] as int,
      nome: (json['nome'] ?? '').toString(),
      photoFilename: (json['foto'] ?? '').toString(),
      galleryFilenames: (json['gallery_filenames'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      etaDisplay: (json['eta_display'] ?? json['eta'] ?? '').toString(),
      city: (json['citta'] ?? '').toString(),
      cityLabel: (json['city_label'] ?? json['citta'] ?? '').toString(),
      bio: (json['bio'] ?? '').toString(),
      preferredFoods: (json['cibi_preferiti'] ?? '').toString(),
      intolerances: (json['intolleranze'] ?? '').toString(),
      isVerified: json['verificato'] == true,
      followersCount: json['followers_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
      ratingAverage: (json['rating_average'] as num?)?.toDouble() ?? 0,
      ratingCount: json['rating_count'] as int? ?? 0,
      isFollowing: json['is_following'] == true,
      isSelf: json['is_self'] == true,
    );
  }
}
