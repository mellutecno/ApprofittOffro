import 'offer.dart';

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
    required this.gender,
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
  final String gender;
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
      gender: (json['sesso'] ?? 'non_dico').toString(),
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

class AdminEditableUser {
  const AdminEditableUser({
    required this.id,
    required this.name,
    required this.email,
    required this.photoFilename,
    required this.galleryFilenames,
    required this.age,
    required this.actionRadiusKm,
    required this.gender,
    required this.phoneNumber,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.preferredFoods,
    required this.intolerances,
    required this.bio,
    required this.isVerified,
    required this.isAdmin,
  });

  final int id;
  final String name;
  final String email;
  final String photoFilename;
  final List<String> galleryFilenames;
  final String age;
  final int actionRadiusKm;
  final String gender;
  final String phoneNumber;
  final String city;
  final double? latitude;
  final double? longitude;
  final String preferredFoods;
  final String intolerances;
  final String bio;
  final bool isVerified;
  final bool isAdmin;

  factory AdminEditableUser.fromJson(Map<String, dynamic> json) {
    return AdminEditableUser(
      id: json['id'] as int? ?? 0,
      name: (json['nome'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      photoFilename: (json['foto'] ?? '').toString(),
      galleryFilenames: (json['gallery_filenames'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      age: (json['eta'] ?? '').toString(),
      actionRadiusKm: json['raggio_azione'] as int? ?? 15,
      gender: (json['sesso'] ?? 'non_dico').toString(),
      phoneNumber: (json['numero_telefono'] ?? '').toString(),
      city: (json['citta'] ?? '').toString(),
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lon'] as num?)?.toDouble(),
      preferredFoods: (json['cibi_preferiti'] ?? '').toString(),
      intolerances: (json['intolleranze'] ?? '').toString(),
      bio: (json['bio'] ?? '').toString(),
      isVerified: json['verificato'] == true,
      isAdmin: json['is_admin'] == true,
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
    required this.latitude,
    required this.longitude,
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
  final double latitude;
  final double longitude;
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
      latitude: (json['lat'] as num?)?.toDouble() ?? 0,
      longitude: (json['lon'] as num?)?.toDouble() ?? 0,
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

  Offer toEditableOffer() {
    return Offer(
      id: id,
      tipoPasto: mealType,
      nomeLocale: localeName,
      indirizzo: address,
      telefonoLocale: localePhone,
      latitude: latitude,
      longitude: longitude,
      distanceKm: 0,
      postiTotali: totalSeats,
      postiDisponibili: availableSeats,
      stato: status,
      dataOra: startsAt ?? DateTime.now().add(const Duration(hours: 1)),
      bookingClosed: false,
      descrizione: description,
      fotoLocale: photoFilename,
      autoreNome: author.name,
      autoreId: author.id,
      autoreFoto: author.photoFilename,
      autoreGallery: const <String>[],
      autoreEta: '',
      autoreRatingAverage: 0,
      autoreRatingCount: 0,
      hostWhatsAppLink: '',
      participants: const <Participant>[],
      isOwn: true,
      alreadyClaimed: false,
      canClaim: false,
      claimStatus: 'open',
      claimId: 0,
      userHasReviewed: false,
      reviewsReceivedCount: 0,
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
