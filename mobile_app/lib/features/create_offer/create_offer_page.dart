import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
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

class CreateOfferPageResult {
  const CreateOfferPageResult({
    required this.changed,
    this.message,
  });

  final bool changed;
  final String? message;
}

class _CreateOfferPageState extends State<CreateOfferPage> {
  static const LatLng _fallbackMapTarget = LatLng(45.070339, 7.686864);

  final _formKey = GlobalKey<FormState>();
  final _localeController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  final _scrollController = ScrollController();
  final _venueSectionKey = GlobalKey();
  final ValueNotifier<int> _mapPickerRefreshTick = ValueNotifier(0);
  final Completer<GoogleMapController> _mapControllerCompleter = Completer();

  String? _mealType;
  int _totalSeats = 1;
  DateTime? _selectedDateTime;
  XFile? _pickedImage;
  bool _submitting = false;
  bool _deleting = false;
  bool _isLocating = false;
  bool _initialLocationRequested = false;
  bool _initialMapReady = !AppConfig.googleMapsEnabled;
  bool _loadingNearbyPlaces = false;
  bool _nearbyPlacesLoaded = false;
  GoogleMapController? _mapController;
  BuildContext? _mapPickerSheetContext;
  LatLng _currentMapCenter = _fallbackMapTarget;
  double? _selectedLatitude;
  double? _selectedLongitude;
  String? _selectedPlaceId;
  String _selectedPrimaryType = '';
  PlaceCandidate? _mapDraftSelection;
  List<PlaceCandidate> _nearbyPlaces = const [];
  Set<Marker> _nearbyMarkers = const <Marker>{};
  final Map<String, BitmapDescriptor> _markerIconCache = {};
  String? _lastImmediateTimingWarning;

  int get _occupiedSeats {
    final initialOffer = widget.initialOffer;
    if (initialOffer == null) {
      return 0;
    }
    return (initialOffer.postiTotali - initialOffer.postiDisponibili).clamp(
      0,
      initialOffer.postiTotali,
    );
  }

  int get _minimumSeatsAllowed {
    if (widget.initialOffer == null) {
      return 1;
    }
    return _occupiedSeats == 0 ? 1 : _occupiedSeats;
  }

  String? get _publicationTimingWarning =>
      _buildPublicationTimingWarning(_mealType, _selectedDateTime);

  String? _buildPublicationTimingWarning(
    String? mealType,
    DateTime? selectedDateTime,
  ) {
    if (mealType == null ||
        mealType.trim().isEmpty ||
        selectedDateTime == null) {
      return null;
    }

    final leadHours = mealType == 'colazione' ? 1 : 6;
    final latestAllowedPublication = selectedDateTime.subtract(
      Duration(hours: leadHours),
    );
    if (DateTime.now().isBefore(latestAllowedPublication)) {
      return null;
    }

    if (mealType == 'colazione') {
      return 'Questa colazione verrebbe pubblicata troppo tardi: deve essere inserita almeno 1 ora prima dell\'inizio.';
    }
    if (mealType == 'pranzo') {
      return 'Questo pranzo verrebbe pubblicato troppo tardi: i pranzi devono essere inseriti almeno 6 ore prima dell\'inizio.';
    }
    return 'Questa cena verrebbe pubblicata troppo tardi: le cene devono essere inserite almeno 6 ore prima dell\'inizio.';
  }

  void _setMealType(String value) {
    setState(() => _mealType = value);
    _maybeShowPublicationTimingWarning();
  }

