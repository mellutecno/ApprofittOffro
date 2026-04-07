import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/admin_dashboard.dart';
import '../auth/auth_controller.dart';

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

  Widget _buildAvatar(AdminEditableUser user) {
    final filename = user.photoFilename.trim();
    final imageProvider = filename.isEmpty
        ? null
        : NetworkImage(
            widget.authController.apiClient.buildUploadUrl(filename));
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
                                            'Le foto e la posizione restano quelle gia presenti sul profilo. Qui modifichi solo i dati testuali e lo stato di verifica.',
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
