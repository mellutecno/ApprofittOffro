import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/network/api_client.dart';
import '../../models/offer.dart';

class OffersController extends ChangeNotifier {
  OffersController(this.apiClient);

  static const int minRadiusKm = 5;
  static const int maxRadiusKm = 100;
  static const int defaultRadiusKm = 50;

  final ApiClient apiClient;
  static const Duration _positionCacheTtl = Duration(minutes: 3);
  static const Duration _liveLocationPingMinInterval = Duration(minutes: 2);
  static const double _liveLocationPingMinMoveMeters = 250;

  bool _isLoading = false;
  String? _errorMessage;
  String _selectedMealType = '';
  int _selectedRadiusKm = defaultRadiusKm;
  List<Offer> _offers = const [];
  int _hiddenOwnOffersCount = 0;
  Position? _cachedSearchPosition;
  DateTime? _cachedSearchPositionAt;
  Position? _lastLiveLocationPingPosition;
  DateTime? _lastLiveLocationPingAt;
  int _activeLoadToken = 0;
  Timer? _filtersDebounceTimer;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get selectedMealType => _selectedMealType;
  int get selectedRadiusKm => _selectedRadiusKm;
  List<Offer> get offers => _offers;
  int get hiddenOwnOffersCount => _hiddenOwnOffersCount;

  @override
  void dispose() {
    _filtersDebounceTimer?.cancel();
    super.dispose();
  }

  void initializeRadiusKm(int value) {
    _selectedRadiusKm = value.clamp(minRadiusKm, maxRadiusKm);
  }

  bool get _hasFreshCachedPosition {
    final cachedAt = _cachedSearchPositionAt;
    final cachedPosition = _cachedSearchPosition;
    if (cachedAt == null || cachedPosition == null) {
      return false;
    }
    return DateTime.now().difference(cachedAt) <= _positionCacheTtl;
  }

  void _cacheSearchPosition(Position position) {
    _cachedSearchPosition = position;
    _cachedSearchPositionAt = DateTime.now();
  }

  Future<Position?> _getCurrentPosition() async {
    if (_hasFreshCachedPosition) {
      return _cachedSearchPosition;
    }
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _cacheSearchPosition(lastKnown);
        }
        return lastKnown;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            _cacheSearchPosition(lastKnown);
          }
          return lastKnown;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _cacheSearchPosition(lastKnown);
        }
        return lastKnown;
      }
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _cacheSearchPosition(current);
      return current;
    } catch (_) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _cacheSearchPosition(lastKnown);
        }
        return lastKnown;
      } catch (_) {
        return _cachedSearchPosition;
      }
    }
  }

  bool _shouldPingLiveLocation(Position position) {
    final lastAt = _lastLiveLocationPingAt;
    final lastPosition = _lastLiveLocationPingPosition;
    if (lastAt == null || lastPosition == null) {
      return true;
    }
    final elapsed = DateTime.now().difference(lastAt);
    if (elapsed >= _liveLocationPingMinInterval) {
      return true;
    }
    final movedMeters = Geolocator.distanceBetween(
      lastPosition.latitude,
      lastPosition.longitude,
      position.latitude,
      position.longitude,
    );
    return movedMeters >= _liveLocationPingMinMoveMeters;
  }

  Future<void> _pingLiveLocation(Position? position) async {
    if (position == null || !_shouldPingLiveLocation(position)) {
      return;
    }
    try {
      await apiClient.sendLiveLocationPing(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _lastLiveLocationPingPosition = position;
      _lastLiveLocationPingAt = DateTime.now();
    } catch (_) {
      // Best effort: non bloccare la lista eventi.
    }
  }

  Future<void> loadOffers() async {
    final loadToken = ++_activeLoadToken;
    if (!_isLoading) {
      _isLoading = true;
      notifyListeners();
    }
    _errorMessage = null;

    try {
      final position = await _getCurrentPosition();
      unawaited(_pingLiveLocation(position));
      final fetchedOffers = await apiClient.fetchOffers(
        mealType: _selectedMealType,
        radiusKm: _selectedRadiusKm,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      if (loadToken != _activeLoadToken) {
        return;
      }
      _hiddenOwnOffersCount =
          fetchedOffers.where((offer) => offer.isOwn).length;
      _offers = fetchedOffers.where((offer) => !offer.isOwn).toList();
    } on ApiException catch (e) {
      if (loadToken != _activeLoadToken) {
        return;
      }
      _errorMessage = e.message;
      _hiddenOwnOffersCount = 0;
    } catch (_) {
      if (loadToken != _activeLoadToken) {
        return;
      }
      _errorMessage = 'Non riesco a caricare le offerte adesso.';
      _hiddenOwnOffersCount = 0;
    } finally {
      if (loadToken != _activeLoadToken) {
        return;
      }
      _isLoading = false;
      notifyListeners();
    }
  }

  void _scheduleOffersReload(
      {Duration delay = const Duration(milliseconds: 180)}) {
    _filtersDebounceTimer?.cancel();
    _filtersDebounceTimer = Timer(delay, () => unawaited(loadOffers()));
  }

  Future<String?> claimOffer(Offer offer) async {
    try {
      final message = await apiClient.claimOffer(offer.id);
      await loadOffers();
      return message;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Non riesco a completare l\'operazione adesso.';
    }
  }

  Future<String?> cancelClaim(Offer offer) async {
    if (offer.claimId <= 0) {
      return 'Non trovo la partecipazione da annullare.';
    }
    try {
      final message = await apiClient.cancelClaim(offer.claimId);
      await loadOffers();
      return message;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Non riesco ad annullare la partecipazione adesso.';
    }
  }

  Future<String?> hideRejectedOffer(Offer offer) async {
    if (offer.claimId <= 0) {
      return 'Non trovo il rifiuto da nascondere.';
    }
    try {
      final message = await apiClient.hideRejectedClaim(offer.claimId);
      await loadOffers();
      return message;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Non riesco a rimuovere questo evento dal feed adesso.';
    }
  }

  Future<void> toggleMealType(String value) async {
    _selectedMealType = _selectedMealType == value ? '' : value;
    _scheduleOffersReload();
  }

  Future<void> selectRadiusKm(int value) async {
    _selectedRadiusKm = value.clamp(minRadiusKm, maxRadiusKm);
    await loadOffers();
  }
}
