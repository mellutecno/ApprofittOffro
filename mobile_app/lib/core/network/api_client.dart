import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/app_user.dart';
import '../../models/offer.dart';
import '../../models/place_candidate.dart';
import '../../models/public_profile.dart';
import '../../models/user_preview.dart';
import '../config/app_config.dart';
import 'session_store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.sessionStore});

  final SessionStore sessionStore;
  String? _cookieHeader;

  String get baseUrl => AppConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');

  Future<void> initialize() async {
    _cookieHeader = await sessionStore.loadCookie();
  }

  String buildUploadUrl(String filename) {
    final encoded = Uri.encodeComponent(filename);
    return '$baseUrl/uploads/$encoded';
  }

  bool get hasSession => (_cookieHeader ?? '').isNotEmpty;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/login',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final payload = _decodeJson(response.body);
    _storeCookies(response);
    _ensureSuccess(payload, response.statusCode);
    return payload;
  }

  Future<Map<String, dynamic>> loginWithGoogle({
    required String idToken,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/auth/google',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    final payload = _decodeJson(response.body);
    _storeCookies(response);
    _ensureSuccess(payload, response.statusCode);
    return payload;
  }

  Future<Map<String, dynamic>> fetchGoogleAuthConfig() async {
    final response = await _send(method: 'GET', path: '/api/auth/google/config');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload;
  }

  Future<String> registerUser({
    required String nome,
    required String email,
    required String password,
    required String confermaPassword,
    required String numeroTelefono,
    required String eta,
    required String gender,
    required String latitude,
    required String longitude,
    required String citta,
    required List<String> photoPaths,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/register'),
    );

    request.fields.addAll({
      'nome': nome,
      'email': email,
      'password': password,
      'conferma_password': confermaPassword,
      'numero_telefono': numeroTelefono,
      'eta': eta,
      'sesso': gender,
      'latitudine': latitude,
      'longitudine': longitude,
      'citta': citta,
    });

    for (final photoPath in photoPaths) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto',
          photoPath,
          filename: File(photoPath).uri.pathSegments.last,
        ),
      );
    }

    final response = await _sendMultipart(request);
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ??
        'Registrazione completata con successo.';
  }

  Future<void> logout() async {
    try {
      await _send(method: 'POST', path: '/api/logout');
    } finally {
      _cookieHeader = null;
      await sessionStore.clear();
    }
  }

  Future<AppUser> fetchCurrentUser() async {
    final response = await _send(method: 'GET', path: '/api/user/me');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return AppUser.fromJson(payload['user'] as Map<String, dynamic>);
  }

  Future<List<UserPreview>> fetchPeople({
    String ageRange = '',
    String gender = '',
    int? radiusKm,
  }) async {
    final query = <String, String>{};
    if (ageRange.isNotEmpty) {
      query['age_range'] = ageRange;
    }
    if (gender.isNotEmpty) {
      query['gender'] = gender;
    }
    if (radiusKm != null) {
      query['radius'] = radiusKm.toString();
    }
    final path = query.isEmpty
        ? '/api/people'
        : '/api/people?${Uri(queryParameters: query).query}';
    final response = await _send(method: 'GET', path: path);
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return (payload['people'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(UserPreview.fromJson)
        .toList();
  }

  Future<PublicProfile> fetchPublicUser(int userId) async {
    final response = await _send(method: 'GET', path: '/api/users/$userId');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return PublicProfile.fromJson(payload);
  }

  Future<Map<String, dynamic>> followUser(int userId) async {
    final response =
        await _send(method: 'POST', path: '/api/users/$userId/follow');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload;
  }

  Future<Map<String, dynamic>> unfollowUser(int userId) async {
    final response =
        await _send(method: 'POST', path: '/api/users/$userId/unfollow');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload;
  }

  Future<List<Offer>> fetchOffers({
    String mealType = '',
    int? radiusKm,
    int? limit,
  }) async {
    final query = <String, String>{};
    if (mealType.isNotEmpty) {
      query['tipo'] = mealType;
    }
    if (radiusKm != null) {
      query['radius'] = radiusKm.toString();
    }
    if (limit != null && limit > 0) {
      query['limit'] = limit.toString();
    }
    final path = query.isEmpty
        ? '/api/offers'
        : '/api/offers?${Uri(queryParameters: query).query}';
    final response = await _send(method: 'GET', path: path);
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return (payload['offers'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(Offer.fromJson)
        .toList();
  }

  Future<List<PlaceCandidate>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    int radiusMeters = 7000,
    int maxResults = 36,
  }) async {
    final path = '/api/places/nearby?${Uri(queryParameters: {
          'lat': latitude.toString(),
          'lon': longitude.toString(),
          'radius': radiusMeters.toString(),
          'max_results': maxResults.toString(),
        }).query}';
    final response = await _send(method: 'GET', path: path);
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return (payload['places'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(PlaceCandidate.fromJson)
        .toList();
  }

  Future<PlaceCandidate> fetchPlaceDetails(String placeId) async {
    final encodedId = Uri.encodeComponent(placeId);
    final response = await _send(method: 'GET', path: '/api/places/$encodedId');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return PlaceCandidate.fromJson(
      (payload['place'] as Map<String, dynamic>? ?? <String, dynamic>{}),
    );
  }

  Future<String> claimOffer(int offerId) async {
    final response =
        await _send(method: 'POST', path: '/api/offers/$offerId/claim');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Hai approfittato dell\'offerta.';
  }

  Future<String> acceptClaimRequest(int claimId) async {
    final response =
        await _send(method: 'POST', path: '/api/claims/$claimId/accept');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Richiesta accettata.';
  }

  Future<String> rejectClaimRequest(int claimId) async {
    final response =
        await _send(method: 'POST', path: '/api/claims/$claimId/reject');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Richiesta rifiutata.';
  }

  Future<String> createOffer({
    required String mealType,
    required String localeName,
    required String address,
    String localePhone = '',
    required String latitude,
    required String longitude,
    required int totalSeats,
    required DateTime dateTime,
    required String description,
    String? photoPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/offers'),
    );
    if ((_cookieHeader ?? '').isNotEmpty) {
      request.headers['Cookie'] = _cookieHeader!;
    }

    request.fields.addAll({
      'tipo_pasto': mealType,
      'nome_locale': localeName,
      'indirizzo': address,
      'telefono_locale': localePhone,
      'latitudine': latitude,
      'longitudine': longitude,
      'posti_totali': totalSeats.toString(),
      'data_ora': dateTime.toIso8601String(),
      'descrizione': description,
    });

    if (photoPath != null && photoPath.isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto_locale',
          photoPath,
          filename: File(photoPath).uri.pathSegments.last,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Offerta creata con successo.';
  }

  Future<String> updateOffer({
    required int offerId,
    required String mealType,
    required String localeName,
    required String address,
    String localePhone = '',
    required String latitude,
    required String longitude,
    required int totalSeats,
    required DateTime dateTime,
    required String description,
    String? photoPath,
  }) async {
    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/offers/$offerId'),
    );
    if ((_cookieHeader ?? '').isNotEmpty) {
      request.headers['Cookie'] = _cookieHeader!;
    }

    request.fields.addAll({
      'tipo_pasto': mealType,
      'nome_locale': localeName,
      'indirizzo': address,
      'telefono_locale': localePhone,
      'latitudine': latitude,
      'longitudine': longitude,
      'posti_totali': totalSeats.toString(),
      'data_ora': dateTime.toIso8601String(),
      'descrizione': description,
    });

    if (photoPath != null && photoPath.isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto_locale',
          photoPath,
          filename: File(photoPath).uri.pathSegments.last,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Offerta aggiornata con successo.';
  }

  Future<String> deleteOffer(
    int offerId, {
    String motivazione = 'Eliminata dall\'autore dall\'app mobile.',
  }) async {
    final response = await _send(
      method: 'DELETE',
      path: '/api/offers/$offerId',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'motivazione': motivazione}),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Offerta eliminata con successo.';
  }

  Future<String> updateProfile({
    required String nome,
    required String email,
    required String eta,
    required String gender,
    required int actionRadiusKm,
    required String numeroTelefono,
    required String citta,
    required String latitude,
    required String longitude,
    required String preferredFoods,
    required String intolerances,
    required String bio,
    List<String> existingGalleryFilenames = const [],
    List<String> photoPaths = const [],
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/user/update'),
    );
    if ((_cookieHeader ?? '').isNotEmpty) {
      request.headers['Cookie'] = _cookieHeader!;
    }

    request.fields.addAll({
      'nome': nome,
      'email': email,
      'eta': eta,
      'sesso': gender,
      'raggio_azione': actionRadiusKm.toString(),
      'numero_telefono': numeroTelefono,
      'citta': citta,
      'latitudine': latitude,
      'longitudine': longitude,
      'cibi_preferiti': preferredFoods,
      'intolleranze': intolerances,
      'bio': bio,
      'existing_gallery_filenames': jsonEncode(existingGalleryFilenames),
    });

    for (final photoPath in photoPaths) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto',
          photoPath,
          filename: File(photoPath).uri.pathSegments.last,
        ),
      );
    }

    final response = await _sendMultipart(request);
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    _storeCookies(response);
    return payload['message']?.toString() ?? 'Profilo aggiornato con successo.';
  }

  Future<String> submitReview({
    required int offerId,
    required int reviewedId,
    required int rating,
    String comment = '',
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/reviews',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'offer_id': offerId,
        'reviewed_id': reviewedId,
        'rating': rating,
        'commento': comment,
      }),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Recensione salvata.';
  }

  Future<http.Response> _send({
    required String method,
    required String path,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final mergedHeaders = <String, String>{...?headers};
    if ((_cookieHeader ?? '').isNotEmpty) {
      mergedHeaders['Cookie'] = _cookieHeader!;
    }

    switch (method.toUpperCase()) {
      case 'GET':
        return http.get(uri, headers: mergedHeaders);
      case 'POST':
        return http.post(uri, headers: mergedHeaders, body: body);
      case 'DELETE':
        final request = http.Request('DELETE', uri)
          ..headers.addAll(mergedHeaders);
        if (body != null) {
          request.body = body.toString();
        }
        final streamedResponse = await request.send();
        return http.Response.fromStream(streamedResponse);
      default:
        throw UnsupportedError('Metodo HTTP non gestito: $method');
    }
  }

  Future<http.Response> _sendMultipart(http.MultipartRequest request) async {
    final streamedResponse = await request.send();
    return http.Response.fromStream(streamedResponse);
  }

  Map<String, dynamic> _decodeJson(String body) {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw ApiException('Risposta server non valida.');
  }

  void _ensureSuccess(Map<String, dynamic> payload, int statusCode) {
    if (payload['success'] == true) {
      return;
    }

    final errors = payload['errors'];
    if (errors is List && errors.isNotEmpty) {
      throw ApiException(errors.join('\n'), statusCode: statusCode);
    }

    final error = payload['error'];
    if (error is String && error.isNotEmpty) {
      throw ApiException(error, statusCode: statusCode);
    }

    throw ApiException('Operazione non riuscita.', statusCode: statusCode);
  }

  void _storeCookies(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) {
      return;
    }

    final cookiePairs = <String, String>{};
    for (final match in RegExp(r'([A-Za-z0-9_]+=[^;,\s]+)').allMatches(raw)) {
      final pair = match.group(0);
      if (pair == null) {
        continue;
      }
      final lower = pair.toLowerCase();
      if (lower.startsWith('path=') ||
          lower.startsWith('expires=') ||
          lower.startsWith('max-age=') ||
          lower.startsWith('domain=') ||
          lower.startsWith('samesite=')) {
        continue;
      }
      final parts = pair.split('=');
      if (parts.length < 2) {
        continue;
      }
      cookiePairs[parts.first] = parts.sublist(1).join('=');
    }

    if (cookiePairs.isEmpty) {
      return;
    }

    _cookieHeader =
        cookiePairs.entries.map((e) => '${e.key}=${e.value}').join('; ');
    sessionStore.saveCookie(_cookieHeader!);
  }
}
