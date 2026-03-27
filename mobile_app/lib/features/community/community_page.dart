import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/user_preview.dart';
import '../auth/auth_controller.dart';
import '../profile/public_profile_page.dart';
import 'community_controller.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({
    super.key,
    required this.authController,
    required this.communityController,
  });

  final AuthController authController;
  final CommunityController communityController;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  static const List<MapEntry<String, String>> _ageRanges = [
    MapEntry('', 'Tutte le eta'),
    MapEntry('18-25', '18-25 anni'),
    MapEntry('26-35', '26-35 anni'),
    MapEntry('36-45', '36-45 anni'),
    MapEntry('46-55', '46-55 anni'),
    MapEntry('56-65', '56-65 anni'),
    MapEntry('65+', '65+ anni'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.communityController.people.isEmpty &&
        !widget.communityController.isLoading) {
      widget.communityController.loadPeople();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.communityController,
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: () async {
            await widget.communityController.loadPeople();
            await widget.authController.refreshCurrentUser();
          },
          child: CustomScrollView(
            slivers: [
              const SliverAppBar(
                floating: true,
                snap: true,
                title: BrandWordmark(height: 24, alignment: Alignment.center),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: BrandHeroCard(
                    eyebrow: 'COMMUNITY',
                    title: 'Persone da seguire davvero',
                    subtitle:
                        'Apri i profili, guarda le foto e costruisci il tuo giro nella community.',
                    centered: true,
                    footer: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Scegli la fascia di eta',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.brown,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                widget.communityController.selectedAgeRange,
                            decoration:
                                const InputDecoration(labelText: 'Seleziona'),
                            items: _ageRanges
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item.key,
                                    child: Text(item.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              widget.communityController
                                  .selectAgeRange(value ?? '');
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.communityController.isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (widget.communityController.errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.communityController.errorMessage!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else if (widget.communityController.people.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Per questa fascia non vedo ancora profili disponibili.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: widget.communityController.people.length,
                  itemBuilder: (context, index) {
                    final person = widget.communityController.people[index];
                    return _CommunityUserCard(
                      person: person,
                      authController: widget.authController,
                      onToggleFollow: () async {
                        final message = await widget.communityController
                            .toggleFollow(person);
                        await widget.authController.refreshCurrentUser();
                        if (!context.mounted || message == null) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(message)),
                        );
                      },
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }
}

class _CommunityUserCard extends StatelessWidget {
  const _CommunityUserCard({
    required this.person,
    required this.authController,
    required this.onToggleFollow,
  });

  final UserPreview person;
  final AuthController authController;
  final Future<void> Function() onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final imageUrl = person.photoFilename.isNotEmpty
        ? authController.apiClient.buildUploadUrl(person.photoFilename)
        : null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PublicProfilePage(
                apiClient: authController.apiClient,
                userId: person.id,
              ),
            ),
          );
          if (context.mounted) {
            await authController.refreshCurrentUser();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppTheme.sand,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundImage:
                          imageUrl != null ? NetworkImage(imageUrl) : null,
                      child: imageUrl == null ? const Icon(Icons.person) : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.nome,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text('${person.etaDisplay} anni - ${person.cityLabel}'),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              '${person.followersCount} follower',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.star_rounded,
                              size: 18,
                              color: Color(0xFFD49B00),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              person.ratingAverage.toStringAsFixed(1),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (person.bio.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  person.bio,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PublicProfilePage(
                              apiClient: authController.apiClient,
                              userId: person.id,
                            ),
                          ),
                        );
                        if (context.mounted) {
                          await authController.refreshCurrentUser();
                        }
                      },
                      child: const Text('Vedi profilo'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onToggleFollow,
                      child: Text(
                          person.isFollowing ? 'Non seguire piu' : 'Segui'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
