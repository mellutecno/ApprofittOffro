import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../auth/auth_controller.dart';
import 'chat_page.dart';

class ChatInboxPage extends StatefulWidget {
  const ChatInboxPage({
    super.key,
    required this.authController,
  });

  final AuthController authController;

  @override
  State<ChatInboxPage> createState() => _ChatInboxPageState();
}

class _ChatInboxPageState extends State<ChatInboxPage> {
  final Map<int, Future<_PeerProfile?>> _peerLookups =
      <int, Future<_PeerProfile?>>{};
  bool _loading = true;
  String? _error;
  List<_ChatListItem> _items = const [];

  bool get _isDarkPalette => AppTheme.useMusicAiPalette;
  Color get _bgTop =>
      _isDarkPalette ? const Color(0xFF070A11) : const Color(0xFFFFFBF6);
  Color get _bgBottom =>
      _isDarkPalette ? const Color(0xFF12192A) : const Color(0xFFF6E8DA);
  Color get _tileTextPrimary =>
      _isDarkPalette ? const Color(0xFFEAF0FF) : AppTheme.brown;
  Color get _tileTextSecondary =>
      _isDarkPalette ? const Color(0xFFB8C3E5) : const Color(0xFF6E5A4E);

  @override
  void initState() {
    super.initState();
    unawaited(_loadInbox());
  }

  Future<void> _loadInbox() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final payload = await widget.authController.apiClient.fetchChatInbox();
      final parsed = payload.map(_ChatListItem.fromJson).toList()
        ..sort((a, b) {
          final aTime = a.lastMessageTime?.millisecondsSinceEpoch ?? 0;
          final bTime = b.lastMessageTime?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime);
        });

      if (!mounted) {
        return;
      }
      setState(() {
        _items = parsed;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<_PeerProfile?> _fetchPeer(int userId) {
    return _peerLookups.putIfAbsent(userId, () async {
      try {
        final profile =
            await widget.authController.apiClient.fetchPublicUser(userId);
        return _PeerProfile(
          displayName: profile.user.nome.trim(),
          photoFilename: profile.user.photoFilename.trim(),
        );
      } catch (_) {
        return null;
      }
    });
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '';
    }
    final local = value.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) {
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  Future<void> _openChat({
    required _ChatListItem item,
    required String displayName,
    required String photoFilename,
  }) async {
    final currentUser = widget.authController.currentUser;
    if (currentUser == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessione non valida. Rientra e riprova.'),
        ),
      );
      return;
    }
    if (item.offerId <= 0 || item.otherUserId <= 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questa chat non e disponibile.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          apiClient: widget.authController.apiClient,
          offerId: item.offerId.toString(),
          currentUserId: currentUser.id.toString(),
          currentUserName: currentUser.nome,
          currentUserPhotoFilename: currentUser.photoFilename,
          otherUserId: item.otherUserId.toString(),
          otherUserName: displayName,
          otherUserPhotoFilename: photoFilename,
        ),
      ),
    );

    unawaited(_loadInbox());
  }

  Widget _buildChatTile({
    required _ChatListItem item,
    required String displayName,
    required String photoFilename,
  }) {
    final apiClient = widget.authController.apiClient;
    final photoUrl = photoFilename.trim().isEmpty
        ? null
        : apiClient.buildUploadUrl(photoFilename.trim());
    final subtitle =
        item.lastMessage.isEmpty ? 'Nessun messaggio ancora' : item.lastMessage;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openChat(
          item: item,
          displayName: displayName,
          photoFilename: photoFilename,
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.cardBorder),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isDarkPalette
                  ? const [Color(0xFF141D31), Color(0xFF1A2640)]
                  : const [Color(0xFFFFF9F2), Color(0xFFF4E1CD)],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.peach.withValues(alpha: 0.5),
                backgroundImage:
                    photoUrl == null ? null : NetworkImage(photoUrl),
                child: photoUrl == null
                    ? Icon(
                        Icons.person_rounded,
                        color: _isDarkPalette
                            ? const Color(0xFFEAF0FF)
                            : AppTheme.brown,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _tileTextPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _tileTextSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDateTime(item.lastMessageTime),
                style: TextStyle(
                  color: _tileTextSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResolvedChatTile(_ChatListItem item) {
    final needsLookup = item.otherUserName.trim().isEmpty ||
        item.otherUserName.trim() == 'Utente';
    if (!needsLookup || item.otherUserId <= 0) {
      return _buildChatTile(
        item: item,
        displayName: item.otherUserName.trim().isEmpty
            ? 'Utente'
            : item.otherUserName.trim(),
        photoFilename: item.otherUserPhotoFilename,
      );
    }

    return FutureBuilder<_PeerProfile?>(
      future: _fetchPeer(item.otherUserId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final displayName = (profile?.displayName.trim().isNotEmpty ?? false)
            ? profile!.displayName.trim()
            : 'Utente';
        final photoFilename =
            (profile?.photoFilename.trim().isNotEmpty ?? false)
                ? profile!.photoFilename.trim()
                : item.otherUserPhotoFilename;
        return _buildChatTile(
          item: item,
          displayName: displayName,
          photoFilename: photoFilename,
        );
      },
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: const [
          SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          const SizedBox(height: 120),
          Text(
            'Errore nel caricamento chat: $_error',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.brown,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.35,
            ),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: const [
          SizedBox(height: 100),
          Text(
            'Nessuna chat attiva.\nQuando partecipi a un evento e apri la chat, la trovi qui.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.brown,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.35,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildResolvedChatTile(_items[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgBottom],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: BrandWordmark(
              height: 42,
              alignment: Alignment.center,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: BrandHeroCard(
              eyebrow: 'CONVERSAZIONI',
              title: 'Messaggi attivi',
              subtitle:
                  'Qui trovi solo le persone con cui hai gia aperto una chat da un evento confermato.',
              centered: true,
              footer: Text(
                'Apri una conversazione e continua da qui, senza tornare all\'evento. Le chat inattive si cancellano automaticamente dopo 30 giorni.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.brown,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadInbox,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatListItem {
  const _ChatListItem({
    required this.chatId,
    required this.offerId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserPhotoFilename,
    required this.lastMessage,
    required this.lastMessageTime,
  });

  final String chatId;
  final int offerId;
  final int otherUserId;
  final String otherUserName;
  final String otherUserPhotoFilename;
  final String lastMessage;
  final DateTime? lastMessageTime;

  factory _ChatListItem.fromJson(Map<String, dynamic> json) {
    final rawTime = (json['last_message_time'] ?? '').toString().trim();
    return _ChatListItem(
      chatId: (json['chat_id'] ?? '').toString(),
      offerId: (json['offer_id'] as num?)?.toInt() ??
          int.tryParse('${json['offer_id'] ?? ''}') ??
          0,
      otherUserId: (json['other_user_id'] as num?)?.toInt() ??
          int.tryParse('${json['other_user_id'] ?? ''}') ??
          0,
      otherUserName: (json['other_user_name'] ?? '').toString(),
      otherUserPhotoFilename:
          (json['other_user_photo_filename'] ?? '').toString(),
      lastMessage: (json['last_message'] ?? '').toString(),
      lastMessageTime: rawTime.isEmpty
          ? null
          : DateTime.tryParse(rawTime.replaceFirst('Z', '+00:00'))?.toLocal(),
    );
  }
}

class _PeerProfile {
  const _PeerProfile({
    required this.displayName,
    required this.photoFilename,
  });

  final String displayName;
  final String photoFilename;
}