  void _maybeShowPublicationTimingWarning() {
    final warning = _publicationTimingWarning;
    if (warning == null) {
      _lastImmediateTimingWarning = null;
      return;
    }
    if (_lastImmediateTimingWarning == warning) {
      return;
    }
    _lastImmediateTimingWarning = warning;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _showMessage(warning);
    });
  }

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
    _scrollController.dispose();
    _mapPickerRefreshTick.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initialOffer != null;
    final selectedDateText = _selectedDateTime == null
        ? 'Scegli data e ora'
        : DateFormat('EEEE d MMMM - HH:mm', 'it_IT').format(_selectedDateTime!);

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(height: 42, alignment: Alignment.center),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
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
                          onSelected: _submitting ? null : _setMealType,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MealChoiceChip(
                          label: 'Pranzo',
                          value: 'pranzo',
                          currentValue: _mealType,
                          onSelected: _submitting ? null : _setMealType,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MealChoiceChip(
                          label: 'Cena',
                          value: 'cena',
                          currentValue: _mealType,
                          onSelected: _submitting ? null : _setMealType,
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
                  if (_publicationTimingWarning != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1ED),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFF1B8AA)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.schedule_outlined,
                              color: Color(0xFFB65C45),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _publicationTimingWarning!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF8A4336),
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Posti totali',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.brown,
                                ),
                              ),
                              if (widget.initialOffer != null &&
                                  _occupiedSeats > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Minimo $_minimumSeatsAllowed: $_occupiedSeats partecipanti gia dentro.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        AppTheme.brown.withValues(alpha: 0.66),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        _CounterButton(
                          icon: Icons.remove,
                          onTap: _submitting ||
                                  _deleting ||
                                  _totalSeats <= _minimumSeatsAllowed
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
                          onTap: _submitting || _deleting || _totalSeats >= 8
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
              key: _venueSectionKey,
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
                        return 'Inserisci il nome del locale.';
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
                    enabled: !_submitting,
                    keyboardType: TextInputType.phone,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Scegli dalla mappa',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                _SectionCard(
                  title: null,
                  subtitle: null,
                  child: _buildMapSection(),
                ),
              ],
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
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
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
            if (isEditing)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting || _deleting ? null : _deleteOffer,
                      icon: _deleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline_rounded),
                      label: const Text('Elimina offerta'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF8A4336),
                        side: const BorderSide(color: Color(0xFFD7B4AC)),
                        backgroundColor: const Color(0xFFF7ECE8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submitting || _deleting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _submitting ? 'Sto salvando...' : 'Salva modifiche',
                      ),
                    ),
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: _submitting || _deleting ? null : _submit,
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  _submitting ? 'Sto pubblicando...' : 'Pubblica offerta',
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

    return _CollapsedMapLauncher(
      onTap: _submitting ? null : _openMapPicker,
    );
  }

  Future<void> _openMapPicker() async {
    if (_submitting) {
      return;
    }

    if (!_initialLocationRequested) {
      await _bootstrapCurrentLocation();
    }
    if (!mounted) {
      return;
    }

    _mapDraftSelection ??= _currentCommittedPlaceCandidate();
    _refreshMapPicker();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        _mapPickerSheetContext = sheetContext;
        return ValueListenableBuilder<int>(
          valueListenable: _mapPickerRefreshTick,
          builder: (context, _, __) => _buildMapPickerSheet(context),
        );
      },
    ).whenComplete(() {
      _mapPickerSheetContext = null;
      if (mounted && _mapDraftSelection != null) {
        setState(() => _mapDraftSelection = null);
        _refreshMapPicker();
      }
    });
  }

  Widget _buildMapPickerSheet(BuildContext context) {
    final theme = Theme.of(context);

    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFFBF7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.cardBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scegli dalla mappa',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 24,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Chiudi',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Apri la mappa in grande, spostati dove vuoi, tocca il locale giusto e conferma solo quando sei sicuro.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.brown.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: !_initialMapReady
                          ? const _MapBootstrappingCard(height: null)
                          : _GoogleMapsPreviewCard(
                              target: _currentMapCenter,
                              markers: _nearbyMarkers,
                              isBusy: _isLocating || _loadingNearbyPlaces,
                              onMapCreated: _handleMapCreated,
                              onCameraMove: _handleCameraMove,
                              onCameraIdle: () {},
                              onRecenterTap: _submitting || _isLocating
                                  ? null
                                  : _useCurrentLocation,
                              height: null,
                            ),
                    ),
                    if (_mapDraftSelection != null)
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 72,
                        child: _SelectedPlacePreviewCard(
                          place: _mapDraftSelection!,
                          onConfirm: _submitting || _loadingNearbyPlaces
                              ? null
                              : _confirmMapSelection,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loadingNearbyPlaces || _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      label: const Text('Chiudi'),
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
                            : 'Carica locali qui',
                      ),
                    ),
                  ),
                ],
              ),
              if (_nearbyPlacesLoaded && _nearbyPlaces.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Tocca un marker per scegliere il locale, poi conferma con Offri qui.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.brown.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
      _refreshMapPicker();
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
    _maybeShowPublicationTimingWarning();
  }

  Future<ImageSource?> _pickImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Scatta una foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Scegli dalla galleria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final source = await _pickImageSource();
    if (!mounted || source == null) {
      return;
    }

    final image = await _picker.pickImage(
      source: source,
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
        _refreshMapPicker();
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
        _refreshMapPicker();
      }
    }
  }

  Future<void> _handlePlaceTap(PlaceCandidate place) async {
    if (_submitting) {
      return;
    }
    await _previewPlaceSelection(place);
  }

  Future<void> _previewPlaceSelection(PlaceCandidate place) async {
    setState(() {
      _mapDraftSelection = place;
      _currentMapCenter = LatLng(place.latitude, place.longitude);
    });
    _refreshMapPicker();

    await _rebuildNearbyMarkers();
    await _animateMapTo(
      LatLng(place.latitude, place.longitude),
      zoom: 16.6,
    );

    if (place.id.isNotEmpty &&
        (place.address.trim().isEmpty || place.phoneNumber.trim().isEmpty)) {
      await _hydrateDraftPlaceDetails(place);
    }
  }

  Future<void> _hydrateDraftPlaceDetails(PlaceCandidate place) async {
    try {
      final details =
          await widget.authController.apiClient.fetchPlaceDetails(place.id);
      if (!mounted || _mapDraftSelection?.id != place.id) {
        return;
      }

      setState(() {
        _mapDraftSelection = PlaceCandidate(
          id: place.id,
          name: details.name.isEmpty ? place.name : details.name,
          address: details.address.isEmpty ? place.address : details.address,
          latitude: details.latitude != 0 ? details.latitude : place.latitude,
          longitude:
              details.longitude != 0 ? details.longitude : place.longitude,
          primaryType: details.primaryType.isEmpty
              ? place.primaryType
              : details.primaryType,
          phoneNumber: details.phoneNumber,
        );
        if (details.latitude != 0 && details.longitude != 0) {
          _currentMapCenter = LatLng(details.latitude, details.longitude);
        }
      });
      _refreshMapPicker();
      await _rebuildNearbyMarkers();
    } catch (_) {
      // Manteniamo i dati base gia mostrati.
    }
  }

  Future<void> _rebuildNearbyMarkers() async {
    final markers = <Marker>{};
    final highlightedPlaceId = _mapDraftSelection?.id ?? _selectedPlaceId;

    for (final place in _nearbyPlaces) {
      final selected = place.id == highlightedPlaceId;
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

    final fallbackPlace =
        _mapDraftSelection ?? _currentCommittedPlaceCandidate();
    final hasSelectedMarkerInList = highlightedPlaceId != null &&
        _nearbyPlaces.any((place) => place.id == highlightedPlaceId);
    if (!hasSelectedMarkerInList && fallbackPlace != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('selected_offer_location'),
          position: LatLng(fallbackPlace.latitude, fallbackPlace.longitude),
          icon: await _markerIconFor(fallbackPlace, selected: true),
          anchor: const Offset(0.5, 1),
          infoWindow: InfoWindow(
            title: fallbackPlace.name,
            snippet:
                fallbackPlace.address.isEmpty ? null : fallbackPlace.address,
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
    _refreshMapPicker();
  }

  PlaceCandidate? _currentCommittedPlaceCandidate() {
    if (_selectedLatitude == null || _selectedLongitude == null) {
      return null;
    }
    return PlaceCandidate(
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
  }

  Future<void> _confirmMapSelection() async {
    final place = _mapDraftSelection;
    if (place == null) {
      _showMessage('Scegli un locale dalla mappa prima di continuare.');
      return;
    }

    _localeController.text = place.name;
    _addressController.text = place.address;
    _phoneController.text = place.phoneNumber;

    setState(() {
      _selectedPlaceId = place.id;
      _selectedLatitude = place.latitude;
      _selectedLongitude = place.longitude;
      _selectedPrimaryType = place.primaryType;
      _currentMapCenter = LatLng(place.latitude, place.longitude);
      _mapDraftSelection = null;
    });
    _refreshMapPicker();

    await _rebuildNearbyMarkers();
    if (!mounted) {
      return;
    }

    final pickerContext = _mapPickerSheetContext;
    if (pickerContext != null) {
      Navigator.of(pickerContext).pop();
    }
    await _scrollToVenueSection();
  }

  Future<BitmapDescriptor> _markerIconFor(
    PlaceCandidate place, {
    required bool selected,
  }) async {
    final visual = _markerVisualForType(place.primaryType);
    final cacheKey = '${selected ? 'selected' : 'normal'}:${visual.cacheKey}';

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
    final controller = _mapController ??
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
    if (_totalSeats < _minimumSeatsAllowed) {
      _showMessage(
        'Non puoi scendere sotto $_minimumSeatsAllowed posti: ci sono gia partecipanti confermati.',
      );
      return;
    }
    if (_mealType == null || _mealType!.trim().isEmpty) {
      _showMessage('Scegli il momento del pasto.');
      return;
    }
    final publicationTimingWarning = _publicationTimingWarning;
    if (publicationTimingWarning != null) {
      _showMessage(publicationTimingWarning);
      return;
    }

    if (_selectedLatitude == null || _selectedLongitude == null) {
      final resolvedCoordinates = await _resolveManualAddressCoordinates();
      if (resolvedCoordinates == null) {
        return;
      }
      _selectedLatitude = resolvedCoordinates.latitude;
      _selectedLongitude = resolvedCoordinates.longitude;
      _currentMapCenter = resolvedCoordinates;
    }

    var shouldCloseEditor = false;
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

      if (!mounted) {
        return;
      }

      if (widget.initialOffer != null) {
        shouldCloseEditor = true;
        final navigator = Navigator.of(context);
        if (mounted) {
          setState(() => _submitting = false);
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (navigator.mounted) {
          navigator.pop(const CreateOfferPageResult(changed: true));
        }
        return;
      }
      _showMessage(message);
      if (widget.onOfferCreated != null) {
        await widget.onOfferCreated!.call();
      }
      _localeController.clear();
      _addressController.clear();
      _phoneController.clear();
      _descriptionController.clear();
      setState(() {
        _mealType = null;
        _totalSeats = 1;
        _selectedDateTime = null;
        _pickedImage = null;
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
      if (mounted && !shouldCloseEditor) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _deleteOffer() async {
    final offer = widget.initialOffer;
    if (offer == null) {
      return;
    }

    var shouldCloseEditor = false;
    setState(() => _deleting = true);
    try {
      await widget.authController.apiClient.deleteOffer(offer.id);
      if (!mounted) {
        return;
      }
      shouldCloseEditor = true;
      final navigator = Navigator.of(context);
      if (mounted) {
        setState(() => _deleting = false);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (navigator.mounted) {
        navigator.pop(const CreateOfferPageResult(changed: true));
      }
      return;
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted && !shouldCloseEditor) {
        setState(() => _deleting = false);
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

  Future<LatLng?> _resolveManualAddressCoordinates() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      _showMessage('Inserisci un indirizzo valido oppure scegli il locale dalla mappa.');
      return null;
    }

    try {
      final locations = await locationFromAddress(address);
      if (locations.isEmpty) {
        _showMessage('Non riesco a trovare questo indirizzo. Controllalo oppure scegli il locale dalla mappa.');
        return null;
      }
      final first = locations.first;
      return LatLng(first.latitude, first.longitude);
    } catch (_) {
      _showMessage('Non riesco a trovare questo indirizzo. Controllalo oppure scegli il locale dalla mappa.');
      return null;
    }
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

  void _refreshMapPicker() {
    _mapPickerRefreshTick.value++;
  }

  Future<void> _scrollToVenueSection() async {
    final venueContext = _venueSectionKey.currentContext;
    if (venueContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      venueContext,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String? title;
  final String? subtitle;
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
              Align(
                alignment: Alignment.center,
                child: Text(
                  title!,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.brown.withValues(alpha: 0.86),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.mist,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton(
            onPressed: onTap,
            child: const Text('Apri mappa'),
          ),
        ],
      ),
    );
  }
}

class _SelectedPlacePreviewCard extends StatelessWidget {
  const _SelectedPlacePreviewCard({
    required this.place,
    required this.onConfirm,
  });

  final PlaceCandidate place;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.espresso,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Locale selezionato',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.brown.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('Offri qui'),
          ),
        ],
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
    this.height = 304,
  });

  final LatLng target;
  final Set<Marker> markers;
  final bool isBusy;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<CameraPosition> onCameraMove;
  final VoidCallback onCameraIdle;
  final Future<void> Function()? onRecenterTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: height,
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
  const _MapBootstrappingCard({
    this.height = 304,
  });

  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
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
