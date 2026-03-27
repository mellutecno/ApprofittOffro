import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import '../../models/place_candidate.dart';
import 'auth_controller.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static const LatLng _fallbackMapTarget = LatLng(45.070339, 7.686864);

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final Completer<GoogleMapController> _mapControllerCompleter = Completer();

  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _etaController = TextEditingController();
  final _addressController = TextEditingController();

  List<XFile> _selectedPhotos = const [];
  bool _isSaving = false;
  bool _isLocating = false;
  bool _loadingNearbyPlaces = false;
  bool _initialLocationRequested = false;
  bool _mapReady = !AppConfig.googleMapsEnabled;
  GoogleMapController? _mapController;
  LatLng _currentMapCenter = _fallbackMapTarget;
  double? _latitude;
  double? _longitude;
  String? _selectedPlaceId;
  String _selectedPlaceName = '';
  List<PlaceCandidate> _nearbyPlaces = const [];
  Set<Marker> _markers = const <Marker>{};

  @override
  void initState() {
    super.initState();
    if (AppConfig.googleMapsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_bootstrapCurrentLocation());
      });
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _telefonoController.dispose();
    _etaController.dispose();
    _addressController.dispose();
    _mapController?.dispose();
    super.dispose();
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
    setState(() => _mapReady = true);
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
        _mapReady = true;
      });
      await _animateMapTo(target, zoom: 16.1);
      await _refreshNearbyPlaces(target: target);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _mapReady = true);
      if (!silent) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  Future<void> _refreshNearbyPlaces({LatLng? target}) async {
    if (_loadingNearbyPlaces) {
      return;
    }

    final center = target ?? _currentMapCenter;
    setState(() => _loadingNearbyPlaces = true);
    try {
      final places = await widget.authController.apiClient.fetchNearbyPlaces(
        latitude: center.latitude,
        longitude: center.longitude,
      );
      if (!mounted) {
        return;
      }

      _nearbyPlaces = places;
      await _rebuildMarkers();
    } catch (error) {
      if (mounted) {
        _showMessage('Non riesco a caricare i locali vicini.');
      }
    } finally {
      if (mounted) {
        setState(() => _loadingNearbyPlaces = false);
      }
    }
  }

  Future<void> _rebuildMarkers() async {
    final markers = _nearbyPlaces.map((place) {
      final selected = _selectedPlaceId == place.id;
      return Marker(
        markerId: MarkerId(place.id),
        position: LatLng(place.latitude, place.longitude),
        infoWindow: InfoWindow(
          title: place.name,
          snippet: place.address,
        ),
        icon: selected
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)
            : BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
        onTap: () => _selectPlace(place),
      );
    }).toSet();

    setState(() => _markers = markers);
  }

  Future<void> _selectPlace(PlaceCandidate place) async {
    setState(() {
      _selectedPlaceId = place.id;
      _selectedPlaceName = place.name;
      _addressController.text = place.address;
      _latitude = place.latitude;
      _longitude = place.longitude;
      _currentMapCenter = LatLng(place.latitude, place.longitude);
    });
    await _rebuildMarkers();
    await _animateMapTo(_currentMapCenter, zoom: 17);
  }

  Future<void> _animateMapTo(LatLng target, {double zoom = 15.6}) async {
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

  void _handleMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (!_mapControllerCompleter.isCompleted) {
      _mapControllerCompleter.complete(controller);
    }
    unawaited(_animateMapTo(_currentMapCenter));
  }

  Future<void> _pickPhotos() async {
    final photos = await _picker.pickMultiImage(imageQuality: 86);
    if (!mounted || photos.isEmpty) {
      return;
    }

    final limited = photos.take(5).toList(growable: false);
    setState(() => _selectedPhotos = limited);

    if (photos.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tengo solo le prime 5 foto selezionate.'),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_latitude == null || _longitude == null) {
      _showMessage('Scegli il tuo indirizzo dalla mappa.');
      return;
    }
    if (_selectedPhotos.isEmpty) {
      _showMessage('Carica almeno una foto profilo.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final message = await widget.authController.apiClient.registerUser(
        nome: _nomeController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        confermaPassword: _confirmController.text,
        numeroTelefono: _telefonoController.text.trim(),
        eta: _etaController.text.trim(),
        latitude: _latitude!.toString(),
        longitude: _longitude!.toString(),
        citta: _addressController.text.trim(),
        photoPaths: _selectedPhotos.map((photo) => photo.path).toList(),
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Registrazione completata'),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ho capito'),
            ),
          ],
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const BrandHeroCard(
                        eyebrow: 'REGISTRAZIONE',
                        title: 'Crea il tuo profilo direttamente dal telefono.',
                        subtitle:
                            'La prima foto deve mostrare bene il volto. Le altre devono essere foto reali della stessa persona.',
                      ),
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _nomeController,
                                decoration:
                                    const InputDecoration(labelText: 'Nome'),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Inserisci il nome.'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration:
                                    const InputDecoration(labelText: 'Email'),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Inserisci l\'email.';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Email non valida.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                ),
                                validator: (value) =>
                                    value == null || value.length < 6
                                        ? 'Minimo 6 caratteri.'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _confirmController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Conferma password',
                                ),
                                validator: (value) =>
                                    value != _passwordController.text
                                        ? 'Le password non coincidono.'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _telefonoController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Numero di telefono',
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Inserisci il telefono.'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _etaController,
                                keyboardType: TextInputType.number,
                                decoration:
                                    const InputDecoration(labelText: 'Eta'),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Inserisci l\'eta.'
                                        : null,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Scegli il tuo indirizzo dalla mappa',
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Apri la mappa, spostati se serve e tocca un locale o un punto vicino per compilare l’indirizzo.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: AppTheme.brown
                                          .withValues(alpha: 0.74),
                                      height: 1.4,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 14),
                              _buildMapSection(),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _addressController,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Indirizzo',
                                  prefixIcon:
                                      const Icon(Icons.location_on_outlined),
                                  helperText: _selectedPlaceName.isEmpty
                                      ? 'Sceglilo direttamente dalla mappa'
                                      : _selectedPlaceName,
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Scegli l\'indirizzo dalla mappa.'
                                        : null,
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _isSaving ? null : _pickPhotos,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(
                                  _selectedPhotos.isEmpty
                                      ? 'Seleziona foto profilo'
                                      : 'Foto selezionate (${_selectedPhotos.length})',
                                ),
                              ),
                              if (_selectedPhotos.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _selectedPhotos
                                      .map(
                                        (photo) => ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: Image.file(
                                            File(photo.path),
                                            width: 80,
                                            height: 80,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _isSaving ? null : _submit,
                                child: _isSaving
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Registrati'),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _isSaving
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('Ho gia un account'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapSection() {
    if (!AppConfig.googleMapsEnabled) {
      return const _RegisterMapPlaceholder();
    }

    if (!_mapReady) {
      return const _RegisterMapLoading();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 280,
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: _handleMapCreated,
              initialCameraPosition: CameraPosition(
                target: _currentMapCenter,
                zoom: 15.6,
              ),
              markers: _markers,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
              myLocationEnabled: true,
              zoomControlsEnabled: false,
              compassEnabled: false,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              onCameraMove: (position) {
                _currentMapCenter = position.target;
              },
              onCameraIdle: () => unawaited(_refreshNearbyPlaces()),
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
                  onTap: _isSaving || _isLocating
                      ? null
                      : () => unawaited(_useCurrentLocation()),
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
            if (_isLocating || _loadingNearbyPlaces)
              const Positioned(
                bottom: 14,
                left: 14,
                child: _RegisterMapBusy(),
              ),
          ],
        ),
      ),
    );
  }
}

class _RegisterMapLoading extends StatelessWidget {
  const _RegisterMapLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
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

class _RegisterMapPlaceholder extends StatelessWidget {
  const _RegisterMapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.mist,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Center(
        child: Text(
          'Google Maps non e attivo in questa build.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppTheme.brown.withValues(alpha: 0.78),
              ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _RegisterMapBusy extends StatelessWidget {
  const _RegisterMapBusy();

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
