import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../models/offer.dart';

const int defaultNearbyRadiusKm = 15;
const int expandedNearbyRadiusKm = 40;

class OffersController extends ChangeNotifier {
  OffersController(this.apiClient);

  final ApiClient apiClient;

  bool _isLoading = false;
  String? _errorMessage;
  String _selectedMealType = '';
  int? _selectedRadiusKm = defaultNearbyRadiusKm;
  List<Offer> _offers = const [];
  int _hiddenOwnOffersCount = 0;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get selectedMealType => _selectedMealType;
  int? get selectedRadiusKm => _selectedRadiusKm;
  List<Offer> get offers => _offers;
  int get hiddenOwnOffersCount => _hiddenOwnOffersCount;

  Future<void> loadOffers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fetchedOffers = await apiClient.fetchOffers(
        mealType: _selectedMealType,
        radiusKm: _selectedRadiusKm,
      );
      _hiddenOwnOffersCount =
          fetchedOffers.where((offer) => offer.isOwn).length;
      _offers = fetchedOffers.where((offer) => !offer.isOwn).toList();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _hiddenOwnOffersCount = 0;
    } catch (_) {
      _errorMessage = 'Non riesco a caricare le offerte adesso.';
      _hiddenOwnOffersCount = 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  Future<void> toggleMealType(String value) async {
    _selectedMealType = _selectedMealType == value ? '' : value;
    await loadOffers();
  }

  Future<void> setRadiusKm(int? value) async {
    if (_selectedRadiusKm == value) {
      return;
    }
    _selectedRadiusKm = value;
    await loadOffers();
  }
}
