import 'package:flutter/foundation.dart';

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

  Future<void> loadPeople() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _people = await apiClient.fetchPeople(
        ageRange: _selectedAgeRange,
        gender: _selectedGender,
        radiusKm: _selectedRadiusKm,
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
