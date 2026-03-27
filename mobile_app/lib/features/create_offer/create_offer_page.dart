import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../auth/auth_controller.dart';

class CreateOfferPage extends StatefulWidget {
  const CreateOfferPage({
    super.key,
    required this.authController,
    this.onOfferCreated,
  });

  final AuthController authController;
  final Future<void> Function()? onOfferCreated;

  @override
  State<CreateOfferPage> createState() => _CreateOfferPageState();
}

class _CreateOfferPageState extends State<CreateOfferPage> {
  static const LatLng _fallbackMapTarget = LatLng(45.070339, 7.686864);

  final _formKey = GlobalKey<FormState>();
  final _localeController = TextEditingController();
  final _addressController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  final Completer<GoogleMapController> _mapControllerCompleter = Completer();

  String _mealType = 'colazione';
  int _totalSeats = 2;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  XFile? _pickedImage;
  bool _isLocating = false;
  bool _showManualCoordinates = false;
  bool _submitting = false;
  GoogleMapController? _mapController;

  @override
  void dispose() {
    _localeController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _descriptionController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDateTime = _combinedDateTime;
    final theme = Theme.of(context);
    final locationReady = _parsedLatitude != null && _parsedLongitude != null;
    final summaryDate = selectedDateTime == null
        ? 'Scegli data e ora'
        : DateFormat('EEE d MMM - HH:mm', 'it_IT').format(selectedDateTime);
    final summaryPlace = _localeController.text.trim().isEmpty
        ? 'Scegli il locale'
        : _localeController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(height: 24, alignment: Alignment.center),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const BrandHeroCard(
              eyebrow: 'OFFRI',
              centered: true,
              title: 'Pubblica un invito vero',
              subtitle:
                  'Crea un invito pulito da mobile. Oggi scegli il locale in modo manuale, poi qui entreranno Google Maps e Places.',
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SummaryPill(
                    icon: Icons.restaurant_rounded,
                    label: _mealLabel(_mealType),
                  ),
                  _SummaryPill(
                    icon: Icons.schedule_rounded,
                    label: summaryDate,
                  ),
                  _SummaryPill(
                    icon: Icons.people_alt_rounded,
                    label: '$_totalSeats posti',
                  ),
                  _SummaryPill(
                    icon: Icons.storefront_rounded,
                    label: summaryPlace,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '1. Scegli il momento',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Decidi il tipo di tavolo, quanti posti aprire e quando vuoi trovarti.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.brown.withValues(alpha: 0.72),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MealChoiceChip(
                          label: 'Colazione',
                          value: 'colazione',
                          currentValue: _mealType,
                          onSelected: _submitting
                              ? null
                              : (value) => setState(() => _mealType = value),
                        ),
                        _MealChoiceChip(
                          label: 'Pranzo',
                          value: 'pranzo',
                          currentValue: _mealType,
                          onSelected: _submitting
                              ? null
                              : (value) => setState(() => _mealType = value),
                        ),
                        _MealChoiceChip(
                          label: 'Cena',
                          value: 'cena',
                          currentValue: _mealType,
                          onSelected: _submitting
                              ? null
                              : (value) => setState(() => _mealType = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _submitting ? null : _pickDate,
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(
                              _selectedDate == null
                                  ? 'Data'
                                  : DateFormat('EEE d MMM', 'it_IT')
                                      .format(_selectedDate!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _submitting ? null : _pickTime,
                            icon: const Icon(Icons.schedule_outlined),
                            label: Text(
                              _selectedTime == null
                                  ? 'Ora'
                                  : _selectedTime!.format(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (selectedDateTime != null) ...[
                      const SizedBox(height: 12),
                      _InlineInfoBanner(
                        icon: Icons.event_available_rounded,
                        text:
                            'Invito fissato per ${DateFormat('EEEE d MMMM - HH:mm', 'it_IT').format(selectedDateTime)}.',
                      ),
                    ],
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _submitting ? null : _pickDateTime,
                      icon: const Icon(Icons.edit_calendar_rounded),
                      label: const Text('Apri selettore completo'),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '2. Scegli il posto',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Per ora inseriamo il locale manualmente. Intanto puoi usare la posizione del telefono per evitare di scrivere coordinate a mano.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.brown.withValues(alpha: 0.72),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
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
                          return 'Inserisci l\'indirizzo.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3. Posizione',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Usa la posizione del telefono o, se preferisci, inserisci le coordinate manualmente. Qui poi entreranno Google Maps e Places.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.brown.withValues(alpha: 0.72),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (AppConfig.googleMapsEnabled) ...[
                      _GoogleMapsPreviewCard(
                        target: _mapTarget,
                        markers: _mapMarkers,
                        enabled: !_submitting,
                        onMapCreated: _handleMapCreated,
                        onLongPress: _submitting ? null : _setLocationFromMap,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tocco lungo sulla mappa per fissare subito il punto esatto del locale.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.brown.withValues(alpha: 0.72),
                        ),
                      ),
                    ] else ...[
                      const _GoogleMapsPlaceholderCard(),
                    ],
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _submitting || _isLocating
                          ? null
                          : _useCurrentLocation,
                      icon: const Icon(Icons.my_location_rounded),
                      label: Text(
                        locationReady
                            ? 'Posizione del telefono acquisita'
                            : 'Usa la posizione del telefono',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (locationReady)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.sage,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          AppConfig.googleMapsEnabled
                              ? 'Posizione agganciata sulla mappa.'
                              : 'Coordinate pronte: ${_latitudeController.text} / ${_longitudeController.text}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brown,
                          ),
                        ),
                      )
                    else
                      Text(
                        'Se la posizione automatica non va, puoi sempre compilare i campi manuali.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.brown.withValues(alpha: 0.72),
                        ),
                      ),
                    if (!AppConfig.googleMapsEnabled) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _submitting
                            ? null
                            : () => setState(() {
                                  _showManualCoordinates =
                                      !_showManualCoordinates;
                                }),
                        icon: Icon(
                          _showManualCoordinates
                              ? Icons.expand_less_rounded
                              : Icons.edit_location_alt_outlined,
                        ),
                        label: Text(
                          _showManualCoordinates
                              ? 'Nascondi coordinate manuali'
                              : 'Inserisci coordinate manuali',
                        ),
                      ),
                    ],
                    if (!AppConfig.googleMapsEnabled &&
                        _showManualCoordinates) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _latitudeController,
                              enabled: !_submitting,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: const InputDecoration(
                                  labelText: 'Latitudine'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _longitudeController,
                              enabled: !_submitting,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Longitudine',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '4. Racconta l’invito',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Spiega che atmosfera vuoi creare, cosa ti va di condividere e perche qualcuno dovrebbe unirsi volentieri.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.brown.withValues(alpha: 0.72),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
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
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.send_rounded),
              label:
                  Text(_submitting ? 'Sto pubblicando...' : 'Pubblica offerta'),
            ),
          ],
        ),
      ),
    );
  }

  double? get _parsedLatitude => _tryParseCoordinate(_latitudeController.text);

  double? get _parsedLongitude =>
      _tryParseCoordinate(_longitudeController.text);

  LatLng get _mapTarget {
    final latitude = _parsedLatitude;
    final longitude = _parsedLongitude;
    if (latitude == null || longitude == null) {
      return _fallbackMapTarget;
    }
    return LatLng(latitude, longitude);
  }

  Set<Marker> get _mapMarkers {
    final latitude = _parsedLatitude;
    final longitude = _parsedLongitude;
    if (latitude == null || longitude == null) {
      return const <Marker>{};
    }

    return {
      Marker(
        markerId: const MarkerId('selected_offer_location'),
        position: LatLng(latitude, longitude),
        infoWindow: InfoWindow(
          title: _localeController.text.trim().isEmpty
              ? 'Posizione selezionata'
              : _localeController.text.trim(),
          snippet: _addressController.text.trim().isEmpty
              ? 'Tavolo in preparazione'
              : _addressController.text.trim(),
        ),
      ),
    };
  }

  DateTime? get _combinedDateTime {
    if (_selectedDate == null || _selectedTime == null) {
      return null;
    }
    return DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
  }

  double? _tryParseCoordinate(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('it'),
    );
    if (pickedDate == null || !mounted) {
      return;
    }

    setState(() => _selectedDate = pickedDate);
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime ??
          TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (pickedTime == null || !mounted) {
      return;
    }

    setState(() => _selectedTime = pickedTime);
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime ??
          TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (pickedTime == null) {
      return;
    }

    setState(() {
      _selectedDate = pickedDate;
      _selectedTime = pickedTime;
    });
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (image == null) {
      return;
    }
    setState(() => _pickedImage = image);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Attiva la posizione del telefono e riprova.');
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

      _latitudeController.text = position.latitude.toStringAsFixed(6);
      _longitudeController.text = position.longitude.toStringAsFixed(6);
      setState(() => _showManualCoordinates = false);
      if (AppConfig.googleMapsEnabled) {
        await _animateMapTo(
          LatLng(position.latitude, position.longitude),
        );
      }
      _showMessage(
        AppConfig.googleMapsEnabled
            ? 'Posizione acquisita e mostrata sulla mappa.'
            : 'Posizione acquisita correttamente.',
      );
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _setLocationFromMap(LatLng position) {
    _latitudeController.text = position.latitude.toStringAsFixed(6);
    _longitudeController.text = position.longitude.toStringAsFixed(6);
    setState(() => _showManualCoordinates = false);
    _showMessage('Posizione aggiornata dalla mappa.');
  }

  void _handleMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (!_mapControllerCompleter.isCompleted) {
      _mapControllerCompleter.complete(controller);
    }
  }

  Future<void> _animateMapTo(LatLng target) async {
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
        CameraPosition(target: target, zoom: 16),
      ),
    );
  }

  Future<void> _submit() async {
    final selectedDateTime = _combinedDateTime;
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (selectedDateTime == null) {
      _showMessage('Seleziona data e ora.');
      return;
    }
    final parsedLatitude = _parsedLatitude;
    final parsedLongitude = _parsedLongitude;
    if (parsedLatitude == null || parsedLongitude == null) {
      _showMessage(
        'Acquisisci la posizione del telefono oppure inserisci coordinate valide.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final message = await widget.authController.apiClient.createOffer(
        mealType: _mealType,
        localeName: _localeController.text.trim(),
        address: _addressController.text.trim(),
        latitude: parsedLatitude.toString(),
        longitude: parsedLongitude.toString(),
        totalSeats: _totalSeats,
        dateTime: selectedDateTime,
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
      _formKey.currentState!.reset();
      _localeController.clear();
      _addressController.clear();
      _latitudeController.clear();
      _longitudeController.clear();
      _descriptionController.clear();
      setState(() {
        _mealType = 'colazione';
        _totalSeats = 2;
        _selectedDate = null;
        _selectedTime = null;
        _pickedImage = null;
        _showManualCoordinates = false;
      });
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _mealLabel(String value) {
    switch (value) {
      case 'colazione':
        return 'Colazione';
      case 'pranzo':
        return 'Pranzo';
      case 'cena':
        return 'Cena';
      default:
        return value;
    }
  }
}

class _GoogleMapsPreviewCard extends StatelessWidget {
  const _GoogleMapsPreviewCard({
    required this.target,
    required this.markers,
    required this.enabled,
    required this.onMapCreated,
    required this.onLongPress,
  });

  final LatLng target;
  final Set<Marker> markers;
  final bool enabled;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<LatLng>? onLongPress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 240,
        child: GoogleMap(
          onMapCreated: onMapCreated,
          initialCameraPosition: CameraPosition(
            target: target,
            zoom: markers.isEmpty ? 11 : 15,
          ),
          markers: markers,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          myLocationEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          onLongPress: enabled ? onLongPress : null,
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
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF6EA),
            Color(0xFFF6EEE4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.map_rounded,
                  color: AppTheme.orange,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Base Google Maps pronta',
                  style: TextStyle(
                    color: AppTheme.brown,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Qui entrera` la mappa vera del locale con tocco lungo per scegliere il punto. Per ora restano attivi posizione del telefono e coordinate manuali.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.brown.withValues(alpha: 0.76),
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryPill(
                icon: Icons.map_outlined,
                label: 'Google Maps',
              ),
              _SummaryPill(
                icon: Icons.photo_library_outlined,
                label: 'Foto locale',
              ),
              _SummaryPill(
                icon: Icons.call_outlined,
                label: 'Telefono locale',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.mist,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.orange),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.brown,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineInfoBanner extends StatelessWidget {
  const _InlineInfoBanner({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.peach.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.brown,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
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
  final String currentValue;
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

    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: onSelected == null ? null : (_) => onSelected!(value),
      backgroundColor: Colors.white,
      selectedColor: color.withValues(alpha: 0.16),
      side: BorderSide(color: color.withValues(alpha: 0.36)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      labelStyle: TextStyle(
        color: selected ? color : AppTheme.brown,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
