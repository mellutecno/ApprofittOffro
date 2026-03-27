import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../auth/auth_controller.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _nomeController;
  late final TextEditingController _emailController;
  late final TextEditingController _etaController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _cittaController;
  late final TextEditingController _bioController;
  late final TextEditingController _preferitiController;
  late final TextEditingController _intolleranzeController;

  List<XFile> _selectedPhotos = const [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.authController.currentUser!;
    _nomeController = TextEditingController(text: user.nome);
    _emailController = TextEditingController(text: user.email);
    _etaController = TextEditingController(text: user.etaDisplay);
    _telefonoController = TextEditingController(text: user.phoneNumber);
    _cittaController = TextEditingController(text: user.city);
    _bioController = TextEditingController(text: user.bio);
    _preferitiController = TextEditingController(text: user.preferredFoods);
    _intolleranzeController = TextEditingController(text: user.intolerances);
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _etaController.dispose();
    _telefonoController.dispose();
    _cittaController.dispose();
    _bioController.dispose();
    _preferitiController.dispose();
    _intolleranzeController.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final message = await widget.authController.apiClient.updateProfile(
        nome: _nomeController.text.trim(),
        email: _emailController.text.trim(),
        eta: _etaController.text.trim(),
        numeroTelefono: _telefonoController.text.trim(),
        citta: _cittaController.text.trim(),
        preferredFoods: _preferitiController.text.trim(),
        intolerances: _intolleranzeController.text.trim(),
        bio: _bioController.text.trim(),
        photoPaths: _selectedPhotos.map((photo) => photo.path).toList(),
      );

      await widget.authController.refreshCurrentUser();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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

  @override
  Widget build(BuildContext context) {
    final user = widget.authController.currentUser!;

    return Scaffold(
      appBar: AppBar(
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
                      'Modifica il tuo profilo',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Puoi aggiornare dati, bio e galleria. Se cambi le foto, la prima deve mostrare bene il volto.',
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
                    TextFormField(
                      controller: _telefonoController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Numero di telefono'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Inserisci il numero di telefono.'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cittaController,
                      decoration:
                          const InputDecoration(labelText: 'Citta o zona'),
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
                    : const Text('Salva modifiche'),
              ),
              const SizedBox(height: 24),
            ],
          ),
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
