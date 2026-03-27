import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../auth/auth_controller.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    super.key,
    required this.authController,
    this.requireCompletion = false,
  });

  final AuthController authController;
  final bool requireCompletion;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  static const LatLng _fallbackMapTarget = LatLng(45.070339, 7.686864);
  static const List<DropdownMenuItem<String>> _genderItems = [
    DropdownMenuItem(value: 'maschio', child: Text('Maschio')),
    DropdownMenuItem(value: 'femmina', child: Text('Femmina')),
    DropdownMenuItem(
      value: 'non_dico',
      child: Text('Preferisco non dirlo'),
    ),
  ];

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final Completer<GoogleMapController> _mapControllerCompleter = Completer();

  late final TextEditingController _nomeController;
  late final TextEditingController _emailController;
  late final TextEditingController _etaController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _addressController;
  late final TextEditingController _bioController;
  late final TextEditingController _preferitiController;
  late final TextEditingController _intolleranzeController;

  List<XFile> _selectedPhotos = const [];
  bool _isSaving = false;
  bool _isLocating = false;
  bool _isResolvingAddress = false;
  bool _initialLocationRequested = false;
  bool _mapReady = !AppConfig.googleMapsEnabled;
  late String _selectedGender;

  GoogleMapController? _mapController;
  LatLng _currentMapCenter = _fallbackMapTarget;
  double? _latitude;
  double? _longitude;
  Set<Marker> _markers = const <Marker>{};

  @override
  void initState() {
    super.initState();
    final user = widget.authController.currentUser!;
    _nomeController = TextEditingController(text: user.nome);
    _emailController = TextEditingController(text: user.email);
    final shouldBlankAgeForOnboarding =
        widget.requireCompletion && user.etaDisplay.contains('-');
    _etaController = TextEditingController(
      text: shouldBlankAgeForOnboarding ? '' : user.etaDisplay,
    );
    _selectedGender = user.gender;
    _telefonoController = TextEditingController(text: user.phoneNumber);
    _addressController = TextEditingController(text: user.city);
    _bioController = TextEditingController(text: user.bio);
    _preferitiController = TextEditingController(text: user.preferredFoods);
    _intolleranzeController = TextEditingController(text: user.intolerances);
    _latitude = user.latitude;
    _longitude = user.longitude;

    if (AppConfig.googleMapsEnabled) {
      if (_latitude != null && _longitude != null) {
        _currentMapCenter = LatLng(_latitude!, _longitude!);
        _markers = {
          Marker(
            markerId: const MarkerId('profile-address'),
            position: _currentMapCenter,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
          ),
        };
        _mapReady = true;
        _initialLocationRequested = true;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_bootstrapCurrentLocation());
        });
      }
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _etaController.dispose();
    _telefonoController.dispose();
    _addressController.dispose();
    _bioController.dispose();
    _preferitiController.dispose();
    _intolleranzeController.dispose();
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
      await _setSelectedLocation(target, showErrors: !silent);
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

  Future<void> _setSelectedLocation(
    LatLng target, {
    bool showErrors = true,
  }) async {
    setState(() {
      _currentMapCenter = target;
      _latitude = target.latitude;
      _longitude = target.longitude;
      _markers = {
        Marker(
          markerId: const MarkerId('profile-address'),
          position: target,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      };
    });

    await _resolveAddress(target, showErrors: showErrors);
  }

  Future<void> _resolveAddress(
    LatLng target, {
    bool showErrors = true,
  }) async {
    setState(() => _isResolvingAddress = true);
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(
        target.latitude,
        target.longitude,
      );
      if (!mounted) {
        return;
      }

      final place = placemarks.isEmpty ? null : placemarks.first;
      final parts = <String>[
        if ((place?.street ?? '').trim().isNotEmpty) place!.street!.trim(),
        if ((place?.subLocality ?? '').trim().isNotEmpty)
          place!.subLocality!.trim(),
        if ((place?.locality ?? '').trim().isNotEmpty) place!.locality!.trim(),
        if ((place?.administrativeArea ?? '').trim().isNotEmpty)
          place!.administrativeArea!.trim(),
      ];
      _addressController.text = parts.isEmpty
          ? '${target.latitude.toStringAsFixed(5)}, ${target.longitude.toStringAsFixed(5)}'
          : parts.toSet().join(', ');
    } catch (_) {
      if (showErrors && mounted) {
        _showMessage('Non riesco a leggere l\'indirizzo da questa posizione.');
      }
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
      }
    }
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
    if (widget.requireCompletion && _selectedPhotos.isEmpty) {
      _showMessage('Carica almeno una foto reale prima di continuare.');
      return;
    }
    if (widget.requireCompletion && _bioController.text.trim().isEmpty) {
      _showMessage('Scrivi una bio prima di continuare.');
      return;
    }
    if (widget.requireCompletion &&
        _preferitiController.text.trim().isEmpty) {
      _showMessage('Inserisci i tuoi cibi preferiti prima di continuare.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.authController.apiClient.updateProfile(
        nome: _nomeController.text.trim(),
        email: _emailController.text.trim(),
        eta: _etaController.text.trim(),
        gender: _selectedGender,
        numeroTelefono: _telefonoController.text.trim(),
        citta: _addressController.text.trim(),
        latitude: _latitude!.toString(),
        longitude: _longitude!.toString(),
        preferredFoods: _preferitiController.text.trim(),
        intolerances: _intolleranzeController.text.trim(),
        bio: _bioController.text.trim(),
        photoPaths: _selectedPhotos.map((photo) => photo.path).toList(),
      );

      await widget.authController.refreshCurrentUser();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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
    final user = widget.authController.currentUser!;
    final busyMap = _isLocating || _isResolvingAddress;

    return WillPopScope(
      onWillPop: () async => !widget.requireCompletion,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.requireCompletion,
          title: const BrandWordmark(height: 24, alignment: Alignment.center),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.requireCompletion
                          ? 'Completa il tuo profilo'
                          : 'Modifica il tuo profilo',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.requireCompletion
                          ? 'Aggiungi foto reali, bio e preferenze per accedere alla community. Ti basta farlo una volta sola.'
                          : 'Puoi aggiornare dati, bio e galleria. Se cambi le foto, la prima deve mostrare bene il volto.',
                    ),
                    if (user.galleryFilenames.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: user.galleryFilenames
                            .take(5)
                            .map(
                              (filename) => ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  widget.authController.apiClient
                                      .buildUploadUrl(filename),
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SectionCard(
                title: 'Identita',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nomeController,
                      decoration: const InputDecoration(labelText: 'Nome'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Inserisci il nome.'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
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
                      controller: _etaController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Eta'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Inserisci l\'eta.'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedGender,
                      decoration: const InputDecoration(labelText: 'Sesso'),
                      items: _genderItems,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _selectedGender = value);
                      },
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
                              ? 'Inserisci il numero di telefono.'
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
                      'Tocca la mappa nel punto giusto oppure usa il GPS in alto a destra.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.brown.withValues(alpha: 0.74),
                            height: 1.4,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    _buildMapSection(busyMap),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _addressController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Indirizzo',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Scegli l\'indirizzo dalla mappa.'
                              : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Identikit alimentare',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _preferitiController,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Cibi preferiti'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _intolleranzeController,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Intolleranze'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bioController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Bio',
                        hintText:
                            'Racconta qualcosa di te, del tuo stile e di come vivi i pasti.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Foto profilo',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _pickPhotos,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        _selectedPhotos.isEmpty
                            ? 'Scegli fino a 5 foto'
                            : 'Cambia galleria (${_selectedPhotos.length})',
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
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(
                                  File(photo.path),
                                  width: 84,
                                  height: 84,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Se selezioni nuove foto, sostituiscono la galleria attuale.',
                    ),
                  ],
                ),
              ),
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
                    : Text(
                        widget.requireCompletion
                            ? 'Salva e continua'
                            : 'Salva modifiche',
                      ),
              ),
              const SizedBox(height: 24),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapSection(bool busyMap) {
    if (!AppConfig.googleMapsEnabled) {
      return const _ProfileMapPlaceholder();
    }

    if (!_mapReady) {
      return const _ProfileMapLoading();
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
              onTap: (target) => unawaited(_setSelectedLocation(target)),
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
            if (busyMap)
              const Positioned(
                bottom: 14,
                left: 14,
                child: _ProfileMapBusy(),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProfileMapLoading extends StatelessWidget {
  const _ProfileMapLoading();

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

class _ProfileMapPlaceholder extends StatelessWidget {
  const _ProfileMapPlaceholder();

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

class _ProfileMapBusy extends StatelessWidget {
  const _ProfileMapBusy();

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
