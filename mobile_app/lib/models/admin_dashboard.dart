class AdminDashboardStats {
  const AdminDashboardStats({
    required this.users,
    required this.admins,
    required this.futureOffers,
    required this.pastOffers,
  });

  final int users;
  final int admins;
  final int futureOffers;
  final int pastOffers;

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    return AdminDashboardStats(
      users: json['users'] as int? ?? 0,
      admins: json['admins'] as int? ?? 0,
      futureOffers: json['future_offers'] as int? ?? 0,
      pastOffers: json['past_offers'] as int? ?? 0,
    );
  }
}

class AdminUserSummary {
  const AdminUserSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.photoFilename,
    required this.ageDisplay,
    required this.city,
    required this.cityLabel,
    required this.bio,
    required this.isVerified,
    required this.isAdmin,
    required this.createdAt,
    required this.offersCount,
    required this.claimsCount,
    required this.reviewsCount,
    required this.ratingAverage,
    required this.ratingCount,
  });

  final int id;
  final String name;
  final String email;
  final String photoFilename;
  final String ageDisplay;
  final String city;
  final String cityLabel;
  final String bio;
  final bool isVerified;
  final bool isAdmin;
  final DateTime? createdAt;
  final int offersCount;
  final int claimsCount;
  final int reviewsCount;
  final double ratingAverage;
  final int ratingCount;

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) {
    return AdminUserSummary(
      id: json['id'] as int? ?? 0,
      name: (json['nome'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      photoFilename: (json['foto'] ?? '').toString(),
      ageDisplay: (json['eta_display'] ?? '').toString(),
      city: (json['citta'] ?? '').toString(),
      cityLabel: (json['city_label'] ?? '').toString(),
      bio: (json['bio'] ?? '').toString(),
      isVerified: json['verificato'] == true,
      isAdmin: json['is_admin'] == true,
      createdAt: _parseDate(json['created_at']),
      offersCount: json['offers_count'] as int? ?? 0,
      claimsCount: json['claims_count'] as int? ?? 0,
      reviewsCount: json['reviews_count'] as int? ?? 0,
      ratingAverage: (json['rating_average'] as num?)?.toDouble() ?? 0,
      ratingCount: json['rating_count'] as int? ?? 0,
    );
  }
}

class AdminOfferAuthorSummary {
  const AdminOfferAuthorSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.photoFilename,
  });

  final int id;
  final String name;
  final String email;
  final String photoFilename;

  factory AdminOfferAuthorSummary.fromJson(Map<String, dynamic> json) {
    return AdminOfferAuthorSummary(
      id: json['id'] as int? ?? 0,
      name: (json['nome'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      photoFilename: (json['foto'] ?? '').toString(),
    );
  }
}

class AdminOfferSummary {
  const AdminOfferSummary({
    required this.id,
    required this.mealType,
    required this.localeName,
    required this.address,
    required this.localePhone,
    required this.startsAt,
    required this.status,
    required this.description,
    required this.photoFilename,
    required this.totalSeats,
    required this.availableSeats,
    required this.participantsCount,
    required this.author,
  });

  final int id;
  final String mealType;
  final String localeName;
  final String address;
  final String localePhone;
  final DateTime? startsAt;
  final String status;
  final String description;
  final String photoFilename;
  final int totalSeats;
  final int availableSeats;
  final int participantsCount;
  final AdminOfferAuthorSummary author;

  factory AdminOfferSummary.fromJson(Map<String, dynamic> json) {
    return AdminOfferSummary(
      id: json['id'] as int? ?? 0,
      mealType: (json['tipo_pasto'] ?? '').toString(),
      localeName: (json['nome_locale'] ?? '').toString(),
      address: (json['indirizzo'] ?? '').toString(),
      localePhone: (json['telefono_locale'] ?? '').toString(),
      startsAt: _parseDate(json['data_ora']),
      status: (json['stato'] ?? '').toString(),
      description: (json['descrizione'] ?? '').toString(),
      photoFilename: (json['foto_locale'] ?? '').toString(),
      totalSeats: json['posti_totali'] as int? ?? 0,
      availableSeats: json['posti_disponibili'] as int? ?? 0,
      participantsCount: json['participants_count'] as int? ?? 0,
      author: AdminOfferAuthorSummary.fromJson(
        (json['autore'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
      ),
    );
  }
}

class AdminDashboardData {
  const AdminDashboardData({
    required this.stats,
    required this.users,
    required this.futureOffers,
    required this.pastOffers,
  });

  final AdminDashboardStats stats;
  final List<AdminUserSummary> users;
  final List<AdminOfferSummary> futureOffers;
  final List<AdminOfferSummary> pastOffers;

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    return AdminDashboardData(
      stats: AdminDashboardStats.fromJson(
        (json['stats'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
      ),
      users: (json['users'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(AdminUserSummary.fromJson)
          .toList(),
      futureOffers: (json['future_offers'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(AdminOfferSummary.fromJson)
          .toList(),
      pastOffers: (json['past_offers'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(AdminOfferSummary.fromJson)
          .toList(),
    );
  }
}

DateTime? _parseDate(Object? value) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}
