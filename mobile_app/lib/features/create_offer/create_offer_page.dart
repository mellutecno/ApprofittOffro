import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/offer.dart';
import '../../models/place_candidate.dart';
import '../auth/auth_controller.dart';

class CreateOfferPage extends StatefulWidget {
  const CreateOfferPage({
    super.key,
    required this.authController,
    this.onOfferCreated,
    this.initialOffer,
  });

  final AuthController authController;
  final Future<void> Function()? onOfferCreated;
  final Offer? initialOffer;

  @override
  State<CreateOfferPage> createState() => _CreateOfferPageState();
}

class _CreateOfferPageState extends State<CreateOfferPage> {
  static const LatLng _fallbackMapTarget = LatLng(45.070339, 7.686864);

  final _formKey = GlobalKey<FormState>();
  final _localeController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  final Completer<GoogleMapController> _mapControllerCompleter = Completer();

  String? _mealType;
  int _totalSeats = 2;
  DateTime? _selectedDateTime;
  XFile? _pickedImage;
  bool _submitting = false;
  bool _isLocating = false;
  bool _initialLocationRequested = false;
  bool _initialMapReady = !AppConfig.googleMapsEnabled;
  bool _mapExpanded = false;
  bool _loadingNearbyPlaces = false;
  bool _nearbyPlacesLoaded = false;
  GoogleMapController? _mapController;
  LatLng _currentMapCenter = _fallbackMapTarget;
  double? _selectedLatitude;
  double? _selectedLongitude;
  String? _selectedPlaceId;
  String _selectedPrimaryType = '';
  List<PlaceCandidate> _nearbyPlaces = const [];
  Set<Marker> _nearbyMarkers = const <Marker>{};
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  @override
  void initState() {
    super.initState();
    final initialOffer = widget.initialOffer;
    if (initialOffer != null) {
      _prefillFromOffer(initialOffer);
      if (AppConfig.googleMapsEnabled) {
        _initialMapReady = true;
        _initialLocationRequested = true;
      }
    } else if (AppConfig.googleMapsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_bootstrapCurrentLocation());
      });
    }
  }

  @override
  void dispose() {
    _localeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initialOffer != null;
    final selectedDateText = _selectedDateTime == null
        ? 'Scegli data e ora'
        : DateFormat('EEEE d MMMM - HH:mm', 'it_IT')
            .format(_selectedDateTime!);

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(height: 24, alignment: Alignment.center),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Text(
              isEditing ? 'Modifica la tua offerta' : 'Pubblica un invito vero',
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isEditing
                  ? 'Aggiorna momento, locale e dettagli del tuo invito senza perdere lo stile del tavolo che hai gia creato.'
                  : 'Prima scegli il momento, poi apri la mappa solo quando ti serve e completa l’invito in pochi passaggi.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppTheme.brown.withValues(alpha: 0.74),
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _SectionCard(
              title: null,
              subtitle:
                  'Decidi il tipo di pasto, data e ora complete e quanti posti vuoi aprire.',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MealChoiceChip(
                          label: 'Colazione',
                          value: 'colazione',
                          currentValue: _mealType,
                          onSelected: _submitting
                              ? null
                              : (value) => setState(() => _mealType = value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MealChoiceChip(
                          label: 'Pranzo',
                          value: 'pranzo',
                          currentValue: _mealType,
                          onSelected: _submitting
                              ? null
                              : (value) => setState(() => _mealType = value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MealChoiceChip(
                          label: 'Cena',
                          value: 'cena',
                          currentValue: _mealType,
                          onSelected: _submitting
                              ? null
                              : (value) => setState(() => _mealType = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickDateTime,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(selectedDateText),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.mist,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Posti totali',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.brown,
                            ),
                          ),
                        ),
                        _CounterButton(
                          icon: Icons.remove,
                          onTap: _submitting || _totalSeats <= 1
                              ? null
                              : () => setState(() => _totalSeats -= 1),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            '$_totalSeats',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontSize: 28,
                            ),
                          ),
                        ),
                        _CounterButton(
                          icon: Icons.add,
                          onTap: _submitting || _totalSeats >= 8
                              ? null
                              : () => setState(() => _totalSeats += 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: null,
              subtitle:
                  'Apri la mappa solo quando ti serve, spostati con il GPS e poi carica i locali vicini.',
              child: _buildMapSection(),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: null,
              subtitle:
                  'Nome, indirizzo e telefono si compilano in automatico quando selezioni un locale sulla mappa.',
              child: Column(
                children: [
                  TextFormField(
                    controller: _localeController,
                    enabled: !_submitting,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome del locale',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Seleziona un locale dalla mappa.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _addressController,
                    enabled: !_submitting,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Indirizzo',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Inserisci l\'indirizzo del locale.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Telefono del locale',
                      prefixIcon: const Icon(Icons.call_outlined),
                      suffixIcon: _phoneController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: _callSelectedPlace,
                              icon: const Icon(Icons.phone_forwarded_rounded),
                              tooltip: 'Chiama il locale',
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: null,
              subtitle:
                  'Spiega che atmosfera vuoi creare e cosa ti va di condividere.',
              child: Column(
                children: [
                  TextFormField(
                    controller: _descriptionController,
                    enabled: !_submitting,
                    minLines: 5,
                    maxLines: 7,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Descrizione',
                      alignLabelWithHint: true,
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 72),
                        child: Icon(Icons.notes_rounded),
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().length < 30) {
                        return 'Scrivi almeno 30 caratteri.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickImage,
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    label: Text(
                      _pickedImage == null
                          ? 'Aggiungi foto locale (opzionale)'
                          : 'Cambia foto del locale',
                    ),
                  ),
                  if (_pickedImage != null) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: AspectRatio(
                        aspectRatio: 16 / 10,
                        child: Image.file(
                          File(_pickedImage!.path),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _pickedImage!.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.brown.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.send_rounded),
              label: Text(
                _submitting
                    ? (isEditing
                        ? 'Sto aggiornando...'
                        : 'Sto pubblicando...')
                    : (isEditing
                        ? 'Salva modifiche'
                        : 'Pubblica offerta'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSection() {
    if (!AppConfig.googleMapsEnabled) {
      return const _GoogleMapsPlaceholderCard();
    }

    if (!_mapExpanded) {
      return _CollapsedMapLauncher(
        onTap: _submitting
            ? null
            : () {
                setState(() => _mapExpanded = true);
                if (!_initialLocationRequested) {
                  unawaited(_bootstrapCurrentLocation());
                }
              },
      );
    }

    if (!_initialMapReady) {
      return const _MapBootstrappingCard();
    }

    return Column(
      children: [
        _GoogleMapsPreviewCard(
          target: _currentMapCenter,
          markers: _nearbyMarkers,
          isBusy: _isLocating || _loadingNearbyPlaces,
          onMapCreated: _handleMapCreated,
          onCameraMove: _handleCameraMove,
          onCameraIdle: () {},
          onRecenterTap: _submitting || _isLocating ? null : _useCurrentLocation,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _submitting
                    ? null
                    : () => setState(() => _mapExpanded = false),
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                label: const Text('Chiudi la mappa'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _submitting || _loadingNearbyPlaces
                    ? null
                    : () => unawaited(_refreshNearbyPlaces(force: true)),
                icon: const Icon(Icons.storefront_rounded),
                label: Text(
                  _nearbyPlacesLoaded
                      ? 'Aggiorna locali qui'
                      : 'Scegli il locale',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _bootstrapCurrentLocation() async {
    if (_initialLocationRequested) {
      return;
    }
    _initialLocationRequested = true;
    await _useCurrentLocation(silent: true);
    if (!mounted) {
      return;
    }
    if (!_initialMapReady) {
      setState(() => _initialMapReady = true);
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('it'),
    );
    if (pickedDate == null || !mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedDateTime != null
          ? TimeOfDay.fromDateTime(_selectedDateTime!)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (pickedTime == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (image == null || !mounted) {
      return;
    }
    setState(() => _pickedImage = image);
  }

  Future<void> _useCurrentLocation({bool silent = false}) async {
    if (_isLocating) {
      return;
    }

    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Attiva il GPS del telefono e riprova.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Permesso posizione negato.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Permesso posizione negato in modo permanente. Riattivalo dalle impostazioni.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) {
        return;
      }

      final target = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentMapCenter = target;
        _initialMapReady = true;
      });
      await _animateMapTo(target, zoom: 16.2);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _initialMapReady = true);
      if (!silent) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _handleMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (!_mapControllerCompleter.isCompleted) {
      _mapControllerCompleter.complete(controller);
    }
    unawaited(_animateMapTo(_currentMapCenter));
  }

  void _handleCameraMove(CameraPosition position) {
    _currentMapCenter = position.target;
  }

  Future<void> _refreshNearbyPlaces({bool force = false}) async {
    if (!AppConfig.googleMapsEnabled || !_initialMapReady || _submitting) {
      return;
    }

    setState(() => _loadingNearbyPlaces = true);
    final queryCenter = _currentMapCenter;

    try {
      final places = await widget.authController.apiClient.fetchNearbyPlaces(
        latitude: queryCenter.latitude,
        longitude: queryCenter.longitude,
      );
      if (!mounted) {
        return;
      }
      _nearbyPlaces = places;
      _nearbyPlacesLoaded = true;
      await _rebuildNearbyMarkers();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _nearbyPlaces = const [];
      _nearbyPlacesLoaded = true;
      await _rebuildNearbyMarkers();
    } finally {
      if (mounted) {
        setState(() => _loadingNearbyPlaces = false);
      }
    }
  }

  Future<void> _handlePlaceTap(PlaceCandidate place) async {
    if (_submitting) {
      return;
    }
    await _selectPlace(place);
  }

  Future<void> _selectPlace(PlaceCandidate place) async {
    _localeController.text = place.name;
    _addressController.text = place.address;
    _phoneController.text = place.phoneNumber;

    setState(() {
      _selectedPlaceId = place.id;
      _selectedLatitude = place.latitude;
      _selectedLongitude = place.longitude;
      _selectedPrimaryType = place.primaryType;
      _currentMapCenter = LatLng(place.latitude, place.longitude);
    });

    await _rebuildNearbyMarkers();
    await _animateMapTo(
      LatLng(place.latitude, place.longitude),
      zoom: 16.6,
    );

    if (place.id.isNotEmpty &&
        (place.address.trim().isEmpty || place.phoneNumber.trim().isEmpty)) {
      await _hydrateSelectedPlaceDetails(place);
    }
  }

  Future<void> _hydrateSelectedPlaceDetails(PlaceCandidate place) async {
    try {
      final details =
          await widget.authController.apiClient.fetchPlaceDetails(place.id);
      if (!mounted || _selectedPlaceId != place.id) {
        return;
      }

      _localeController.text = details.name.isEmpty
          ? _localeController.text
          : details.name;
      _addressController.text = details.address.isEmpty
          ? _addressController.text
          : details.address;
      _phoneController.text = details.phoneNumber;

      setState(() {
        _selectedPrimaryType = details.primaryType;
        if (details.latitude != 0 && details.longitude != 0) {
          _selectedLatitude = details.latitude;
          _selectedLongitude = details.longitude;
        }
      });
      await _rebuildNearbyMarkers();
    } catch (_) {
      // Manteniamo i dati base gia mostrati.
    }
  }

  Future<void> _rebuildNearbyMarkers() async {
    final markers = <Marker>{};

    for (final place in _nearbyPlaces) {
      final selected = place.id == _selectedPlaceId;
      final icon = await _markerIconFor(place, selected: selected);
      markers.add(
        Marker(
          markerId: MarkerId('place_${place.id}'),
          position: LatLng(place.latitude, place.longitude),
          icon: icon,
          anchor: const Offset(0.5, 1),
          infoWindow: InfoWindow(
            title: place.name,
            snippet: _placeTypeLabel(place.primaryType),
          ),
          zIndexInt: selected ? 20 : 10,
          onTap: () => unawaited(_handlePlaceTap(place)),
        ),
      );
    }

    final hasSelectedMarkerInList = _selectedPlaceId != null &&
        _nearbyPlaces.any((place) => place.id == _selectedPlaceId);
    if (!hasSelectedMarkerInList &&
        _selectedLatitude != null &&
        _selectedLongitude != null) {
      final fallbackPlace = PlaceCandidate(
        id: _selectedPlaceId ?? 'selected_offer_location',
        name: _localeController.text.trim().isEmpty
            ? 'Locale selezionato'
            : _localeController.text.trim(),
        address: _addressController.text.trim(),
        latitude: _selectedLatitude!,
        longitude: _selectedLongitude!,
        primaryType: _selectedPrimaryType,
        phoneNumber: _phoneController.text.trim(),
      );
      markers.add(
        Marker(
          markerId: const MarkerId('selected_offer_location'),
          position: LatLng(_selectedLatitude!, _selectedLongitude!),
          icon: await _markerIconFor(fallbackPlace, selected: true),
          anchor: const Offset(0.5, 1),
          infoWindow: InfoWindow(
            title: fallbackPlace.name,
            snippet: fallbackPlace.address.isEmpty ? null : fallbackPlace.address,
          ),
          zIndexInt: 30,
          onTap: () => unawaited(_handlePlaceTap(fallbackPlace)),
        ),
      );
    }

    if (!mounted) {
      return;
    }
    setState(() => _nearbyMarkers = markers);
  }

  Future<BitmapDescriptor> _markerIconFor(
    PlaceCandidate place, {
    required bool selected,
  }) async {
    final visual = _markerVisualForType(place.primaryType);
    final cacheKey =
        '${selected ? 'selected' : 'normal'}:${visual.cacheKey}';

    final cached = _markerIconCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    try {
      final descriptor = await _buildMarkerDescriptor(
        icon: visual.icon,
        accentColor: visual.color,
        selected: selected,
      );
      _markerIconCache[cacheKey] = descriptor;
      return descriptor;
    } catch (_) {
      return BitmapDescriptor.defaultMarkerWithHue(
        selected ? BitmapDescriptor.hueOrange : visual.fallbackHue,
      );
    }
  }

  _MarkerVisual _markerVisualForType(String primaryType) {
    switch (primaryType.trim().toLowerCase()) {
      case 'cafe':
      case 'coffee_shop':
      case 'brunch_restaurant':
        return const _MarkerVisual(
          cacheKey: 'coffee',
          icon: Icons.local_cafe,
          color: Color(0xFF8A5A44),
          fallbackHue: BitmapDescriptor.hueOrange,
        );
      case 'bar':
        return const _MarkerVisual(
          cacheKey: 'bar',
          icon: Icons.local_bar,
          color: Color(0xFF7A4EC7),
          fallbackHue: BitmapDescriptor.hueViolet,
        );
      case 'pizza_restaurant':
        return const _MarkerVisual(
          cacheKey: 'pizza',
          icon: Icons.local_pizza,
          color: Color(0xFFE86E35),
          fallbackHue: BitmapDescriptor.hueRose,
        );
      case 'bakery':
        return const _MarkerVisual(
          cacheKey: 'bakery',
          icon: Icons.bakery_dining,
          color: Color(0xFFD49B00),
          fallbackHue: BitmapDescriptor.hueYellow,
        );
      case 'meal_takeaway':
      case 'fast_food_restaurant':
      case 'sandwich_shop':
        return const _MarkerVisual(
          cacheKey: 'takeaway',
          icon: Icons.takeout_dining,
          color: Color(0xFF3D8B5A),
          fallbackHue: BitmapDescriptor.hueGreen,
        );
      default:
        return const _MarkerVisual(
          cacheKey: 'restaurant',
          icon: Icons.restaurant,
          color: AppTheme.orange,
          fallbackHue: BitmapDescriptor.hueRed,
        );
    }
  }

  String _placeTypeLabel(String primaryType) {
    switch (primaryType.trim().toLowerCase()) {
      case 'cafe':
      case 'coffee_shop':
        return 'Bar o caffe';
      case 'bar':
        return 'Pub o bar';
      case 'pizza_restaurant':
        return 'Pizzeria';
      case 'bakery':
        return 'Bakery';
      case 'meal_takeaway':
      case 'fast_food_restaurant':
      case 'sandwich_shop':
        return 'Locale veloce';
      default:
        return 'Ristorante';
    }
  }

  Future<BitmapDescriptor> _buildMarkerDescriptor({
    required IconData icon,
    required Color accentColor,
    required bool selected,
  }) async {
    const canvasWidth = 132.0;
    const canvasHeight = 156.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    );

    final bubbleCenter = const Offset(canvasWidth / 2, 48);
    final bubbleRadius = selected ? 38.0 : 34.0;
    final innerRadius = selected ? 26.0 : 23.0;

    final tailPath = Path()
      ..moveTo(canvasWidth / 2, canvasHeight - 8)
      ..lineTo((canvasWidth / 2) - 16, 82)
      ..quadraticBezierTo(canvasWidth / 2, 98, (canvasWidth / 2) + 16, 82)
      ..close();
    final shadowPath = Path()
      ..addOval(Rect.fromCircle(center: bubbleCenter, radius: bubbleRadius))
      ..addPath(tailPath, Offset.zero);

    canvas.drawShadow(
      shadowPath,
      Colors.black.withValues(alpha: 0.28),
      16,
      true,
    );

    final outerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(bubbleCenter, bubbleRadius, outerPaint);
    canvas.drawPath(tailPath, outerPaint);

    final borderPaint = Paint()
      ..color = selected ? AppTheme.orange : accentColor.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 6 : 5;
    canvas.drawCircle(bubbleCenter, bubbleRadius - 3, borderPaint);

    final innerPaint = Paint()
      ..color = selected ? AppTheme.orange : accentColor;
    canvas.drawCircle(bubbleCenter, innerRadius, innerPaint);

    final painter = TextPainter(textDirection: ui.TextDirection.ltr);
    painter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: selected ? 34 : 30,
        color: Colors.white,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
      ),
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(
        bubbleCenter.dx - painter.width / 2,
        bubbleCenter.dy - painter.height / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List();
    if (bytes == null) {
      throw StateError('Impossibile creare il marker.');
    }

    return BitmapDescriptor.bytes(
      bytes,
      width: selected ? 54 : 50,
      height: selected ? 64 : 60,
    );
  }

  Future<void> _animateMapTo(
    LatLng target, {
    double zoom = 15.6,
  }) async {
    final controller =
        _mapController ??
        (_mapControllerCompleter.isCompleted
            ? await _mapControllerCompleter.future
            : null);
    if (controller == null) {
      return;
    }
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedDateTime == null) {
      _showMessage('Scegli data e ora dell\'invito.');
      return;
    }
    if (_mealType == null || _mealType!.trim().isEmpty) {
      _showMessage('Scegli il momento del pasto.');
      return;
    }
    if (_selectedLatitude == null || _selectedLongitude == null) {
      _showMessage('Scegli un locale dalla mappa.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final message = widget.initialOffer == null
          ? await widget.authController.apiClient.createOffer(
              mealType: _mealType!,
              localeName: _localeController.text.trim(),
              address: _addressController.text.trim(),
              localePhone: _phoneController.text.trim(),
              latitude: _selectedLatitude!.toString(),
              longitude: _selectedLongitude!.toString(),
              totalSeats: _totalSeats,
              dateTime: _selectedDateTime!,
              description: _descriptionController.text.trim(),
              photoPath: _pickedImage?.path,
            )
          : await widget.authController.apiClient.updateOffer(
              offerId: widget.initialOffer!.id,
              mealType: _mealType!,
              localeName: _localeController.text.trim(),
              address: _addressController.text.trim(),
              localePhone: _phoneController.text.trim(),
              latitude: _selectedLatitude!.toString(),
              longitude: _selectedLongitude!.toString(),
              totalSeats: _totalSeats,
              dateTime: _selectedDateTime!,
              description: _descriptionController.text.trim(),
              photoPath: _pickedImage?.path,
            );

      if (widget.onOfferCreated != null) {
        await widget.onOfferCreated!.call();
      }
      if (!mounted) {
        return;
      }

      _showMessage(message);
      if (widget.initialOffer != null) {
        Navigator.of(context).pop(true);
        return;
      }
      _localeController.clear();
      _addressController.clear();
      _phoneController.clear();
      _descriptionController.clear();
      setState(() {
        _mealType = null;
        _totalSeats = 2;
        _selectedDateTime = null;
        _pickedImage = null;
        _mapExpanded = false;
        _nearbyPlacesLoaded = false;
        _selectedPlaceId = null;
        _selectedLatitude = null;
        _selectedLongitude = null;
        _selectedPrimaryType = '';
        _nearbyPlaces = const [];
      });
      await _rebuildNearbyMarkers();
      unawaited(_bootstrapCurrentLocation());
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _callSelectedPlace() async {
    if (_phoneController.text.trim().isEmpty) {
      return;
    }
    final digits = _phoneController.text.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.tryParse('tel:$digits');
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _prefillFromOffer(Offer offer) {
    _mealType = offer.tipoPasto;
    _totalSeats = offer.postiTotali;
    _selectedDateTime = offer.dataOra;
    _localeController.text = offer.nomeLocale;
    _addressController.text = offer.indirizzo;
    _phoneController.text = offer.telefonoLocale;
    _descriptionController.text = offer.descrizione;
    _selectedLatitude = offer.latitude;
    _selectedLongitude = offer.longitude;
    _selectedPlaceId = 'offer_${offer.id}';
    _currentMapCenter = LatLng(offer.latitude, offer.longitude);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String? title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null && title!.trim().isNotEmpty) ...[
              Text(title!, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
            ],
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.brown.withValues(alpha: 0.86),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _CollapsedMapLauncher extends StatelessWidget {
  const _CollapsedMapLauncher({
    required this.onTap,
  });

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.mist,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.map_outlined,
                color: AppTheme.orange,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Scegli dalla mappa',
              style: TextStyle(
                color: AppTheme.brown,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Apri la mappa, usa il GPS e poi carica i locali vicini solo quando vuoi scegliere davvero il posto.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.brown.withValues(alpha: 0.84),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.open_in_full_rounded),
              label: const Text('Apri la mappa'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleMapsPreviewCard extends StatelessWidget {
  const _GoogleMapsPreviewCard({
    required this.target,
    required this.markers,
    required this.isBusy,
    required this.onMapCreated,
    required this.onCameraMove,
    required this.onCameraIdle,
    required this.onRecenterTap,
  });

  final LatLng target;
  final Set<Marker> markers;
  final bool isBusy;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<CameraPosition> onCameraMove;
  final VoidCallback onCameraIdle;
  final Future<void> Function()? onRecenterTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 304,
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: onMapCreated,
              initialCameraPosition: CameraPosition(
                target: target,
                zoom: 15.6,
              ),
              markers: markers,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
              myLocationEnabled: true,
              zoomControlsEnabled: false,
              compassEnabled: false,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              onCameraMove: onCameraMove,
              onCameraIdle: onCameraIdle,
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  EagerGestureRecognizer.new,
                ),
              },
            ),
            Positioned(
              top: 14,
              right: 14,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onRecenterTap == null
                      ? null
                      : () => unawaited(onRecenterTap!.call()),
                  child: Ink(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: AppTheme.orange,
                    ),
                  ),
                ),
              ),
            ),
            if (isBusy)
              const Positioned(
                bottom: 14,
                left: 14,
                child: _BusyMapBadge(),
              ),
          ],
        ),
      ),
    );
  }
}

class _BusyMapBadge extends StatelessWidget {
  const _BusyMapBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: const CircularProgressIndicator(
        strokeWidth: 2.6,
        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.orange),
      ),
    );
  }
}

class _MapBootstrappingCard extends StatelessWidget {
  const _MapBootstrappingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 304,
      decoration: BoxDecoration(
        color: AppTheme.mist,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.orange),
        ),
      ),
    );
  }
}

class _GoogleMapsPlaceholderCard extends StatelessWidget {
  const _GoogleMapsPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.mist,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Text(
        'Google Maps non e attivo in questa build.',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppTheme.brown.withValues(alpha: 0.78),
            ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: onTap == null ? AppTheme.cardBorder : AppTheme.sand,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppTheme.brown),
      ),
    );
  }
}

class _MealChoiceChip extends StatelessWidget {
  const _MealChoiceChip({
    required this.label,
    required this.value,
    required this.currentValue,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String? currentValue;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = currentValue == value;
    final color = switch (value) {
      'colazione' => const Color(0xFFD49B00),
      'pranzo' => const Color(0xFF3D8B5A),
      'cena' => const Color(0xFF7A4EC7),
      _ => AppTheme.orange,
    };

    return SizedBox(
      width: double.infinity,
      child: ChoiceChip(
        selected: selected,
        label: SizedBox(
          width: double.infinity,
          child: Text(
            label,
            textAlign: TextAlign.center,
          ),
        ),
        onSelected: onSelected == null ? null : (_) => onSelected!(value),
        backgroundColor: Colors.white,
        selectedColor: color.withValues(alpha: 0.16),
        side: BorderSide(color: color.withValues(alpha: 0.36)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        labelStyle: TextStyle(
          color: selected ? color : AppTheme.brown,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MarkerVisual {
  const _MarkerVisual({
    required this.cacheKey,
    required this.icon,
    required this.color,
    required this.fallbackHue,
  });

  final String cacheKey;
  final IconData icon;
  final Color color;
  final double fallbackHue;
}
