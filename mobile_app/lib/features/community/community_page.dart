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
  static const List<MapEntry<String, String>> _genderFilters = [
    MapEntry('', 'Tutti'),
    MapEntry('maschio', 'Maschi'),
    MapEntry('femmina', 'Femmine'),
  ];
  bool _isDistanceCardExpanded = false;
  double? _distanceDraftKm;

  int _normalizeDistanceKm(int rawValue) {
    return rawValue.clamp(
      CommunityController.minRadiusKm,
      CommunityController.maxRadiusKm,
    );
  }

  @override
  void initState() {
    super.initState();
    final currentRadius = _normalizeDistanceKm(
      widget.communityController.selectedRadiusKm,
    );
    widget.communityController.initializeRadiusKm(currentRadius);
    _distanceDraftKm = currentRadius.toDouble();
    if (widget.communityController.people.isEmpty &&
        !widget.communityController.isLoading) {
      widget.communityController.loadPeople();
    }
  }

  Future<void> _saveDistancePreference() async {
    final selectedKm = _normalizeDistanceKm(
      (_distanceDraftKm ?? widget.communityController.selectedRadiusKm.toDouble())
          .round(),
    );
    if (selectedKm == widget.communityController.selectedRadiusKm) {
      return;
    }

    await widget.communityController.selectRadiusKm(selectedKm);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ora vedi utenti entro $selectedKm km.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.communityController,
      builder: (context, _) {
        final distanceDraft = _distanceDraftKm ??
            widget.communityController.selectedRadiusKm.toDouble();
        final distanceValue = _normalizeDistanceKm(distanceDraft.round());
        return RefreshIndicator(
          onRefresh: () async {
            await widget.communityController.loadPeople();
            await widget.authController.refreshCurrentUser();
          },
          child: CustomScrollView(
            slivers: [
              const SliverAppBar(
                pinned: true,
                title: BrandWordmark(height: 42, alignment: Alignment.center),
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
                          'Filtra la community',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.brown,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CommunityDistanceControl(
                          valueKm: distanceValue,
                          isExpanded: _isDistanceCardExpanded,
                          isSaving: widget.communityController.isLoading,
                          onChanged: (value) {
                            setState(() => _distanceDraftKm = value);
                          },
                          onToggle: () {
                            setState(
                              () => _isDistanceCardExpanded =
                                  !_isDistanceCardExpanded,
                            );
                          },
                          onSave: _saveDistancePreference,
                          isDirty: distanceValue !=
                              widget.communityController.selectedRadiusKm,
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Column(
                            children: [
                              _CommunityResultCount(
                                count: widget.communityController.people.length,
                                isLoading: widget.communityController.isLoading,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _CommunityFilterTile(
                                      label: 'Eta',
                                      value: widget.communityController
                                          .selectedAgeRange,
                                      options: _ageRanges,
                                      onChanged: (value) {
                                        widget.communityController
                                            .selectAgeRange(value);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _CommunityFilterTile(
                                      label: 'Sesso',
                                      value: widget
                                          .communityController.selectedGender,
                                      options: _genderFilters,
                                      onChanged: (value) {
                                        widget.communityController
                                            .selectGender(value);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nei risultati trovi sempre gli altri profili della community, mai il tuo.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          AppTheme.brown.withValues(alpha: 0.72),
                                      fontWeight: FontWeight.w600,
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

class _CommunityResultCount extends StatelessWidget {
  const _CommunityResultCount({
    required this.count,
    required this.isLoading,
  });

  final int count;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final label = isLoading
        ? 'Sto cercando utenti nella community...'
        : (count == 1
            ? '1 utente nella community'
            : '$count utenti nella community');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.groups_2_rounded,
            color: isLoading ? AppTheme.brown : AppTheme.orange,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.espresso,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityFilterTile extends StatelessWidget {
  const _CommunityFilterTile({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<MapEntry<String, String>> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.brown.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFE7DBD0),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD1BCAA)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              alignment: Alignment.center,
              borderRadius: BorderRadius.circular(18),
              dropdownColor: AppTheme.paper,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTheme.brown,
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.brown,
                    fontWeight: FontWeight.w700,
                  ),
              items: options
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.key,
                      child: Text(
                        item.value,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (selected) {
                if (selected == null) {
                  return;
                }
                onChanged(selected);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CommunityDistanceControl extends StatelessWidget {
  const _CommunityDistanceControl({
    required this.valueKm,
    required this.isExpanded,
    required this.isSaving,
    required this.onChanged,
    required this.onToggle,
    required this.onSave,
    required this.isDirty,
  });

  final int valueKm;
  final bool isExpanded;
  final bool isSaving;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggle;
  final Future<void> Function() onSave;
  final bool isDirty;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_alt_rounded,
                    color: AppTheme.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Utenti nel raggio di $valueKm km',
                      style: const TextStyle(
                        color: AppTheme.espresso,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.brown,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.orange,
                inactiveTrackColor: AppTheme.cardBorder,
                thumbColor: AppTheme.orange,
                overlayColor: AppTheme.orange.withValues(alpha: 0.14),
                valueIndicatorColor: AppTheme.orange,
                valueIndicatorTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Slider(
                min: CommunityController.minRadiusKm.toDouble(),
                max: CommunityController.maxRadiusKm.toDouble(),
                divisions: ((CommunityController.maxRadiusKm -
                        CommunityController.minRadiusKm) ~/
                    5),
                value: valueKm
                    .clamp(
                      CommunityController.minRadiusKm,
                      CommunityController.maxRadiusKm,
                    )
                    .toDouble(),
                label: '$valueKm km',
                onChanged: isSaving ? null : onChanged,
              ),
            ),
            Row(
              children: [
                Text(
                  '${CommunityController.minRadiusKm} km',
                  style: TextStyle(
                    color: AppTheme.brown.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${CommunityController.maxRadiusKm} km',
                  style: TextStyle(
                    color: AppTheme.brown.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: isSaving || !isDirty ? null : onSave,
              child: Text(
                isSaving
                    ? 'Aggiornamento...'
                    : (isDirty ? 'Applica distanza' : 'Distanza aggiornata'),
              ),
            ),
          ],
        ],
      ),
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
