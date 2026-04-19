class Participant {
  const Participant({
    required this.id,
    required this.name,
    required this.photoFilename,
    required this.whatsAppLink,
    required this.chatEnabled,
  });

  final int id;
  final String name;
  final String photoFilename;
  final String whatsAppLink;
  final bool chatEnabled;

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'] as int,
      name: (json['nome'] ?? '').toString(),
      photoFilename: (json['foto'] ?? '').toString(),
      whatsAppLink: (json['whatsapp_link'] ?? '').toString(),
      chatEnabled: json['chat_enabled'] == true,
    );
  }
}

class Offer {
  const Offer({
    required this.id,
    required this.tipoPasto,
    required this.nomeLocale,
    required this.indirizzo,
    required this.cityLabel,
    required this.telefonoLocale,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.postiTotali,
    required this.postiDisponibili,
    required this.stato,
    required this.dataOra,
    required this.bookingClosed,
    required this.descrizione,
    required this.fotoLocale,
    required this.fotoLocaleGallery,
    required this.fotoLocaleCount,
    required this.autoreNome,
    required this.autoreId,
    required this.autoreFoto,
    required this.autoreGallery,
    required this.autoreEta,
    required this.autoreRatingAverage,
    required this.autoreRatingCount,
    required this.hostWhatsAppLink,
    required this.hostChatEnabled,
    required this.participants,
    required this.isOwn,
    required this.alreadyClaimed,
    required this.canClaim,
    required this.claimStatus,
    required this.claimId,
    required this.userHasReviewed,
    required this.reviewsReceivedCount,
  });

  final int id;
  final String tipoPasto;
  final String nomeLocale;
  final String indirizzo;
  final String cityLabel;
  final String telefonoLocale;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final int postiTotali;
  final int postiDisponibili;
  final String stato;
  final DateTime dataOra;
  final bool bookingClosed;
  final String descrizione;
  final String fotoLocale;
  final List<String> fotoLocaleGallery;
  final int fotoLocaleCount;
  final String autoreNome;
  final int autoreId;
  final String autoreFoto;
  final List<String> autoreGallery;
  final String autoreEta;
  final double autoreRatingAverage;
  final int autoreRatingCount;
  final String hostWhatsAppLink;
  final bool hostChatEnabled;
  final List<Participant> participants;
  final bool isOwn;
  final bool alreadyClaimed;
  final bool canClaim;
  final String claimStatus;
  final int claimId;
  final bool userHasReviewed;
  final int reviewsReceivedCount;

  factory Offer.fromJson(Map<String, dynamic> json) {
    final stato = (json['stato'] ?? '').toString();
    final dataOra = DateTime.parse(json['data_ora'] as String);
    final postiDisponibili = json['posti_disponibili'] as int? ?? 0;
    final bookingClosed = json['booking_closed'] == true;
    final isOwn = json['is_own'] == true;
    final alreadyClaimed = json['already_claimed'] == true;
    final now = DateTime.now();

    var claimStatus = (json['claim_status'] ?? '').toString();
    if (claimStatus.isEmpty) {
      if (alreadyClaimed) {
        claimStatus = 'claimed';
      } else if (stato != 'attiva' || postiDisponibili <= 0) {
        claimStatus = 'full';
      } else if (dataOra.toLocal().isBefore(now)) {
        claimStatus = 'started';
      } else if (bookingClosed) {
        claimStatus = 'booking_closed';
      } else {
        claimStatus = 'open';
      }
    }

    final canClaim = json.containsKey('can_claim')
        ? json['can_claim'] == true
        : (!isOwn && !alreadyClaimed && claimStatus == 'open');

    return Offer(
      id: json['id'] as int,
      tipoPasto: (json['tipo_pasto'] ?? '').toString(),
      nomeLocale: (json['nome_locale'] ?? '').toString(),
      indirizzo: (json['indirizzo'] ?? '').toString(),
      cityLabel: (json['city_label'] ?? '').toString(),
      telefonoLocale: (json['telefono_locale'] ?? '').toString(),
      latitude: (json['lat'] as num?)?.toDouble() ?? 0,
      longitude: (json['lon'] as num?)?.toDouble() ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      postiTotali: json['posti_totali'] as int? ?? 0,
      postiDisponibili: postiDisponibili,
      stato: stato,
      dataOra: dataOra,
      bookingClosed: bookingClosed,
      descrizione: (json['descrizione'] ?? '').toString(),
      fotoLocale: (json['foto_locale'] ?? '').toString(),
      fotoLocaleGallery: (json['foto_locale_gallery'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      fotoLocaleCount: json['foto_locale_count'] as int? ??
          ((json['foto_locale_gallery'] as List<dynamic>?)?.length ?? 0),
      autoreNome: (json['autore'] ?? '').toString(),
      autoreId: json['autore_id'] as int? ?? 0,
      autoreFoto: (json['autore_foto'] ?? '').toString(),
      autoreGallery: (json['autore_foto_gallery'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      autoreEta: (json['autore_eta'] ?? '').toString(),
      autoreRatingAverage:
          (json['autore_rating_average'] as num?)?.toDouble() ?? 0,
      autoreRatingCount: json['autore_rating_count'] as int? ?? 0,
      hostWhatsAppLink: (json['host_whatsapp_link'] ?? '').toString(),
      hostChatEnabled: json['host_chat_enabled'] == true,
      participants: (json['partecipanti'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(Participant.fromJson)
          .toList(),
      isOwn: isOwn,
      alreadyClaimed: alreadyClaimed,
      canClaim: canClaim,
      claimStatus: claimStatus,
      claimId: json['claim_id'] as int? ?? 0,
      userHasReviewed: json['user_has_reviewed'] == true,
      reviewsReceivedCount: json['reviews_received_count'] as int? ?? 0,
    );
  }
}
