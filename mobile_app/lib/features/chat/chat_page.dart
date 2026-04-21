import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
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
  final String currentUserPhotoFilename;
  final String otherUserId;
  final String otherUserName;
  final String otherUserPhotoFilename;

  const ChatPage({
    super.key,
    required this.apiClient,
    required this.offerId,
    required this.currentUserId,
    this.currentUserName = 'Utente',
    this.currentUserPhotoFilename = '',
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhotoFilename = '',
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const int _maxVoiceSeconds = 30;
  static const Set<String> _imageExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'webp',
  };

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, String> _audioFileCache = <String, String>{};
  final Map<String, String> _mediaFileCache = <String, String>{};
  late final Future<void> _chatAuthFuture;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  Timer? _recordingTimer;

  DateTime? _hiddenBefore;
  bool _blockedByMe = false;
  bool _blockedByOther = false;
  bool _isRecording = false;
  bool _isSendingAudio = false;
  bool _isSendingMedia = false;
  int _recordingSeconds = 0;
  String? _playingMessageId;
  late String _resolvedOtherUserName;
  late String _resolvedOtherUserPhotoFilename;

  String get _chatVisibilityPrefsKey => 'chat_hidden_before_$_chatId';

  String get _chatId {
    final ids = [widget.currentUserId, widget.otherUserId]..sort();
    return '${widget.offerId}_${ids[0]}_${ids[1]}';
  }

  int? get _parsedOfferId => int.tryParse(widget.offerId);
  int? get _parsedOtherUserId => int.tryParse(widget.otherUserId);
  String? get _otherUserPhotoUrl {
    final filename = _resolvedOtherUserPhotoFilename.trim();
    if (filename.isEmpty) {
      return null;
    }
    return widget.apiClient.buildUploadUrl(filename);
  }

  Map<String, String> get _participantNamesPayload {
    final currentName = widget.currentUserName.trim().isEmpty
        ? 'Utente'
        : widget.currentUserName.trim();
    final otherName = _resolvedOtherUserName.trim().isEmpty
        ? 'Utente'
        : _resolvedOtherUserName.trim();
    return <String, String>{
      widget.currentUserId.toString(): currentName,
      widget.otherUserId.toString(): otherName,
    };
  }

  Map<String, String> get _participantPhotosPayload {
    return <String, String>{
      widget.currentUserId.toString(): widget.currentUserPhotoFilename.trim(),
      widget.otherUserId.toString(): _resolvedOtherUserPhotoFilename.trim(),
    };
  }

  @override
  void initState() {
    super.initState();
    _resolvedOtherUserName = widget.otherUserName.trim().isEmpty
        ? 'Utente'
        : widget.otherUserName.trim();
    _resolvedOtherUserPhotoFilename = widget.otherUserPhotoFilename.trim();
    final offerId = _parsedOfferId;
    final otherUserId = _parsedOtherUserId;
    if (offerId != null && otherUserId != null) {
      ChatPresenceTracker.setActiveConversation(
        offerId: offerId,
        otherUserId: otherUserId,
      );
    }
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      if (!state.playing ||
          state.processingState == ProcessingState.completed) {
        if (_playingMessageId != null) {
          setState(() => _playingMessageId = null);
        }
      }
    });
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
    _recordingTimer?.cancel();
    _playerStateSubscription?.cancel();
    unawaited(_audioRecorder.dispose());
    unawaited(_audioPlayer.dispose());
    unawaited(_clearCachedAudioFiles());
    unawaited(_clearCachedMediaFiles());
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureFirebaseAuth() async {
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
      } catch (_) {
        if (!AppConfig.firebaseMessagingConfigured) {
          rethrow;
        }
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
    await _hydrateOtherUserProfile();
  }

  Future<void> _hydrateOtherUserProfile() async {
    final otherUserId = _parsedOtherUserId;
    if (otherUserId == null || otherUserId <= 0) {
      return;
    }
    try {
      final profile = await widget.apiClient.fetchPublicUser(otherUserId);
      final resolvedName = profile.user.nome.trim();
      final resolvedPhoto = profile.user.photoFilename.trim();
      if (!mounted) {
        return;
      }
      setState(() {
        if (resolvedName.isNotEmpty) {
          _resolvedOtherUserName = resolvedName;
        }
        if (resolvedPhoto.isNotEmpty) {
          _resolvedOtherUserPhotoFilename = resolvedPhoto;
        }
      });
      try {
        await _upsertChatMetadata();
      } catch (_) {
        // Best effort metadata sync.
      }
    } catch (_) {
      // Keep provided name/photo if profile fetch fails.
    }
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
      // Keep current state if request fails.
    }
  }

  bool get _chatIsBlocked => _blockedByMe || _blockedByOther;
  bool get _isSendingSomething => _isSendingAudio || _isSendingMedia;

  Map<String, String>? get _chatRequestHeaders {
    final cookie = widget.apiClient.authCookieHeader;
    if (cookie == null || cookie.isEmpty) {
      return null;
    }
    return {'Cookie': cookie};
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _ensureCanSendChat() async {
    await _refreshBlockStatus();
    if (!_chatIsBlocked) {
      return true;
    }
    _showSnack(
      _blockedByMe
          ? 'Hai bloccato questo utente. Sbloccalo per scrivere.'
          : 'Questo utente ha bloccato la chat.',
    );
    return false;
  }

  Future<void> _clearChatScreenLocal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Svuotare questa chat?'),
        content: const Text(
          'I messaggi restano nel database ma vengono nascosti solo su questo dispositivo.',
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
    _showSnack('Schermo chat pulito su questo dispositivo.');
  }

  Future<void> _restoreChatHistoryLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatVisibilityPrefsKey);
    if (!mounted) {
      return;
    }
    setState(() => _hiddenBefore = null);
    _showSnack('Cronologia chat ripristinata.');
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
    // Keep visible if serverTimestamp is still pending.
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
      final chatDoc =
          FirebaseFirestore.instance.collection('chats').doc(_chatId);

      while (true) {
        final batchSlice =
            await chatDoc.collection('messages').limit(400).get();
        if (batchSlice.docs.isEmpty) {
          break;
        }
        final batch = FirebaseFirestore.instance.batch();
        final audioPathsToDelete = <String>[];
        final mediaPathsToDelete = <String>[];
        for (final doc in batchSlice.docs) {
          final payload = doc.data();
          final audioPath = payload['audioPath']?.toString().trim() ?? '';
          if (audioPath.isNotEmpty) {
            audioPathsToDelete.add(audioPath);
          }
          final mediaPath = payload['mediaPath']?.toString().trim() ?? '';
          if (mediaPath.isNotEmpty) {
            mediaPathsToDelete.add(mediaPath);
          }
          batch.delete(doc.reference);
        }
        await batch.commit();
        if (audioPathsToDelete.isNotEmpty) {
          try {
            await widget.apiClient.deleteChatAudioBatch(
              offerId: offerId,
              receiverId: receiverId,
              audioPaths: audioPathsToDelete,
            );
          } catch (_) {
            // Best effort: eventual orphan file does not block chat cleanup.
          }
          await _clearCachedAudioFiles(forAudioPaths: audioPathsToDelete);
        }
        if (mediaPathsToDelete.isNotEmpty) {
          try {
            await widget.apiClient.deleteChatMediaBatch(
              offerId: offerId,
              receiverId: receiverId,
              mediaPaths: mediaPathsToDelete,
            );
          } catch (_) {
            // Best effort.
          }
          await _clearCachedMediaFiles(forMediaPaths: mediaPathsToDelete);
        }
      }

      await chatDoc.set({
        'lastMessage': '',
        'lastSenderId': '',
        'lastSenderName': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'participantNames': _participantNamesPayload,
        'participantPhotos': _participantPhotosPayload,
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
        // Best effort: chat stays cleared even if push fails.
      }

      _showSnack('Chat eliminata per entrambi. Potete riscrivervi da zero.');
    } catch (_) {
      _showSnack('Non riesco a eliminare la chat adesso. Riprova tra poco.');
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
              ? 'Non potrete piu inviare messaggi finche non lo sblocchi.'
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
      _showSnack(
          block ? 'Utente bloccato in chat.' : 'Utente sbloccato in chat.');
    } catch (_) {
      _showSnack('Operazione chat non riuscita. Riprova tra poco.');
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
        'participantNames': _participantNamesPayload,
        'participantPhotos': _participantPhotosPayload,
      });
      return;
    } on FirebaseException catch (error) {
      final shouldBootstrap =
          error.code == 'not-found' || error.code == 'permission-denied';
      if (!shouldBootstrap) {
        // Keep chat usable even if legacy metadata does not match.
        return;
      }
    }

    await chatDoc.set({
      'offerId': parsedOfferId,
      'participants': [
        widget.currentUserId.toString(),
        widget.otherUserId.toString(),
      ],
      'participantNames': _participantNamesPayload,
      'participantPhotos': _participantPhotosPayload,
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }
    if (!await _ensureCanSendChat()) {
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
        'participantNames': _participantNamesPayload,
        'participantPhotos': _participantPhotosPayload,
      });

      await chatDoc.collection('messages').add({
        'senderId': widget.currentUserId.toString(),
        'senderName': widget.currentUserName,
        'type': 'text',
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      final offerId = _parsedOfferId;
      final receiverId = _parsedOtherUserId;
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
          // Best effort: chat remains active even if push fails.
        }
      }
    } catch (_) {
      _messageController.text = text;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
      _showSnack('Invio messaggio non riuscito. Riprova tra poco.');
    }
  }

  Future<String> _buildTempAudioPath() async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  Future<void> _deleteLocalAudio(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Local cleanup best effort.
    }
  }

  Future<void> _clearCachedAudioFiles({Iterable<String>? forAudioPaths}) async {
    final targets = <String>[];
    if (forAudioPaths == null) {
      targets.addAll(_audioFileCache.values);
      _audioFileCache.clear();
    } else {
      for (final audioPath in forAudioPaths) {
        final localPath = _audioFileCache.remove(audioPath);
        if (localPath != null && localPath.isNotEmpty) {
          targets.add(localPath);
        }
      }
    }

    for (final localPath in targets) {
      await _deleteLocalAudio(localPath);
    }
  }

  String _audioCacheExtension(String audioPath) {
    final normalized = audioPath.trim();
    if (normalized.contains('.')) {
      final ext = normalized.split('.').last.toLowerCase();
      if (ext.isNotEmpty && RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) {
        return ext;
      }
    }
    return 'm4a';
  }

  Future<String> _cacheAudioBytes({
    required String audioPath,
    required Uint8List bytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final extension = _audioCacheExtension(audioPath);
    final safeHash = audioPath.hashCode.abs();
    final localPath = '${tempDir.path}/chat_audio_$safeHash.$extension';
    final file = File(localPath);
    await file.writeAsBytes(bytes, flush: true);
    _audioFileCache[audioPath] = localPath;
    return localPath;
  }

  String _fileExtensionFromName(String value) {
    final name = value.trim();
    if (!name.contains('.')) {
      return '';
    }
    return name.split('.').last.toLowerCase();
  }

  bool _isImageFileName(String fileName) =>
      _imageExtensions.contains(_fileExtensionFromName(fileName));

  Future<void> _clearCachedMediaFiles({Iterable<String>? forMediaPaths}) async {
    final targets = <String>[];
    if (forMediaPaths == null) {
      targets.addAll(_mediaFileCache.values);
      _mediaFileCache.clear();
    } else {
      for (final mediaPath in forMediaPaths) {
        final localPath = _mediaFileCache.remove(mediaPath);
        if (localPath != null && localPath.isNotEmpty) {
          targets.add(localPath);
        }
      }
    }
    for (final localPath in targets) {
      await _deleteLocalAudio(localPath);
    }
  }

  String _mediaCacheExtension(String mediaPath, String fileName) {
    final fromMediaPath = _fileExtensionFromName(mediaPath);
    if (fromMediaPath.isNotEmpty) {
      return fromMediaPath;
    }
    final fromFileName = _fileExtensionFromName(fileName);
    if (fromFileName.isNotEmpty) {
      return fromFileName;
    }
    return 'bin';
  }

  Future<String> _cacheMediaBytes({
    required String mediaPath,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final extension = _mediaCacheExtension(mediaPath, fileName);
    final safeHash = mediaPath.hashCode.abs();
    final localPath = '${tempDir.path}/chat_media_$safeHash.$extension';
    final file = File(localPath);
    await file.writeAsBytes(bytes, flush: true);
    _mediaFileCache[mediaPath] = localPath;
    return localPath;
  }

  Future<String> _ensureCachedMediaFile({
    required int offerId,
    required int otherUserId,
    required String mediaPath,
    required String fileName,
  }) async {
    final cached = _mediaFileCache[mediaPath];
    if (cached != null && cached.isNotEmpty && await File(cached).exists()) {
      return cached;
    }

    final bytes = await widget.apiClient.downloadChatMedia(
      offerId: offerId,
      otherUserId: otherUserId,
      mediaPath: mediaPath,
    );
    return _cacheMediaBytes(
      mediaPath: mediaPath,
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
    );
  }

  Future<void> _pickAndSendAttachment() async {
    if (_isSendingSomething || _isRecording) {
      return;
    }
    if (!await _ensureCanSendChat()) {
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final picked = result.files.first;
      final localPath = picked.path?.trim() ?? '';
      if (localPath.isEmpty) {
        _showSnack('Non riesco a leggere il file selezionato.');
        return;
      }
      final fileName = picked.name.trim().isNotEmpty
          ? picked.name.trim()
          : File(localPath).uri.pathSegments.last;
      final kind = _isImageFileName(fileName) ? 'image' : 'file';
      await _sendMediaMessage(
        localPath: localPath,
        kind: kind,
        displayFileName: fileName,
      );
    } catch (_) {
      _showSnack('Non riesco ad allegare il file. Riprova.');
    }
  }

  Future<void> _captureAndSendImage() async {
    if (_isSendingSomething || _isRecording) {
      return;
    }
    if (!await _ensureCanSendChat()) {
      return;
    }
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (photo == null) {
        return;
      }
      final fileName = photo.name.trim().isNotEmpty
          ? photo.name.trim()
          : File(photo.path).uri.pathSegments.last;
      await _sendMediaMessage(
        localPath: photo.path,
        kind: 'image',
        displayFileName: fileName,
      );
    } catch (_) {
      _showSnack('Non riesco ad aprire la fotocamera.');
    }
  }

  Future<void> _sendMediaMessage({
    required String localPath,
    required String kind,
    required String displayFileName,
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    if (normalizedKind != 'image' && normalizedKind != 'file') {
      _showSnack('Tipo allegato non valido.');
      return;
    }
    if (_isSendingSomething) {
      return;
    }
    if (!await _ensureCanSendChat()) {
      return;
    }

    if (mounted) {
      setState(() => _isSendingMedia = true);
    }
    try {
      final offerId = _parsedOfferId;
      final receiverId = _parsedOtherUserId;
      if (offerId == null ||
          offerId <= 0 ||
          receiverId == null ||
          receiverId <= 0) {
        throw Exception('Dati chat non validi.');
      }

      await _chatAuthFuture;
      await _upsertChatMetadata();

      final chatDoc =
          FirebaseFirestore.instance.collection('chats').doc(_chatId);
      final messageRef = chatDoc.collection('messages').doc();

      final uploadPayload = await widget.apiClient.uploadChatMedia(
        offerId: offerId,
        receiverId: receiverId,
        filePath: localPath,
        kind: normalizedKind,
        fileName: displayFileName,
      );

      final mediaPath = uploadPayload['media_path']?.toString().trim() ?? '';
      if (mediaPath.isEmpty) {
        throw Exception('Allegato caricato ma path mancante.');
      }
      final contentType =
          uploadPayload['content_type']?.toString().trim() ?? '';
      final fileName =
          uploadPayload['file_name']?.toString().trim() ?? displayFileName;
      final bytes = uploadPayload['bytes'] is num
          ? (uploadPayload['bytes'] as num).toInt()
          : int.tryParse(uploadPayload['bytes']?.toString() ?? '') ?? 0;
      final kindFromServer =
          uploadPayload['media_kind']?.toString().trim().toLowerCase() ??
              normalizedKind;

      final previewText = kindFromServer == 'image'
          ? 'Foto inviata'
          : 'Allegato: ${fileName.isNotEmpty ? fileName : "file"}';

      await chatDoc.set({
        'lastMessage': previewText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': widget.currentUserId.toString(),
        'lastSenderName': widget.currentUserName,
        'participantNames': _participantNamesPayload,
        'participantPhotos': _participantPhotosPayload,
      }, SetOptions(merge: true));

      await messageRef.set({
        'senderId': widget.currentUserId.toString(),
        'senderName': widget.currentUserName,
        'type': kindFromServer == 'image' ? 'image' : 'file',
        'text': previewText,
        'mediaPath': mediaPath,
        'mediaFileName': fileName,
        'mediaContentType': contentType,
        'mediaSizeBytes': bytes,
        'timestamp': FieldValue.serverTimestamp(),
      });

      try {
        await widget.apiClient.sendChatMessageNotification(
          offerId: offerId,
          receiverId: receiverId,
          messageText: previewText,
        );
      } catch (_) {
        // Best effort push.
      }
    } on ApiException catch (e) {
      _showSnack(e.message.isNotEmpty
          ? e.message
          : 'Invio allegato non riuscito. Riprova.');
    } catch (_) {
      _showSnack('Invio allegato non riuscito. Riprova.');
    } finally {
      if (mounted) {
        setState(() => _isSendingMedia = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _openFileAttachment(Map<String, dynamic> data) async {
    final mediaPath = data['mediaPath']?.toString().trim() ?? '';
    if (mediaPath.isEmpty) {
      _showSnack('Allegato non disponibile.');
      return;
    }
    final offerId = _parsedOfferId;
    final otherUserId = _parsedOtherUserId;
    if (offerId == null || otherUserId == null) {
      _showSnack('Dati evento non validi per aprire l\'allegato.');
      return;
    }
    final fileName = data['mediaFileName']?.toString().trim().isNotEmpty == true
        ? data['mediaFileName'].toString().trim()
        : File(mediaPath).uri.pathSegments.last;

    try {
      final localPath = await _ensureCachedMediaFile(
        offerId: offerId,
        otherUserId: otherUserId,
        mediaPath: mediaPath,
        fileName: fileName,
      );
      final result = await OpenFilex.open(localPath);
      if (result.type != ResultType.done) {
        _showSnack('Impossibile aprire il file sul dispositivo.');
      }
    } on ApiException catch (e) {
      _showSnack(
          e.message.isNotEmpty ? e.message : 'Download allegato non riuscito.');
    } catch (_) {
      _showSnack('Impossibile aprire questo allegato.');
    }
  }

  void _openImagePreview({
    required String imageUrl,
    required String heroTag,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Hero(
            tag: heroTag,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              headers: _chatRequestHeaders,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 240,
                child:
                    Center(child: Icon(Icons.broken_image_outlined, size: 48)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startVoiceRecording() async {
    if (_isRecording || _isSendingSomething) {
      return;
    }
    if (!await _ensureCanSendChat()) {
      return;
    }
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showSnack('Permesso microfono non concesso.');
        return;
      }
      final recordPath = await _buildTempAudioPath();
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: recordPath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_isRecording) {
          timer.cancel();
          return;
        }
        final next = _recordingSeconds + 1;
        if (next >= _maxVoiceSeconds) {
          setState(() => _recordingSeconds = _maxVoiceSeconds);
          timer.cancel();
          unawaited(_stopVoiceRecording(send: true, limitReached: true));
          return;
        }
        setState(() => _recordingSeconds = next);
      });
    } catch (_) {
      _showSnack('Non riesco ad avviare la registrazione. Riprova.');
    }
  }

  Future<void> _stopVoiceRecording({
    required bool send,
    bool limitReached = false,
  }) async {
    if (!_isRecording) {
      return;
    }
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final capturedSeconds = _recordingSeconds;
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }

    String? localPath;
    try {
      localPath = await _audioRecorder.stop();
    } catch (_) {
      localPath = null;
    }

    if (localPath == null || localPath.isEmpty) {
      if (send) {
        _showSnack('Registrazione non disponibile. Riprova.');
      }
      return;
    }

    if (!send) {
      await _deleteLocalAudio(localPath);
      return;
    }

    final durationSec = capturedSeconds.clamp(1, _maxVoiceSeconds);
    await _sendAudioMessage(
      localPath: localPath,
      durationSec: durationSec,
      limitReached: limitReached,
    );
  }

  Future<void> _sendAudioMessage({
    required String localPath,
    required int durationSec,
    required bool limitReached,
  }) async {
    if (_isSendingSomething) {
      await _deleteLocalAudio(localPath);
      return;
    }
    if (!await _ensureCanSendChat()) {
      await _deleteLocalAudio(localPath);
      return;
    }

    if (mounted) {
      setState(() => _isSendingAudio = true);
    }
    final previewText = 'Vocale (${durationSec}s)';
    try {
      final offerId = _parsedOfferId;
      final receiverId = _parsedOtherUserId;
      if (offerId == null ||
          offerId <= 0 ||
          receiverId == null ||
          receiverId <= 0) {
        throw Exception('Dati chat non validi.');
      }

      await _chatAuthFuture;
      await _upsertChatMetadata();

      final chatDoc =
          FirebaseFirestore.instance.collection('chats').doc(_chatId);
      final messageRef = chatDoc.collection('messages').doc();
      final uploadPayload = await widget.apiClient.uploadChatAudio(
        offerId: offerId,
        receiverId: receiverId,
        filePath: localPath,
      );
      final storagePath = uploadPayload['audio_path']?.toString().trim() ?? '';
      if (storagePath.isEmpty) {
        throw Exception('Audio caricato ma path mancante.');
      }

      await chatDoc.set({
        'lastMessage': previewText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': widget.currentUserId.toString(),
        'lastSenderName': widget.currentUserName,
        'participantNames': _participantNamesPayload,
        'participantPhotos': _participantPhotosPayload,
      }, SetOptions(merge: true));

      await messageRef.set({
        'senderId': widget.currentUserId.toString(),
        'senderName': widget.currentUserName,
        'type': 'audio',
        'text': previewText,
        'audioPath': storagePath,
        'audioDurationSec': durationSec,
        'timestamp': FieldValue.serverTimestamp(),
      });

      try {
        await widget.apiClient.sendChatMessageNotification(
          offerId: offerId,
          receiverId: receiverId,
          messageText: previewText,
        );
      } catch (_) {
        // Best effort push.
      }

      if (limitReached) {
        _showSnack('Limite 30 secondi raggiunto: vocale inviato.');
      }
    } on ApiException catch (e) {
      _showSnack(e.message.isNotEmpty
          ? e.message
          : 'Invio vocale non riuscito. Riprova tra poco.');
    } catch (_) {
      _showSnack('Invio vocale non riuscito. Riprova tra poco.');
    } finally {
      await _deleteLocalAudio(localPath);
      if (mounted) {
        setState(() => _isSendingAudio = false);
      }
    }
  }

  int _parseDurationSeconds(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _toggleAudioPlayback({
    required String messageId,
    required Map<String, dynamic> data,
  }) async {
    final audioPath = data['audioPath']?.toString().trim() ?? '';
    if (audioPath.isEmpty) {
      _showSnack('Audio non disponibile.');
      return;
    }
    final offerId = _parsedOfferId;
    final otherUserId = _parsedOtherUserId;
    if (offerId == null ||
        offerId <= 0 ||
        otherUserId == null ||
        otherUserId <= 0) {
      _showSnack('Dati evento non validi per riprodurre il vocale.');
      return;
    }

    try {
      if (_playingMessageId == messageId && _audioPlayer.playing) {
        await _audioPlayer.pause();
        if (mounted) {
          setState(() => _playingMessageId = null);
        }
        return;
      }

      String? localFilePath = _audioFileCache[audioPath];
      if (localFilePath == null || localFilePath.isEmpty) {
        final audioBytes = await widget.apiClient.downloadChatAudio(
          offerId: offerId,
          otherUserId: otherUserId,
          audioPath: audioPath,
        );
        localFilePath = await _cacheAudioBytes(
          audioPath: audioPath,
          bytes: Uint8List.fromList(audioBytes),
        );
      } else {
        final existingFile = File(localFilePath);
        if (!await existingFile.exists()) {
          _audioFileCache.remove(audioPath);
          final audioBytes = await widget.apiClient.downloadChatAudio(
            offerId: offerId,
            otherUserId: otherUserId,
            audioPath: audioPath,
          );
          localFilePath = await _cacheAudioBytes(
            audioPath: audioPath,
            bytes: Uint8List.fromList(audioBytes),
          );
        }
      }

      await _audioPlayer.setFilePath(localFilePath);
      await _audioPlayer.play();
      if (mounted) {
        setState(() => _playingMessageId = messageId);
      }
    } catch (_) {
      _showSnack('Non riesco a riprodurre questo vocale.');
    }
  }

  Widget _buildMessageContent({
    required String messageId,
    required Map<String, dynamic> data,
    required bool isMe,
  }) {
    final type = data['type']?.toString().toLowerCase() ?? 'text';
    final textColor = isMe ? Colors.white : AppTheme.espresso;
    final offerId = _parsedOfferId;
    final otherUserId = _parsedOtherUserId;

    if (type == 'audio') {
      final isPlaying = _playingMessageId == messageId && _audioPlayer.playing;
      final durationSec = _parseDurationSeconds(data['audioDurationSec']);
      return InkWell(
        onTap: () => _toggleAudioPlayback(messageId: messageId, data: data),
        borderRadius: BorderRadius.circular(14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: textColor,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              durationSec > 0
                  ? 'Messaggio vocale ${durationSec}s'
                  : 'Messaggio vocale',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (type == 'image') {
      final mediaPath = data['mediaPath']?.toString().trim() ?? '';
      if (mediaPath.isEmpty || offerId == null || otherUserId == null) {
        return Text(
          data['text']?.toString() ?? 'Immagine non disponibile',
          style: TextStyle(color: textColor),
        );
      }
      final imageUrl = widget.apiClient.buildChatMediaUrl(
        mediaPath: mediaPath,
        offerId: offerId,
        otherUserId: otherUserId,
      );
      final heroTag = 'chat_img_${messageId}_$mediaPath';
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openImagePreview(imageUrl: imageUrl, heroTag: heroTag),
        child: Hero(
          tag: heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              headers: _chatRequestHeaders,
              width: 170,
              height: 170,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 170,
                height: 170,
                color: Colors.black12,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: textColor.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (type == 'file') {
      final fileName =
          (data['mediaFileName']?.toString().trim().isNotEmpty == true)
              ? data['mediaFileName'].toString().trim()
              : 'Allegato';
      final sizeBytes = data['mediaSizeBytes'] is num
          ? (data['mediaSizeBytes'] as num).toInt()
          : int.tryParse(data['mediaSizeBytes']?.toString() ?? '') ?? 0;
      final sizeLabel = _formatBytes(sizeBytes);
      return InkWell(
        onTap: () => _openFileAttachment(data),
        borderRadius: BorderRadius.circular(14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file_rounded, color: textColor, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (sizeLabel.isNotEmpty)
                    Text(
                      sizeLabel,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      data['text']?.toString() ?? '',
      style: TextStyle(color: textColor),
    );
  }

  Widget _buildRecordingComposer() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record,
                    color: Colors.red, size: 14),
                const SizedBox(width: 8),
                Text(
                  'Registrazione $_recordingSeconds/$_maxVoiceSeconds s',
                  style: const TextStyle(
                    color: AppTheme.brown,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          backgroundColor: AppTheme.cardBorder,
          child: IconButton(
            icon: const Icon(Icons.close, color: AppTheme.brown),
            onPressed: () => _stopVoiceRecording(send: false),
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          backgroundColor: AppTheme.orange,
          child: IconButton(
            icon: const Icon(Icons.send, color: Colors.white),
            onPressed: _isSendingSomething
                ? null
                : () => _stopVoiceRecording(send: true),
          ),
        ),
      ],
    );
  }

  Widget _buildTextComposer() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _messageController,
            enabled: !_isSendingSomething,
            decoration: InputDecoration(
              hintText: _isSendingSomething
                  ? 'Invio in corso...'
                  : 'Scrivi un messaggio...',
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
          backgroundColor: AppTheme.cardBorder,
          child: IconButton(
            icon: const Icon(Icons.attach_file_rounded, color: AppTheme.brown),
            onPressed: _isSendingSomething ? null : _pickAndSendAttachment,
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          backgroundColor: AppTheme.cardBorder,
          child: IconButton(
            icon: const Icon(Icons.photo_camera_rounded, color: AppTheme.brown),
            onPressed: _isSendingSomething ? null : _captureAndSendImage,
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          backgroundColor: AppTheme.brown,
          child: IconButton(
            icon: const Icon(Icons.mic, color: Colors.white),
            onPressed: _isSendingSomething ? null : _startVoiceRecording,
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          backgroundColor: AppTheme.orange,
          child: IconButton(
            icon: const Icon(Icons.send, color: Colors.white),
            onPressed: _isSendingSomething ? null : _sendMessage,
          ),
        ),
      ],
    );
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
              backgroundImage: _otherUserPhotoUrl != null
                  ? NetworkImage(_otherUserPhotoUrl!)
                  : null,
              child: _otherUserPhotoUrl == null
                  ? const Icon(Icons.person_outline, size: 18)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _resolvedOtherUserName,
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
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
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
                        final doc = visibleMessages[index];
                        final data = doc.data() as Map<String, dynamic>;
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
                                  child: _buildMessageContent(
                                    messageId: doc.id,
                                    data: data,
                                    isMe: isMe,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                    : (_isRecording
                        ? _buildRecordingComposer()
                        : _buildTextComposer()),
              ),
            ],
          );
        },
      ),
    );
  }
}
