import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../models/offer.dart';

class OffersController extends ChangeNotifier {
  OffersController(this.apiClient);

  static const int minRadiusKm = 5;
  static const int maxRadiusKm = 500;
  static const int defaultRadiusKm = 50;

  final ApiClient apiClient;

  bool _isLoading = false;
  String? _errorMessage;
  String _selectedMealType = '';
  int _selectedRadiusKm = defaultRadiusKm;
  List<Offer> _offers = const [];
  int _hiddenOwnOffersCount = 0;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get selectedMealType => _selectedMealType;
  int get selectedRadiusKm => _selectedRadiusKm;
  List<Offer> get offers => _offers;
  int get hiddenOwnOffersCount => _hiddenOwnOffersCount;

  void initializeRadiusKm(int value) {
    _selectedRadiusKm = value.clamp(minRadiusKm, maxRadiusKm);
  }

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

  Future<void> toggleMealType(String value) async {
    _selectedMealType = _selectedMealType == value ? '' : value;
    await loadOffers();
  }

  Future<void> selectRadiusKm(int value) async {
    _selectedRadiusKm = value.clamp(minRadiusKm, maxRadiusKm);
    await loadOffers();
  }
}
