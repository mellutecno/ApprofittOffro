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

  bool _isLoading = false;
  String? _errorMessage;
  String _selectedAgeRange = '';
  String _selectedGender = '';
  int _selectedRadiusKm = defaultRadiusKm;
  List<UserPreview> _people = const [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get selectedAgeRange => _selectedAgeRange;
  String get selectedGender => _selectedGender;
  int get selectedRadiusKm => _selectedRadiusKm;
  List<UserPreview> get people => _people;

  void initializeRadiusKm(int value) {
    _selectedRadiusKm = value.clamp(minRadiusKm, maxRadiusKm);
  }

  Future<Position?> _getLiveSearchPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return await Geolocator.getLastKnownPosition();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return await Geolocator.getLastKnownPosition();
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> loadPeople() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final livePosition = await _getLiveSearchPosition();
      _people = await apiClient.fetchPeople(
        ageRange: _selectedAgeRange,
        gender: _selectedGender,
        radiusKm: _selectedRadiusKm,
        latitude: livePosition?.latitude,
        longitude: livePosition?.longitude,
      );
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Non riesco a caricare la community adesso.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectAgeRange(String value) async {
    _selectedAgeRange = value;
    await loadPeople();
  }

  Future<void> selectGender(String value) async {
    _selectedGender = value;
    await loadPeople();
  }

  Future<void> selectRadiusKm(int value) async {
    _selectedRadiusKm = value.clamp(minRadiusKm, maxRadiusKm);
    await loadPeople();
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
