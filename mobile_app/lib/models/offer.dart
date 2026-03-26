class Participant {
  const Participant({
    required this.id,
    required this.name,
    required this.photoFilename,
    required this.whatsAppLink,
  });

  final int id;
  final String name;
  final String photoFilename;
  final String whatsAppLink;

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'] as int,
      name: (json['nome'] ?? '').toString(),
      photoFilename: (json['foto'] ?? '').toString(),
      whatsAppLink: (json['whatsapp_link'] ?? '').toString(),
    );
  }
}

class Offer {
  const Offer({
    required this.id,
    required this.tipoPasto,
    required this.nomeLocale,
    required this.indirizzo,
    required this.distanceKm,
    required this.postiTotali,
    required this.postiDisponibili,
    required this.stato,
    required this.dataOra,
    required this.bookingClosed,
    required this.descrizione,
    required this.fotoLocale,
    required this.autoreNome,
    required this.autoreId,
    required this.autoreFoto,
    required this.autoreGallery,
    required this.autoreEta,
    required this.autoreRatingAverage,
    required this.autoreRatingCount,
    required this.hostWhatsAppLink,
    required this.participants,
    required this.isOwn,
    required this.alreadyClaimed,
  });

  final int id;
  final String tipoPasto;
  final String nomeLocale;
  final String indirizzo;
  final double distanceKm;
  final int postiTotali;
  final int postiDisponibili;
  final String stato;
  final DateTime dataOra;
  final bool bookingClosed;
  final String descrizione;
  final String fotoLocale;
  final String autoreNome;
  final int autoreId;
  final String autoreFoto;
  final List<String> autoreGallery;
  final String autoreEta;
  final double autoreRatingAverage;
  final int autoreRatingCount;
  final String hostWhatsAppLink;
  final List<Participant> participants;
  final bool isOwn;
  final bool alreadyClaimed;

  factory Offer.fromJson(Map<String, dynamic> json) {
    return Offer(
      id: json['id'] as int,
      tipoPasto: (json['tipo_pasto'] ?? '').toString(),
      nomeLocale: (json['nome_locale'] ?? '').toString(),
      indirizzo: (json['indirizzo'] ?? '').toString(),
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      postiTotali: json['posti_totali'] as int? ?? 0,
      postiDisponibili: json['posti_disponibili'] as int? ?? 0,
      stato: (json['stato'] ?? '').toString(),
      dataOra: DateTime.parse(json['data_ora'] as String),
      bookingClosed: json['booking_closed'] == true,
      descrizione: (json['descrizione'] ?? '').toString(),
      fotoLocale: (json['foto_locale'] ?? '').toString(),
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
      participants: (json['partecipanti'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(Participant.fromJson)
          .toList(),
      isOwn: json['is_own'] == true,
      alreadyClaimed: json['already_claimed'] == true,
    );
  }
}
