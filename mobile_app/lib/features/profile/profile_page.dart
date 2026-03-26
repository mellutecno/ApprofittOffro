import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.authController});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    final user = authController.currentUser;
    final apiClient = authController.apiClient;
    final photoUrl = user != null && user.photoFilename.isNotEmpty
        ? apiClient.buildUploadUrl(user.photoFilename)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Su di me')),
      body: user == null
          ? const Center(child: Text('Utente non disponibile.'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 46,
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null ? const Icon(Icons.person, size: 42) : null,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    user.nome,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Center(child: Text('${user.etaDisplay} anni • ${user.city}')),
                const SizedBox(height: 24),
                _InfoCard(
                  title: 'Email',
                  value: user.email,
                ),
                _InfoCard(
                  title: 'Cibi preferiti',
                  value: user.preferredFoods.isNotEmpty ? user.preferredFoods : 'Non ancora indicati',
                ),
                _InfoCard(
                  title: 'Intolleranze',
                  value: user.intolerances.isNotEmpty ? user.intolerances : 'Nessuna indicata',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifica profilo Flutter in arrivo'),
                ),
              ],
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

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
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(value),
          ],
        ),
      ),
    );
  }
}
