import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'public_profile_page.dart';

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
          : RefreshIndicator(
              onRefresh: authController.refreshCurrentUser,
              child: ListView(
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
                  Center(child: Text('${user.etaDisplay} anni - ${user.city}')),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '${user.ratingAverage.toStringAsFixed(1)} ★ su ${user.ratingCount} recensioni',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'Offerte',
                          value: user.offersCount.toString(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          label: 'Recuperi',
                          value: user.claimsCount.toString(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          label: 'Follower',
                          value: user.followersCount.toString(),
                        ),
                      ),
                    ],
                  ),
                  if (user.galleryFilenames.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Le tue foto',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 116,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: user.galleryFilenames.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final imageUrl = apiClient.buildUploadUrl(user.galleryFilenames[index]);
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _InfoCard(title: 'Email', value: user.email),
                  _InfoCard(
                    title: 'Numero di telefono',
                    value: user.phoneNumber.isNotEmpty ? user.phoneNumber : 'Non indicato',
                  ),
                  if (user.bio.isNotEmpty) _InfoCard(title: 'Bio', value: user.bio),
                  _InfoCard(
                    title: 'Cibi preferiti',
                    value: user.preferredFoods.isNotEmpty ? user.preferredFoods : 'Non ancora indicati',
                  ),
                  _InfoCard(
                    title: 'Intolleranze',
                    value: user.intolerances.isNotEmpty ? user.intolerances : 'Nessuna indicata',
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Chi ti segue',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  if (user.followers.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Per ora non hai ancora follower.'),
                      ),
                    )
                  else
                    ...user.followers.map(
                      (follower) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage: follower.photoFilename.isNotEmpty
                                ? NetworkImage(apiClient.buildUploadUrl(follower.photoFilename))
                                : null,
                            child: follower.photoFilename.isEmpty
                                ? const Icon(Icons.person_outline)
                                : null,
                          ),
                          title: Text(follower.nome),
                          subtitle: Text('${follower.etaDisplay} anni - ${follower.cityLabel}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PublicProfilePage(
                                  apiClient: apiClient,
                                  userId: follower.id,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifica profilo Flutter in arrivo'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center),
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
