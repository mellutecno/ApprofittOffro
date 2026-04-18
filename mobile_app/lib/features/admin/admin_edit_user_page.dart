import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../core/media/profile_photo_cropper.dart';
import '../../models/admin_dashboard.dart';
import '../auth/auth_controller.dart';
import 'dart:io';

class AdminEditUserPage extends StatefulWidget {
  const AdminEditUserPage({
    super.key,
    required this.authController,
    required this.userId,
  });

  final AuthController authController;
  final int userId;

  @override
  State<AdminEditUserPage> createState() => _AdminEditUserPageState();
}

class _AdminEditUserPageState extends State<AdminEditUserPage> {
  static const List<DropdownMenuItem<String>> _genderItems =
      <DropdownMenuItem<String>>[
    DropdownMenuItem(value: 'femmina', child: Text('Femmina')),
    DropdownMenuItem(value: 'maschio', child: Text('Maschio')),
    DropdownMenuItem(value: 'non_dico', child: Text('Non dichiarato')),
  ];

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late Future<AdminEditableUser> _userFuture;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _preferredFoodsController = TextEditingController();
  final _intolerancesController = TextEditingController();
  final _bioController = TextEditingController();

  int? _loadedUserId;
  String _selectedGender = 'non_dico';
  bool _isVerified = false;
  bool _isSaving = false;
  int _actionRadiusKm = 15;
  double? _latitude;
  double? _longitude;
  List<String> _existingGalleryFilenames = const <String>[];
  List<XFile> _selectedPhotos = const <XFile>[];

