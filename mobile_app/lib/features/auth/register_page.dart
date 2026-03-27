import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import 'auth_controller.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _etaController = TextEditingController();
  final _cittaController = TextEditingController();

  List<XFile> _selectedPhotos = const [];
  bool _isSaving = false;
  bool _isLocating = false;
  double? _latitude;
  double? _longitude;

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _telefonoController.dispose();
    _etaController.dispose();
    _cittaController.dispose();
    super.dispose();
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

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posizione acquisita correttamente.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prima devi acquisire la posizione del telefono.'),
        ),
      );
      return;
    }
    if (_selectedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carica almeno una foto profilo.')),
      );
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
        citta: _cittaController.text.trim(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationReady = _latitude != null && _longitude != null;

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
                        title:
                            'Crea il tuo profilo utenti direttamente dal telefono.',
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
                                    labelText: 'Password'),
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
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _cittaController,
                                decoration: const InputDecoration(
                                  labelText: 'Citta o zona',
                                ),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _isLocating || _isSaving
                                    ? null
                                    : _useCurrentLocation,
                                icon: const Icon(Icons.my_location_rounded),
                                label: Text(
                                  locationReady
                                      ? 'Posizione acquisita'
                                      : 'Usa la posizione del telefono',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                locationReady
                                    ? 'Coordinate pronte: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                                    : 'Per registrarti serve la posizione attuale.',
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
}
