import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/chat/chat_presence_tracker.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';

enum _ChatMenuAction {
  clearLocal,
  restoreLocal,
  clearForEveryone,
  blockUser,
  unblockUser,
}

class ChatPage extends StatefulWidget {
  final ApiClient apiClient;
  final String offerId;
  final String currentUserId;
  final String currentUserName;
  final String otherUserId;
  final String otherUserName;
  final String otherUserPhotoFilename;

  const ChatPage({
    super.key,
    required this.apiClient,
    required this.offerId,
    required this.currentUserId,
    this.currentUserName = 'Utente',
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhotoFilename = '',
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final Future<void> _chatAuthFuture;
  DateTime? _hiddenBefore;
  bool _blockedByMe = false;
  bool _blockedByOther = false;

  String get _chatVisibilityPrefsKey => 'chat_hidden_before_$_chatId';

  String get _chatId {
    final ids = [widget.currentUserId, widget.otherUserId]..sort();
    return '${widget.offerId}_${ids[0]}_${ids[1]}';
  }

  int? get _parsedOfferId => int.tryParse(widget.offerId);
  int? get _parsedOtherUserId => int.tryParse(widget.otherUserId);
  String? get _otherUserPhotoUrl {
    final filename = widget.otherUserPhotoFilename.trim();
    if (filename.isEmpty) {
      return null;
    }
    return widget.apiClient.buildUploadUrl(filename);
  }

  @override
  void initState() {
    super.initState();
    final offerId = _parsedOfferId;
    final otherUserId = _parsedOtherUserId;
    if (offerId != null && otherUserId != null) {
      ChatPresenceTracker.setActiveConversation(
        offerId: offerId,
        otherUserId: otherUserId,
      );
    }
    _chatAuthFuture = _bootstrapChat();
  }

  @override
  void dispose() {
    final offerId = _parsedOfferId;
    final otherUserId = _parsedOtherUserId;
    if (offerId != null && otherUserId != null) {
      ChatPresenceTracker.clearConversation(
        offerId: offerId,
        otherUserId: otherUserId,
      );
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureFirebaseAuth() async {
    if (Firebase.apps.isEmpty) {
      if (AppConfig.firebaseMessagingConfigured) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: AppConfig.firebaseApiKey,
            appId: AppConfig.firebaseAppId,
            messagingSenderId: AppConfig.firebaseMessagingSenderId,
            projectId: AppConfig.firebaseProjectId,
            storageBucket: AppConfig.firebaseStorageBucket.isEmpty
                ? null
                : AppConfig.firebaseStorageBucket,
          ),
        );
      } else {
        await Firebase.initializeApp();
      }
    }

    final auth = FirebaseAuth.instance;
    if (auth.currentUser?.uid != widget.currentUserId) {
      final token = await widget.apiClient.fetchFirebaseCustomToken();
      if (token.isEmpty) {
        throw Exception('Token chat non disponibile.');
      }
      await auth.signInWithCustomToken(token);
    }

    await _upsertChatMetadata();
  }

  Future<void> _bootstrapChat() async {
    await _loadChatVisibilityPreference();
    await _refreshBlockStatus();
    await _ensureFirebaseAuth();
  }

  Future<void> _loadChatVisibilityPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final rawValue = prefs.getInt(_chatVisibilityPrefsKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _hiddenBefore = rawValue == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(rawValue);
    });
  }

  Future<void> _refreshBlockStatus() async {
    final otherUserId = _parsedOtherUserId;
    if (otherUserId == null || otherUserId <= 0) {
      return;
    }

    try {
      final payload =
          await widget.apiClient.fetchChatBlockStatus(otherUserId: otherUserId);
      if (!mounted) {
        return;
      }
      setState(() {
        _blockedByMe = payload['blocked_by_me'] == true;
        _blockedByOther = payload['blocked_by_other'] == true;
      });
    } catch (_) {
      // Manteniamo lo stato precedente in caso di errore temporaneo.
    }
  }

  bool get _chatIsBlocked => _blockedByMe || _blockedByOther;

  Future<void> _clearChatScreenLocal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Svuotare questa chat?'),
        content: const Text(
          'I messaggi resteranno nel database ma verranno nascosti solo su questo dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Svuota schermo'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chatVisibilityPrefsKey, now.millisecondsSinceEpoch);
    if (!mounted) {
      return;
    }
    setState(() => _hiddenBefore = now);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Schermo chat pulito su questo dispositivo.')),
    );
  }

  Future<void> _restoreChatHistoryLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatVisibilityPrefsKey);
    if (!mounted) {
      return;
    }
    setState(() => _hiddenBefore = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cronologia chat ripristinata.')),
    );
  }

  bool _isMessageVisible(QueryDocumentSnapshot<Object?> doc) {
    final hiddenBefore = _hiddenBefore;
    if (hiddenBefore == null) {
      return true;
    }
    final payload = doc.data();
    if (payload is Map<String, dynamic>) {
      final timestamp = payload['timestamp'];
      if (timestamp is Timestamp) {
        return timestamp.toDate().isAfter(hiddenBefore);
      }
    }
    // Se il timestamp non e' ancora disponibile (serverTimestamp pending), tieni visibile.
    return true;
  }

  Future<void> _clearChatForEveryone() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Elimina chat per tutti?'),
        content: const Text(
          'Questa azione cancella tutti i messaggi per entrambi. Potrete comunque riscrivervi da zero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Elimina per entrambi'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final offerId = _parsedOfferId;
    final receiverId = _parsedOtherUserId;
    if (offerId == null || receiverId == null) {
      return;
    }

    try {
      await _chatAuthFuture;
      final chatDoc = FirebaseFirestore.instance.collection('chats').doc(_chatId);

      while (true) {
        final batchSlice = await chatDoc.collection('messages').limit(400).get();
        if (batchSlice.docs.isEmpty) {
          break;
        }
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in batchSlice.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      await chatDoc.set({
        'lastMessage': '',
        'lastSenderId': '',
        'lastSenderName': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'clearedAt': FieldValue.serverTimestamp(),
        'clearedById': widget.currentUserId.toString(),
        'clearedByName': widget.currentUserName,
      }, SetOptions(merge: true));

      try {
        await widget.apiClient.sendChatClearNotification(
          offerId: offerId,
          receiverId: receiverId,
        );
      } catch (_) {
        // Best effort: la chat resta comunque azzerata.
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat eliminata per entrambi. Potete riscrivervi da zero.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Non riesco a eliminare la chat adesso. Riprova tra poco.'),
        ),
      );
    }
  }

  Future<void> _toggleBlockUser({required bool block}) async {
    final otherUserId = _parsedOtherUserId;
    if (otherUserId == null || otherUserId <= 0) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(block ? 'Bloccare utente?' : 'Sbloccare utente?'),
        content: Text(
          block
              ? 'Non potrete più inviare messaggi finché non lo sblocchi.'
              : 'Dopo lo sblocco potrete tornare a scrivervi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(block ? 'Blocca' : 'Sblocca'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      if (block) {
        await widget.apiClient.blockChatUser(otherUserId: otherUserId);
      } else {
        await widget.apiClient.unblockChatUser(otherUserId: otherUserId);
      }
      await _refreshBlockStatus();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            block ? 'Utente bloccato in chat.' : 'Utente sbloccato in chat.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Operazione chat non riuscita. Riprova tra poco.'),
        ),
      );
    }
  }

  Future<void> _onMenuSelected(_ChatMenuAction action) async {
    switch (action) {
      case _ChatMenuAction.clearLocal:
        await _clearChatScreenLocal();
        break;
      case _ChatMenuAction.restoreLocal:
        await _restoreChatHistoryLocal();
        break;
      case _ChatMenuAction.clearForEveryone:
        await _clearChatForEveryone();
        break;
      case _ChatMenuAction.blockUser:
        await _toggleBlockUser(block: true);
        break;
      case _ChatMenuAction.unblockUser:
        await _toggleBlockUser(block: false);
        break;
    }
  }

  Future<void> _upsertChatMetadata() async {
    final parsedOfferId = int.tryParse(widget.offerId);
    if (parsedOfferId == null || parsedOfferId <= 0) {
      throw Exception('ID evento chat non valido.');
    }

    final chatDoc = FirebaseFirestore.instance.collection('chats').doc(_chatId);

    try {
      await chatDoc.update({
        'offerId': parsedOfferId,
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
      return;
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') {
        // Fallback: non bloccare la chat se i metadata legacy non sono allineati.
        return;
      }
    }

    await chatDoc.set({
      'offerId': parsedOfferId,
      'participants': [
        widget.currentUserId.toString(),
        widget.otherUserId.toString(),
      ],
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    await _refreshBlockStatus();
    if (_chatIsBlocked) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _blockedByMe
                ? 'Hai bloccato questo utente. Sbloccalo per scrivere.'
                : 'Questo utente ha bloccato la chat.',
          ),
        ),
      );
      return;
    }

    _messageController.clear();
    try {
      await _chatAuthFuture;
      await _upsertChatMetadata();

      final chatDoc =
          FirebaseFirestore.instance.collection('chats').doc(_chatId);

      await chatDoc.update({
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': widget.currentUserId.toString(),
        'lastSenderName': widget.currentUserName,
      });

      await chatDoc.collection('messages').add({
        'senderId': widget.currentUserId.toString(),
        'senderName': widget.currentUserName,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      final offerId = int.tryParse(widget.offerId);
      final receiverId = int.tryParse(widget.otherUserId);
      if (offerId != null &&
          offerId > 0 &&
          receiverId != null &&
          receiverId > 0) {
        try {
          await widget.apiClient.sendChatMessageNotification(
            offerId: offerId,
            receiverId: receiverId,
            messageText: text,
          );
        } catch (_) {
          // Best effort: la chat resta attiva anche se la push fallisce.
        }
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _messageController.text = text;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invio messaggio non riuscito. Riprova tra poco.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage:
                  _otherUserPhotoUrl != null ? NetworkImage(_otherUserPhotoUrl!) : null,
              child: _otherUserPhotoUrl == null
                  ? const Icon(Icons.person_outline, size: 18)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.otherUserName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.orange,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<_ChatMenuAction>(
            onSelected: _onMenuSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _ChatMenuAction.clearLocal,
                child: Text('Svuota schermo chat'),
              ),
              if (_hiddenBefore != null)
                const PopupMenuItem(
                  value: _ChatMenuAction.restoreLocal,
                  child: Text('Mostra cronologia'),
                ),
              const PopupMenuItem(
                value: _ChatMenuAction.clearForEveryone,
                child: Text('Elimina chat per tutti'),
              ),
              PopupMenuItem(
                value: _blockedByMe
                    ? _ChatMenuAction.unblockUser
                    : _ChatMenuAction.blockUser,
                child: Text(_blockedByMe ? 'Sblocca utente' : 'Blocca utente'),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _chatAuthFuture,
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (authSnapshot.hasError) {
            final details = authSnapshot.error?.toString() ?? '';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Non riesco ad aprire la chat. Riprova tra poco.',
                      textAlign: TextAlign.center,
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        details,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .doc(_chatId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Errore: ${snapshot.error}'));
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data?.docs ?? const [];
                    final visibleMessages = _hiddenBefore == null
                        ? messages
                        : messages.where(_isMessageVisible).toList();
                    if (visibleMessages.isEmpty) {
                      return const Center(
                        child: Text(
                          'Nessun messaggio ancora.\nScrivi qualcosa per iniziare!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      itemCount: visibleMessages.length,
                      itemBuilder: (context, index) {
                        final data =
                            visibleMessages[index].data() as Map<String, dynamic>;
                        final isMe = data['senderId']?.toString() ==
                            widget.currentUserId.toString();

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? AppTheme.brown
                                        : AppTheme.peach.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    data['text'] ?? '',
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white
                                          : AppTheme.espresso,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: _chatIsBlocked
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.mist,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: Text(
                          _blockedByMe
                              ? 'Hai bloccato questo utente. Sbloccalo dal menu per riprendere la chat.'
                              : 'Questo utente ha bloccato la chat.',
                          style: const TextStyle(
                            color: AppTheme.brown,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              decoration: InputDecoration(
                                hintText: 'Scrivi un messaggio...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey[100],
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: AppTheme.orange,
                            child: IconButton(
                              icon: const Icon(Icons.send, color: Colors.white),
                              onPressed: _sendMessage,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