  @override
  void initState() {
    super.initState();
    _userFuture = widget.authController.apiClient.fetchAdminUser(widget.userId);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _preferredFoodsController.dispose();
    _intolerancesController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _hydrate(AdminEditableUser user) {
    if (_loadedUserId == user.id) {
      return;
    }
    _loadedUserId = user.id;
    _nameController.text = user.name;
    _emailController.text = user.email;
    _ageController.text = user.age;
    _actionRadiusKm = user.actionRadiusKm;
    _phoneController.text = user.phoneNumber;
    _cityController.text = user.city;
    _preferredFoodsController.text = user.preferredFoods;
    _intolerancesController.text = user.intolerances;
    _bioController.text = user.bio;
    _selectedGender = user.gender;
    _isVerified = user.isVerified;
    _latitude = user.latitude;
    _longitude = user.longitude;
    _existingGalleryFilenames = List<String>.from(user.galleryFilenames);
  }

  Future<void> _reload() async {
    final future =
        widget.authController.apiClient.fetchAdminUser(widget.userId);
    setState(() {
      _userFuture = future;
      _loadedUserId = null;
    });
    await future;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_totalPhotoCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tieni almeno una foto profilo.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final message = await widget.authController.apiClient.updateAdminUser(
        userId: widget.userId,
        nome: _nameController.text.trim(),
        email: _emailController.text.trim(),
        eta: _ageController.text.trim(),
        actionRadiusKm: _actionRadiusKm,
        gender: _selectedGender,
        verified: _isVerified,
        numeroTelefono: _phoneController.text.trim(),
        citta: _cityController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        preferredFoods: _preferredFoodsController.text.trim(),
        intolerances: _intolerancesController.text.trim(),
        bio: _bioController.text.trim(),
        existingGalleryFilenames: _existingGalleryFilenames,
        photoPaths: _selectedPhotos.map((photo) => photo.path).toList(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
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

  Future<ImageSource?> _pickPhotoSource() {
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

  Future<void> _pickPhotos() async {
    final source = await _pickPhotoSource();
    if (!mounted || source == null) {
      return;
    }

    final availableSlots = 5 - _existingGalleryFilenames.length;
    if (availableSlots <= 0) {
      _showMessage('Rimuovi prima una foto attuale per aggiungerne un\'altra.');
      return;
    }

    if (source == ImageSource.camera) {
      if (_totalPhotoCount >= 5) {
        _showMessage('Puoi caricare al massimo 5 foto profilo.');
        return;
      }

      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 86,
        maxWidth: 1800,
      );
      if (!mounted || photo == null) {
        return;
      }

      final croppedPhoto = await ProfilePhotoCropper.cropPickedPhoto(
        photo,
        title: 'Ritaglia foto profilo',
      );
      if (!mounted || croppedPhoto == null) {
        return;
      }

      setState(() {
        _selectedPhotos = [..._selectedPhotos, croppedPhoto];
      });
      return;
    }

    final photos = await _picker.pickMultiImage(imageQuality: 86);
    if (!mounted || photos.isEmpty) {
      return;
    }

    final croppedPhotos = await ProfilePhotoCropper.cropPickedPhotos(
      photos,
      titlePrefix: 'Ritaglia foto profilo',
    );
    if (!mounted || croppedPhotos.isEmpty) {
      return;
    }

    final combined = [..._selectedPhotos, ...croppedPhotos];
    final limited = combined.take(availableSlots).toList(growable: false);
    setState(() => _selectedPhotos = limited);

    if (combined.length > availableSlots) {
      _showMessage('Tengo solo le prime $availableSlots foto selezionate.');
    }
  }

  void _removeSelectedPhotoAt(int index) {
    if (index < 0 || index >= _selectedPhotos.length) {
      return;
    }
    setState(() {
      _selectedPhotos = [
        for (int i = 0; i < _selectedPhotos.length; i++)
          if (i != index) _selectedPhotos[i],
      ];
    });
  }

  void _removeExistingPhotoAt(int index) {
    if (index < 0 || index >= _existingGalleryFilenames.length) {
      return;
    }
    setState(() {
      _existingGalleryFilenames = [
        for (int i = 0; i < _existingGalleryFilenames.length; i++)
          if (i != index) _existingGalleryFilenames[i],
      ];
    });
  }

  Future<void> _cropExistingPhotoAt(int index) async {
    if (index < 0 || index >= _existingGalleryFilenames.length) {
      return;
    }

    try {
      final filename = _existingGalleryFilenames[index];
      final croppedPhoto = await ProfilePhotoCropper.cropExistingPhotoFromUrl(
        widget.authController.apiClient.buildUploadUrl(filename),
        title: index == 0
            ? 'Ritaglia foto principale'
            : 'Ritaglia foto ${index + 1}',
      );
      if (!mounted || croppedPhoto == null) {
        return;
      }

      setState(() {
        _existingGalleryFilenames = [
          for (int i = 0; i < _existingGalleryFilenames.length; i++)
            if (i != index) _existingGalleryFilenames[i],
        ];
        _selectedPhotos = [..._selectedPhotos, croppedPhoto];
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _cropSelectedPhotoAt(int index) async {
    if (index < 0 || index >= _selectedPhotos.length) {
      return;
    }

    final effectiveIndex = _existingGalleryFilenames.length + index;
    final croppedPhoto = await ProfilePhotoCropper.cropPickedPhoto(
      _selectedPhotos[index],
      title: effectiveIndex == 0
          ? 'Ritaglia foto principale'
          : 'Ritaglia foto ${effectiveIndex + 1}',
    );
    if (!mounted || croppedPhoto == null) {
      return;
    }

    setState(() {
      _selectedPhotos = [
        for (int i = 0; i < _selectedPhotos.length; i++)
          if (i == index) croppedPhoto else _selectedPhotos[i],
      ];
    });
  }

  int get _totalPhotoCount =>
      _existingGalleryFilenames.length + _selectedPhotos.length;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  ImageProvider<Object>? _buildCurrentAvatarProvider(AdminEditableUser user) {
    if (_existingGalleryFilenames.isNotEmpty) {
      return NetworkImage(
        widget.authController.apiClient
            .buildUploadUrl(_existingGalleryFilenames.first),
      );
    }
    if (_selectedPhotos.isNotEmpty) {
      return FileImage(File(_selectedPhotos.first.path));
    }
    final filename = user.photoFilename.trim();
    if (filename.isEmpty) {
      return null;
    }
    return NetworkImage(
        widget.authController.apiClient.buildUploadUrl(filename));
  }

  Widget _buildAvatar(AdminEditableUser user) {
    final imageProvider = _buildCurrentAvatarProvider(user);
    return CircleAvatar(
      radius: 34,
      backgroundColor: AppTheme.peach,
      backgroundImage: imageProvider,
      child: imageProvider == null
          ? Text(
              user.name.isEmpty ? '?' : user.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: AppTheme.brown,
                fontWeight: FontWeight.w900,
                fontSize: 28,
              ),
            )
          : null,
    );
  }

  Widget _buildExistingPhotoCard(String filename, int index) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              widget.authController.apiClient.buildUploadUrl(filename),
              width: 92,
              height: 92,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            index == 0 ? 'Foto principale' : 'Foto ${index + 1}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _cropExistingPhotoAt(index),
                tooltip: 'Ritaglia foto',
                icon: const Icon(Icons.crop_rounded, size: 20),
                color: AppTheme.brown,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () => _removeExistingPhotoAt(index),
                tooltip: 'Rimuovi foto',
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppTheme.brown,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPhotoCard(XFile photo, int index) {
    final effectiveIndex = _existingGalleryFilenames.length + index;
    return Container(
      width: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(photo.path),
              width: 92,
              height: 92,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            effectiveIndex == 0
                ? 'Foto principale'
                : 'Foto ${effectiveIndex + 1}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _cropSelectedPhotoAt(index),
                tooltip: 'Ritaglia foto',
                icon: const Icon(Icons.crop_rounded, size: 20),
                color: AppTheme.brown,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () => _removeSelectedPhotoAt(index),
                tooltip: 'Rimuovi foto',
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppTheme.brown,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminEditableUser>(
      future: _userFuture,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting && user == null;
        final error = snapshot.hasError ? snapshot.error.toString() : null;

        if (user != null) {
          _hydrate(user);
        }

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: kToolbarHeight,
            centerTitle: true,
            title: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: BrandWordmark(
                height: 42,
                alignment: Alignment.center,
              ),
            ),
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : error != null && user == null
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 80),
                        const Text(
                          'Non riesco a caricare questo utente adesso.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.brown,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.brown.withValues(alpha: 0.72),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Riprova'),
                        ),
                      ],
                    )
                  : SafeArea(
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Row(
                                  children: [
                                    _buildAvatar(user!),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: AppTheme.brown,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            user.email,
                                            style: TextStyle(
                                              color: AppTheme.brown.withValues(
                                                alpha: 0.72,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Da qui puoi correggere i dati utente, sistemare la galleria foto e aggiornare anche lo stato di verifica.',
                                            style: TextStyle(
                                              color: AppTheme.brown.withValues(
                                                alpha: 0.72,
                                              ),
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Foto profilo',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.brown,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: _isSaving ? null : _pickPhotos,
                                      icon: const Icon(
                                          Icons.add_a_photo_outlined),
                                      label: Text(
                                        _selectedPhotos.isEmpty
                                            ? 'Aggiungi o sostituisci foto'
                                            : 'Nuove foto selezionate (${_selectedPhotos.length})',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Totale foto attuali: $_totalPhotoCount di 5.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppTheme.brown.withValues(
                                              alpha: 0.7,
                                            ),
                                          ),
                                    ),
                                    if (_existingGalleryFilenames
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        'Foto attuali',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: List.generate(
                                          _existingGalleryFilenames.length,
                                          (index) => _buildExistingPhotoCard(
                                            _existingGalleryFilenames[index],
                                            index,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (_selectedPhotos.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        'Nuove foto da salvare',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: List.generate(
                                          _selectedPhotos.length,
                                          (index) => _buildSelectedPhotoCard(
                                            _selectedPhotos[index],
                                            index,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Text(
                                      'Puoi aggiungere, ritagliare o rimuovere foto prima di salvare. La prima restera la foto principale del profilo.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppTheme.brown.withValues(
                                              alpha: 0.72,
                                            ),
                                            height: 1.4,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _nameController,
                              enabled: !_isSaving,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nome o nickname',
                              ),
                              validator: (value) => (value ?? '').trim().isEmpty
                                  ? 'Inserisci un nome.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _emailController,
                              enabled: !_isSaving,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                              validator: (value) {
                                final trimmed = (value ?? '').trim();
                                if (trimmed.isEmpty || !trimmed.contains('@')) {
                                  return 'Inserisci un\'email valida.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _ageController,
                                    enabled: !_isSaving,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Eta',
                                    ),
                                    validator: (value) =>
                                        (value ?? '').trim().isEmpty
                                            ? 'Inserisci l\'eta.'
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _selectedGender,
                                    items: _genderItems,
                                    onChanged: _isSaving
                                        ? null
                                        : (value) => setState(
                                              () => _selectedGender =
                                                  value ?? 'non_dico',
                                            ),
                                    decoration: const InputDecoration(
                                      labelText: 'Sesso',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phoneController,
                              enabled: !_isSaving,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Telefono',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _cityController,
                              enabled: !_isSaving,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Citta / indirizzo',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _preferredFoodsController,
                              enabled: !_isSaving,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Cibi preferiti',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _intolerancesController,
                              enabled: !_isSaving,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Intolleranze',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _bioController,
                              enabled: !_isSaving,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Bio',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile.adaptive(
                              value: _isVerified,
                              onChanged: _isSaving
                                  ? null
                                  : (value) =>
                                      setState(() => _isVerified = value),
                              title: const Text('Utente verificato'),
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _isSaving ? null : _save,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                _isSaving
                                    ? 'Salvataggio in corso...'
                                    : 'Salva modifiche',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
        );
      },
    );
  }
}
