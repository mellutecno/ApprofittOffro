class AppUser {
  const AppUser({
    required this.id,
    required this.nome,
    required this.email,
    required this.isAdmin,
    required this.photoFilename,
    required this.etaDisplay,
    required this.city,
    required this.isVerified,
    required this.preferredFoods,
    required this.intolerances,
  });

  final int id;
  final String nome;
  final String email;
  final bool isAdmin;
  final String photoFilename;
  final String etaDisplay;
  final String city;
  final bool isVerified;
  final String preferredFoods;
  final String intolerances;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      nome: (json['nome'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      isAdmin: json['is_admin'] == true,
      photoFilename: (json['foto'] ?? '').toString(),
      etaDisplay: (json['eta_display'] ?? json['eta'] ?? '').toString(),
      city: (json['citta'] ?? '').toString(),
      isVerified: json['verificato'] == true,
      preferredFoods: (json['cibi_preferiti'] ?? '').toString(),
      intolerances: (json['intolleranze'] ?? '').toString(),
    );
  }
}
