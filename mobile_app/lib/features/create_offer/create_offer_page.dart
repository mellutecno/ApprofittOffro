import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _localeController = TextEditingController();
  final _addressController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();

  String _mealType = 'colazione';
  int _totalSeats = 2;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  XFile? _pickedImage;
  bool _submitting = false;

  @override
  void dispose() {
    _localeController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDateTime = _combinedDateTime;

    return Scaffold(
      appBar: AppBar(title: const Text('Offri')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              'Pubblica un nuovo invito',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            const Text(
              'Per ora la scelta del locale e` manuale. La mappa Google arriva nel passo successivo.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _mealType,
              decoration: const InputDecoration(labelText: 'Tipo di pasto'),
              items: const [
                DropdownMenuItem(value: 'colazione', child: Text('Colazione')),
                DropdownMenuItem(value: 'pranzo', child: Text('Pranzo')),
                DropdownMenuItem(value: 'cena', child: Text('Cena')),
              ],
              onChanged: _submitting
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _mealType = value);
                    },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _localeController,
              enabled: !_submitting,
              decoration: const InputDecoration(labelText: 'Nome del locale'),
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
              decoration: const InputDecoration(labelText: 'Indirizzo'),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Inserisci l\'indirizzo.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latitudeController,
                    enabled: !_submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Latitudine'),
                    validator: _validateCoordinate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _longitudeController,
                    enabled: !_submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Longitudine'),
                    validator: _validateCoordinate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Temporaneo: per ora inseriamo le coordinate a mano. Le sostituiamo con Google Maps nella prossima fase.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              value: _totalSeats,
              decoration: const InputDecoration(labelText: 'Posti totali'),
              items: List.generate(
                8,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('${index + 1}'),
                ),
              ),
              onChanged: _submitting
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _totalSeats = value);
                    },
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickDateTime,
              icon: const Icon(Icons.schedule_outlined),
              label: Text(
                selectedDateTime == null
                    ? 'Scegli data e ora'
                    : DateFormat('dd/MM/yyyy - HH:mm').format(selectedDateTime),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionController,
              enabled: !_submitting,
              minLines: 4,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Descrizione',
                alignLabelWithHint: true,
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
                    : 'Foto selezionata: ${_pickedImage!.name}',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Sto pubblicando...' : 'Pubblica offerta'),
            ),
          ],
        ),
      ),
    );
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

  String? _validateCoordinate(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return 'Obbligatoria';
    }
    if (double.tryParse(raw.replaceAll(',', '.')) == null) {
      return 'Numero non valido';
    }
    return null;
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
      initialTime: _selectedTime ?? TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
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

  Future<void> _submit() async {
    final selectedDateTime = _combinedDateTime;
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (selectedDateTime == null) {
      _showMessage('Seleziona data e ora.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final message = await widget.authController.apiClient.createOffer(
        mealType: _mealType,
        localeName: _localeController.text.trim(),
        address: _addressController.text.trim(),
        latitude: _latitudeController.text.trim().replaceAll(',', '.'),
        longitude: _longitudeController.text.trim().replaceAll(',', '.'),
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
}
