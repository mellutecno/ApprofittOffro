import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/network/api_client.dart';
import '../../models/user_preview.dart';

class CommunityController extends ChangeNotifier {
  CommunityController(this.apiClient);

  static const int minRadiusKm = 5;
  static const int maxRadiusKm = 1500;
  static const int defaultRadiusKm = 50;

  final ApiClient apiClient;
  static const Duration _positionCacheTtl = Duration(minutes: 3);
  static const Duration _liveLocationPingMinInterval = Duration(minutes: 2);
  static const double _liveLocationPingMinMoveMeters = 250;

  bool _isLoading = false;
  String? _errorMessage;
  String _selectedAgeRange = '';
  String _selectedGender = '';
  int _selectedRadiusKm = defaultRadiusKm;
  List<UserPreview> _people = const [];
  Position? _cachedSearchPosition;
  DateTime? _cachedSearchPositionAt;
  Position? _lastLiveLocationPingPosition;
  DateTime? _lastLiveLocationPingAt;
  bool _isUsingLiveGpsForSearch = false;
  int _activeLoadToken = 0;
  Timer? _filtersDebounceTimer;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get selectedAgeRange => _selectedAgeRange;
  String get selectedGender => _selectedGender;
  int get selectedRadiusKm => _selectedRadiusKm;
  List<UserPreview> get people => _people;
  bool get isUsingLiveGpsForSearch => _isUsingLiveGpsForSearch;

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

  Future<Position?> _getLiveSearchPosition() async {
    if (_hasFreshCachedPosition) {
      _isUsingLiveGpsForSearch = true;
      return _cachedSearchPosition;
    }
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _cacheSearchPosition(lastKnown);
          _isUsingLiveGpsForSearch = true;
        } else {
          _isUsingLiveGpsForSearch = false;
        }
        return lastKnown;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _cacheSearchPosition(lastKnown);
          _isUsingLiveGpsForSearch = true;
        } else {
          _isUsingLiveGpsForSearch = false;
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
      _isUsingLiveGpsForSearch = true;
      return current;
    } catch (_) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _cacheSearchPosition(lastKnown);
          _isUsingLiveGpsForSearch = true;
        } else {
          _isUsingLiveGpsForSearch = false;
        }
        return lastKnown;
      } catch (_) {
        _isUsingLiveGpsForSearch = false;
        return null;
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
      // Best effort: non bloccare il caricamento community.
    }
  }

  Future<void> loadPeople() async {
    final loadToken = ++_activeLoadToken;
    if (!_isLoading) {
      _isLoading = true;
      notifyListeners();
    }
    _errorMessage = null;

    try {
      final livePosition = await _getLiveSearchPosition();
      unawaited(_pingLiveLocation(livePosition));
      final people = await apiClient.fetchPeople(
        ageRange: _selectedAgeRange,
        gender: _selectedGender,
        radiusKm: _selectedRadiusKm,
        latitude: livePosition?.latitude,
        longitude: livePosition?.longitude,
      );
      if (loadToken != _activeLoadToken) {
        return;
      }
      _people = people;
    } on ApiException catch (e) {
      if (loadToken != _activeLoadToken) {
        return;
      }
      _errorMessage = e.message;
    } catch (_) {
      if (loadToken != _activeLoadToken) {
        return;
      }
      _errorMessage = 'Non riesco a caricare la community adesso.';
    } finally {
      if (loadToken != _activeLoadToken) {
        return;
      }
      _isLoading = false;
      notifyListeners();
    }
  }

  void _schedulePeopleReload(
      {Duration delay = const Duration(milliseconds: 180)}) {
    _filtersDebounceTimer?.cancel();
    _filtersDebounceTimer = Timer(delay, () => unawaited(loadPeople()));
  }

  Future<void> selectAgeRange(String value) async {
    _selectedAgeRange = value;
    _schedulePeopleReload();
  }

  Future<void> selectGender(String value) async {
    _selectedGender = value;
    _schedulePeopleReload();
  }

  Future<void> selectRadiusKm(int value) async {
    _selectedRadiusKm = value.clamp(minRadiusKm, maxRadiusKm);
    _schedulePeopleReload();
  }

  Future<String?> toggleFollow(UserPreview user) async {
    try {
      final payload = user.isFollowing
          ? await apiClient.unfollowUser(user.id)
          : await apiClient.followUser(user.id);
      final isFollowing = payload['is_following'] == true;
      final followersCount =
          payload['followers_count'] as int? ?? user.followersCount;
      _people = _people.map((person) {
        if (person.id != user.id) {
          return person;
        }
        return person.copyWith(
          isFollowing: isFollowing,
          followersCount: followersCount,
        );
      }).toList();
      notifyListeners();
      return payload['message']?.toString();
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Non riesco a completare l\'operazione adesso.';
    }
  }
}
