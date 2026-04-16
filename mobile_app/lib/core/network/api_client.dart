import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/app_user.dart';
import '../../models/admin_dashboard.dart';
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

class ReviewHistoryBundle {
  const ReviewHistoryBundle({
    required this.received,
    required this.given,
  });

  final List<UserReview> received;
  final List<UserReview> given;
}

class ApiClient {
  ApiClient({required this.sessionStore});

  final SessionStore sessionStore;
  String? _cookieHeader;
  Future<void> Function()? onUnauthorized;
  bool _handlingUnauthorized = false;

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

  Future<String> requestPasswordReset({
    required String email,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/password/forgot',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ??
        'Se l\'account puo\' essere recuperato via password, ti abbiamo inviato un link.';
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
    final response =
        await _send(method: 'GET', path: '/api/auth/google/config');
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
      await clearLocalSession();
    }
  }

  Future<void> clearLocalSession() async {
    _cookieHeader = null;
    await sessionStore.clear();
  }

  Future<AppUser> fetchCurrentUser() async {
    final response = await _send(method: 'GET', path: '/api/user/me');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return AppUser.fromJson(payload['user'] as Map<String, dynamic>);
  }

  Future<void> registerPushToken({
    required String token,
    required String platform,
    String deviceLabel = '',
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/push/token',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'platform': platform,
        'device_label': deviceLabel,
      }),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
  }

  Future<void> unregisterPushToken(String token) async {
    final response = await _send(
      method: 'DELETE',
      path: '/api/push/token',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token}),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
  }

  Future<ReviewHistoryBundle> fetchMyReviewHistory() async {
    final response = await _send(method: 'GET', path: '/api/user/reviews');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return ReviewHistoryBundle(
      received: (payload['reviews_received'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(UserReview.fromJson)
          .toList(),
      given: (payload['reviews_given'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(UserReview.fromJson)
          .toList(),
    );
  }

  Future<AdminDashboardData> fetchAdminDashboard() async {
    final response = await _send(method: 'GET', path: '/api/admin/dashboard');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return AdminDashboardData.fromJson(payload);
  }

  Future<AdminEditableUser> fetchAdminUser(int userId) async {
    final response =
        await _send(method: 'GET', path: '/api/admin/users/$userId');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return AdminEditableUser.fromJson(
      payload['user'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<List<UserPreview>> fetchPeople({
    String ageRange = '',
    String gender = '',
    int? radiusKm,
    double? latitude,
    double? longitude,
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
    if (latitude != null && longitude != null) {
      query['lat'] = latitude.toString();
      query['lon'] = longitude.toString();
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
    double? latitude,
    double? longitude,
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
    if (latitude != null && longitude != null) {
      query['lat'] = latitude.toString();
      query['lon'] = longitude.toString();
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

  Future<List<Offer>> fetchMyProfileOffers({
    required bool claimed,
    bool archived = false,
  }) async {
    final scope = claimed ? 'claimed' : 'owned';
    final archivedValue = archived ? '&archived=1' : '';
    final response = await _send(
      method: 'GET',
      path: '/api/user/offers?scope=$scope$archivedValue',
    );
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

  Future<String> hideRejectedClaim(int claimId) async {
    final response = await _send(
      method: 'POST',
      path: '/api/claims/$claimId/hide-rejected',
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Evento rimosso dal feed.';
  }

  Future<String> cancelClaim(int claimId) async {
    final response =
        await _send(method: 'DELETE', path: '/api/claims/$claimId');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ??
        'Partecipazione annullata con successo.';
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
    bool forceShortNotice = false,
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
      'force_short_notice': forceShortNotice ? 'true' : 'false',
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
    bool forceShortNotice = false,
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
      'force_short_notice': forceShortNotice ? 'true' : 'false',
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

  Future<String> archiveOffer(int offerId) async {
    final response = await _send(
      method: 'POST',
      path: '/api/offers/$offerId/archive',
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Offerta archiviata.';
  }

  Future<String> deleteAdminUser(
    int userId, {
    required String motivazione,
  }) async {
    final response = await _send(
      method: 'DELETE',
      path: '/api/admin/users/$userId',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'motivazione': motivazione}),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ??
        'Account eliminato e utente avvisato via email.';
  }

  Future<String> updateAdminUser({
    required int userId,
    required String nome,
    required String email,
    required String eta,
    required int actionRadiusKm,
    required String gender,
    required bool verified,
    required String numeroTelefono,
    required String citta,
    required double? latitude,
    required double? longitude,
    required String preferredFoods,
    required String intolerances,
    required String bio,
    List<String> existingGalleryFilenames = const [],
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/admin/users/$userId',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'nome': nome,
        'email': email,
        'eta': eta,
        'sesso': gender,
        'verificato': verified,
        'raggio_azione': actionRadiusKm,
        'numero_telefono': numeroTelefono,
        'citta': citta,
        'latitudine': latitude,
        'longitudine': longitude,
        'cibi_preferiti': preferredFoods,
        'intolleranze': intolerances,
        'bio': bio,
        'existing_gallery_filenames': existingGalleryFilenames,
      }),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ?? 'Utente aggiornato con successo.';
  }

  Future<String> sendAdminMessage(
    int userId, {
    required String subject,
    required String message,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/admin/users/$userId/message',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'subject': subject,
        'message': message,
      }),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['message']?.toString() ??
        'Comunicazione inviata con successo.';
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
    String currentPassword = '',
    String newPassword = '',
    String confirmNewPassword = '',
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

    if (currentPassword.isNotEmpty ||
        newPassword.isNotEmpty ||
        confirmNewPassword.isNotEmpty) {
      request.fields.addAll({
        'current_password': currentPassword,
        'new_password': newPassword,
        'confirm_new_password': confirmNewPassword,
      });
    }

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

  Future<String> deleteMyAccount() async {
    final response = await _send(method: 'DELETE', path: '/api/user/account');
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    await clearLocalSession();
    return payload['message']?.toString() ??
        'Il tuo account è stato eliminato definitivamente.';
  }

  Future<bool> setChatEnabled(bool enabled) async {
    final response = await _send(
      method: 'POST',
      path: '/api/user/settings/chat',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'chat_enabled': enabled}),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
    return payload['chat_enabled'] == true;
  }

  Future<void> requestChatNotification(int offerId) async {
    final response = await _send(
      method: 'POST',
      path: '/api/chat/request-notification',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'offer_id': offerId}),
    );
    final payload = _decodeJson(response.body);
    _ensureSuccess(payload, response.statusCode);
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

    late final http.Response response;
    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(uri, headers: mergedHeaders);
        break;
      case 'POST':
        response = await http.post(uri, headers: mergedHeaders, body: body);
        break;
      case 'DELETE':
        final request = http.Request('DELETE', uri)
          ..headers.addAll(mergedHeaders);
        if (body != null) {
          request.body = body.toString();
        }
        final streamedResponse = await request.send();
        response = await http.Response.fromStream(streamedResponse);
        break;
      default:
        throw UnsupportedError('Metodo HTTP non gestito: $method');
    }

    if (response.statusCode == 401) {
      await _handleUnauthorizedResponse();
    }
    return response;
  }

  Future<http.Response> _sendMultipart(http.MultipartRequest request) async {
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 401) {
      await _handleUnauthorizedResponse();
    }
    return response;
  }

  Map<String, dynamic> _decodeJson(String body) {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw ApiException('Risposta server non valida.');
    } on FormatException {
      throw ApiException('Errore di comunicazione con il server.');
    }
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

  Future<void> _handleUnauthorizedResponse() async {
    if (_handlingUnauthorized) {
      return;
    }
    _handlingUnauthorized = true;
    try {
      await clearLocalSession();
      final handler = onUnauthorized;
      if (handler != null) {
        await handler();
      }
    } finally {
      _handlingUnauthorized = false;
    }
  }
}
