import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;
import 'package:video_compress/video_compress.dart';

import '../../core/chat/chat_presence_tracker.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';

enum _ChatMenuAction {
  clearForEveryone,
  blockUser,
  unblockUser,
}

enum _ChatComposerMediaAction {
  file,
  camera,
  voice,
}

enum _ChatMessageAction {
  saveAttachment,
  hideForMe,
}

class _PreparedMediaUpload {
  final String uploadPath;
  final String previewPath;
  final String uploadFileName;
  final bool shouldDeleteUploadFile;

  const _PreparedMediaUpload({
    required this.uploadPath,
    required this.previewPath,
    required this.uploadFileName,
    required this.shouldDeleteUploadFile,
  });
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
  static const int _imageCompressionThresholdBytes = 2 * 1024 * 1024;
  static const int _videoCompressionThresholdBytes = 12 * 1024 * 1024;
  static const int _imageCompressionQuality = 74;
  static const int _imageCompressionMaxDimension = 1600;
  static const Set<String> _imageExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'webp',
  };
  static const Set<String> _videoExtensions = <String>{
    'mp4',
    'm4v',
    'mov',
    '3gp',
    'webm',
    'mkv',
  };

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, String> _audioFileCache = <String, String>{};
  final Map<String, String> _mediaFileCache = <String, String>{};
  final Map<String, int> _mediaDownloadSentBytes = <String, int>{};
  final Map<String, int> _mediaDownloadTotalBytes = <String, int>{};
  final Map<String, Uint8List> _videoThumbnailCache = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _videoThumbnailFutureCache =
      <String, Future<Uint8List?>>{};
  late final Future<void> _chatBootstrapFuture;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  Timer? _recordingTimer;
  Timer? _messagesPollTimer;

  bool _blockedByMe = false;
  bool _blockedByOther = false;
  bool _isRecording = false;
  bool _isSendingAudio = false;
  bool _isPreparingMedia = false;
  bool _isSendingMedia = false;
  bool _isLoadingMessages = true;
  String _uploadingMediaName = '';
  String _mediaTransferStatus = '';
  bool _mediaTransferIsVideo = false;
  Uint8List? _mediaTransferPreviewBytes;
  int _uploadProgressSentBytes = 0;
  int _uploadProgressTotalBytes = 0;
  int _recordingSeconds = 0;
  String? _playingMessageId;
  String? _messagesError;
  List<Map<String, dynamic>> _messages = const <Map<String, dynamic>>[];
  late String _resolvedOtherUserName;
  late String _resolvedOtherUserPhotoFilename;

  String get _chatHiddenMessagesPrefsKey => 'chat_hidden_messages_$_chatId';
  Set<String> _hiddenMessageIds = <String>{};

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
    _chatBootstrapFuture = _bootstrapChat();
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
    _messagesPollTimer?.cancel();
    _playerStateSubscription?.cancel();
    unawaited(_audioRecorder.dispose());
    unawaited(_audioPlayer.dispose());
    unawaited(_clearCachedAudioFiles());
    unawaited(_clearCachedMediaFiles());
    _mediaDownloadSentBytes.clear();
    _mediaDownloadTotalBytes.clear();
    _videoThumbnailCache.clear();
    _videoThumbnailFutureCache.clear();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapChat() async {
    await _loadChatVisibilityPreference();
    await _refreshBlockStatus();
    await _ensureChatThread();
    await _hydrateOtherUserProfile();
    await _refreshMessages();
    _startMessagesPolling();
  }

  Future<void> _ensureChatThread() async {
    final offerId = _parsedOfferId;
    final otherUserId = _parsedOtherUserId;
    if (offerId == null ||
        offerId <= 0 ||
        otherUserId == null ||
        otherUserId <= 0) {
      throw Exception('Dati chat non validi.');
    }
    await widget.apiClient.ensureChatThread(
      offerId: offerId,
      otherUserId: otherUserId,
    );
  }

  void _startMessagesPolling() {
    _messagesPollTimer?.cancel();
    _messagesPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshMessages(silent: true)),
    );
  }

  DateTime? _parseMessageTimestamp(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw.replaceFirst('Z', '+00:00'))?.toLocal();
  }

  Future<void> _refreshMessages({bool silent = false}) async {
    final offerId = _parsedOfferId;
    final otherUserId = _parsedOtherUserId;
    if (offerId == null ||
        offerId <= 0 ||
        otherUserId == null ||
        otherUserId <= 0) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingMessages = false;
        _messagesError = 'Dati chat non validi.';
      });
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _isLoadingMessages = true;
        _messagesError = null;
      });
    }

    try {
      final payload = await widget.apiClient.fetchChatMessages(
        offerId: offerId,
        otherUserId: otherUserId,
        limit: 300,
      );
      if (!mounted) {
        return;
      }
      final normalized = payload.map((entry) {
        final map = Map<String, dynamic>.from(entry);
        map['senderId'] = (map['senderId'] ?? '').toString();
        map['type'] = (map['type'] ?? 'text').toString().toLowerCase();
        map['text'] = (map['text'] ?? '').toString();
        map['timestamp'] = (map['timestamp'] ?? '').toString();
        return map;
      }).toList();
      setState(() {
        _messages = normalized;
        _messagesError = null;
        _isLoadingMessages = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingMessages = false;
        _messagesError = error.toString();
      });
    }
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
        await _ensureChatThread();
      } catch (_) {
        // Best effort metadata sync.
      }
    } catch (_) {
      // Keep provided name/photo if profile fetch fails.
    }
  }

  Future<void> _loadChatVisibilityPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final hiddenIds =
        prefs.getStringList(_chatHiddenMessagesPrefsKey) ?? const <String>[];
    // Pulizia retrocompatibile: la feature "svuota schermo chat" non e' piu esposta.
    await prefs.remove('chat_hidden_before_$_chatId');
    if (!mounted) {
      return;
    }
    setState(() {
      _hiddenMessageIds = hiddenIds.toSet();
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
  bool get _isSendingSomething =>
      _isSendingAudio || _isPreparingMedia || _isSendingMedia;
  double get _uploadProgress {
    if (_uploadProgressTotalBytes <= 0) {
      return 0;
    }
    return (_uploadProgressSentBytes / _uploadProgressTotalBytes)
        .clamp(0.0, 1.0);
  }

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

  String _messageLocalId(Map<String, dynamic> payload) {
    final direct = payload['id']?.toString().trim() ?? '';
    if (direct.isNotEmpty) {
      return 'id:$direct';
    }
    final fallbackRaw =
        '${payload['timestamp']}|${payload['senderId']}|${payload['type']}|${payload['text']}|${payload['audioPath']}|${payload['mediaPath']}';
    return 'raw:$fallbackRaw';
  }

  Future<void> _persistHiddenMessageIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _chatHiddenMessagesPrefsKey,
      _hiddenMessageIds.toList(growable: false),
    );
  }

  Future<void> _hideMessageForMe(Map<String, dynamic> payload) async {
    final localId = _messageLocalId(payload);
    if (localId.isEmpty || _hiddenMessageIds.contains(localId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _hiddenMessageIds = {..._hiddenMessageIds, localId};
      _messages = _messages
          .where((message) => _messageLocalId(message) != localId)
          .toList();
    });
    await _persistHiddenMessageIds();
    _showSnack('Messaggio nascosto solo per te.');
  }

  bool _isMessageVisible(Map<String, dynamic> payload) {
    if (_hiddenMessageIds.contains(_messageLocalId(payload))) {
      return false;
    }
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
      await widget.apiClient.clearChatForEveryone(
        offerId: offerId,
        receiverId: receiverId,
      );
      await _clearCachedAudioFiles();
      await _clearCachedMediaFiles();
      await _refreshMessages(silent: true);

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
      final offerId = _parsedOfferId;
      final receiverId = _parsedOtherUserId;
      if (offerId == null ||
          offerId <= 0 ||
          receiverId == null ||
          receiverId <= 0) {
        throw Exception('Dati chat non validi.');
      }

      await widget.apiClient.sendChatMessage(
        offerId: offerId,
        receiverId: receiverId,
        type: 'text',
        text: text,
      );
      await _refreshMessages(silent: true);

      try {
        await widget.apiClient.sendChatMessageNotification(
          offerId: offerId,
          receiverId: receiverId,
          messageText: text,
        );
      } catch (_) {
        // Best effort: chat remains active even if push fails.
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

  Future<String> _ensureCachedAudioFile({
    required int offerId,
    required int otherUserId,
    required String audioPath,
  }) async {
    final cached = _audioFileCache[audioPath];
    if (cached != null && cached.isNotEmpty && await File(cached).exists()) {
      return cached;
    }

    final audioBytes = await widget.apiClient.downloadChatAudio(
      offerId: offerId,
      otherUserId: otherUserId,
      audioPath: audioPath,
    );
    return _cacheAudioBytes(
      audioPath: audioPath,
      bytes: Uint8List.fromList(audioBytes),
    );
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

  bool _isVideoFileName(String fileName) =>
      _videoExtensions.contains(_fileExtensionFromName(fileName));

  bool _isVideoMessage(Map<String, dynamic> data) {
    final mediaFileName = data['mediaFileName']?.toString().trim() ?? '';
    final mediaPath = data['mediaPath']?.toString().trim() ?? '';
    final mediaContentType =
        data['mediaContentType']?.toString().trim().toLowerCase() ?? '';
    return _isVideoFileName(mediaFileName) ||
        _isVideoFileName(mediaPath) ||
        mediaContentType.startsWith('video/');
  }

  bool _isMediaDownloadInProgress(String mediaPath) =>
      _mediaDownloadSentBytes.containsKey(mediaPath);

  double _mediaDownloadProgress(String mediaPath) {
    final sent = _mediaDownloadSentBytes[mediaPath] ?? 0;
    final total = _mediaDownloadTotalBytes[mediaPath] ?? 0;
    if (total <= 0) {
      return 0;
    }
    return (sent / total).clamp(0.0, 1.0);
  }

  String _mediaDownloadProgressLabel(String mediaPath) {
    final sent = _mediaDownloadSentBytes[mediaPath] ?? 0;
    final total = _mediaDownloadTotalBytes[mediaPath] ?? 0;
    if (total <= 0) {
      return 'Download in corso...';
    }
    final percent = ((sent / total).clamp(0.0, 1.0) * 100).round();
    final sentLabel = _formatBytes(sent);
    final totalLabel = _formatBytes(total);
    if (sentLabel.isNotEmpty && totalLabel.isNotEmpty) {
      return '$percent% • $sentLabel / $totalLabel';
    }
    return '$percent%';
  }

  String _sanitizeDownloadFileName(
    String rawName, {
    String fallbackBase = 'allegato_chat',
  }) {
    final cleaned = rawName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      return fallbackBase;
    }
    return cleaned;
  }

  // ignore: unused_element
  String _compactMediaLabel(String fileName, {int maxChars = 38}) {
    final safe = fileName.trim();
    if (safe.isEmpty) {
      return 'Allegato';
    }
    if (safe.length <= maxChars) {
      return safe;
    }
    final ext = _fileExtensionFromName(safe);
    if (ext.isEmpty || maxChars <= ext.length + 4) {
      return '${safe.substring(0, maxChars - 1)}…';
    }
    final keep = (maxChars - ext.length - 2).clamp(4, safe.length);
    return '${safe.substring(0, keep)}….$ext';
  }

  Future<String?> _findCachedMediaPathOnDisk({
    required String mediaPath,
    required String fileName,
  }) async {
    if (mediaPath.isEmpty) {
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final safeHash = mediaPath.hashCode.abs();
    final preferredExt = _mediaCacheExtension(mediaPath, fileName);
    final preferredPath = '${tempDir.path}/chat_media_$safeHash.$preferredExt';
    final preferredFile = File(preferredPath);
    if (await preferredFile.exists()) {
      _mediaFileCache[mediaPath] = preferredPath;
      return preferredPath;
    }

    final prefix = 'chat_media_$safeHash.';
    for (final entity in tempDir.listSync(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.path.replaceAll('\\', '/').split('/').last;
      if (!name.startsWith(prefix)) {
        continue;
      }
      _mediaFileCache[mediaPath] = entity.path;
      return entity.path;
    }

    return null;
  }

  String _messageTimestampLabel(Map<String, dynamic> data) {
    final parsed = _parseMessageTimestamp(data['timestamp']) ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${parsed.year}${two(parsed.month)}${two(parsed.day)}_${two(parsed.hour)}${two(parsed.minute)}${two(parsed.second)}';
  }

  bool get _isMusicAiDark => AppTheme.useMusicAiPalette;

  Color get _chatCanvasTop =>
      _isMusicAiDark ? const Color(0xFF070A11) : const Color(0xFFF8F0E9);
  Color get _chatCanvasBottom =>
      _isMusicAiDark ? const Color(0xFF11182A) : const Color(0xFFF4ECE5);
  Color get _chatInputSurface =>
      _isMusicAiDark ? const Color(0xFF1A2439) : (Colors.grey[100] ?? AppTheme.mist);
  Color get _chatInputBorder =>
      _isMusicAiDark ? const Color(0xFF2F3B5A) : AppTheme.cardBorder;
  Color get _incomingBubbleColor =>
      _isMusicAiDark ? const Color(0xFF1C263D) : const Color(0xFFF7EADF);
  Color get _incomingVideoBubbleColor =>
      _isMusicAiDark ? const Color(0xFF182133) : const Color(0xFFF9F2EA);
  Color get _outgoingBubbleColor =>
      _isMusicAiDark ? const Color(0xFF314783) : AppTheme.orange.withValues(alpha: 0.94);
  Color get _outgoingVideoBubbleColor =>
      _isMusicAiDark ? const Color(0xFF273B72) : const Color(0xFFF4E8DE);

  bool _canSaveMessageAttachment(Map<String, dynamic> data) {
    final type = data['type']?.toString().toLowerCase().trim() ?? '';
    if (type == 'audio') {
      return (data['audioPath']?.toString().trim().isNotEmpty == true);
    }
    if (type == 'image' || type == 'file') {
      return (data['mediaPath']?.toString().trim().isNotEmpty == true);
    }
    return false;
  }

  String _downloadFileNameForMessage(Map<String, dynamic> data) {
    final type = data['type']?.toString().toLowerCase().trim() ?? '';
    final timestamp = _messageTimestampLabel(data);
    if (type == 'audio') {
      final audioPath = data['audioPath']?.toString().trim() ?? '';
      final extension = _audioCacheExtension(audioPath);
      return _sanitizeDownloadFileName('vocale_$timestamp.$extension');
    }

    final rawFileName = data['mediaFileName']?.toString().trim() ?? '';
    if (rawFileName.isNotEmpty) {
      return _sanitizeDownloadFileName(rawFileName);
    }

    final mediaPath = data['mediaPath']?.toString().trim() ?? '';
    final extension = _fileExtensionFromName(mediaPath);
    if (extension.isNotEmpty) {
      final base = type == 'image' ? 'foto_chat' : 'file_chat';
      return _sanitizeDownloadFileName('${base}_$timestamp.$extension');
    }
    return _sanitizeDownloadFileName('allegato_chat_$timestamp');
  }

  Future<void> _clearCachedMediaFiles({Iterable<String>? forMediaPaths}) async {
    final targets = <String>[];
    if (forMediaPaths == null) {
      targets.addAll(_mediaFileCache.values);
      _mediaFileCache.clear();
      _videoThumbnailCache.clear();
      _videoThumbnailFutureCache.clear();
      _mediaDownloadSentBytes.clear();
      _mediaDownloadTotalBytes.clear();
    } else {
      for (final mediaPath in forMediaPaths) {
        final localPath = _mediaFileCache.remove(mediaPath);
        if (localPath != null && localPath.isNotEmpty) {
          targets.add(localPath);
        }
        _videoThumbnailCache.remove(mediaPath);
        _videoThumbnailFutureCache.remove(mediaPath);
        _mediaDownloadSentBytes.remove(mediaPath);
        _mediaDownloadTotalBytes.remove(mediaPath);
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
    UploadProgressCallback? onProgress,
  }) async {
    final cached = _mediaFileCache[mediaPath];
    if (cached != null && cached.isNotEmpty && await File(cached).exists()) {
      onProgress?.call(1, 1);
      return cached;
    }

    final persisted = await _findCachedMediaPathOnDisk(
      mediaPath: mediaPath,
      fileName: fileName,
    );
    if (persisted != null && persisted.isNotEmpty) {
      onProgress?.call(1, 1);
      return persisted;
    }

    final bytes = await widget.apiClient.downloadChatMedia(
      offerId: offerId,
      otherUserId: otherUserId,
      mediaPath: mediaPath,
      onProgress: onProgress,
    );
    return _cacheMediaBytes(
      mediaPath: mediaPath,
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
    );
  }

  Future<Uint8List?> _buildVideoThumbnailFromLocalPath(String localPath) async {
    try {
      final generated = await video_thumbnail.VideoThumbnail.thumbnailData(
        video: localPath,
        imageFormat: video_thumbnail.ImageFormat.JPEG,
        maxWidth: 420,
        quality: 65,
      );
      return generated;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _videoThumbnailForMediaPath({
    required int offerId,
    required int otherUserId,
    required String mediaPath,
    required String fileName,
  }) {
    final cached = _videoThumbnailCache[mediaPath];
    if (cached != null && cached.isNotEmpty) {
      return Future<Uint8List?>.value(cached);
    }

    final inFlight = _videoThumbnailFutureCache[mediaPath];
    if (inFlight != null) {
      return inFlight;
    }

    final future = () async {
      var localPath = _mediaFileCache[mediaPath];
      if (localPath == null || localPath.isEmpty) {
        localPath = await _findCachedMediaPathOnDisk(
          mediaPath: mediaPath,
          fileName: fileName,
        );
      }
      if (localPath == null || localPath.isEmpty) {
        try {
          localPath = await _ensureCachedMediaFile(
            offerId: offerId,
            otherUserId: otherUserId,
            mediaPath: mediaPath,
            fileName: fileName,
          );
        } catch (_) {
          return null;
        }
      }
      final localFile = File(localPath);
      if (!await localFile.exists()) {
        return null;
      }
      final bytes = await _buildVideoThumbnailFromLocalPath(localPath);
      if (bytes != null && bytes.isNotEmpty) {
        _videoThumbnailCache[mediaPath] = bytes;
      }
      return bytes;
    }();

    _videoThumbnailFutureCache[mediaPath] = future;
    future.whenComplete(() {
      _videoThumbnailFutureCache.remove(mediaPath);
    });
    return future;
  }

  void _primeVideoThumbnailFromLocalPath({
    required String mediaPath,
    required String localPath,
  }) {
    unawaited(() async {
      final localFile = File(localPath);
      if (!await localFile.exists()) {
        return;
      }
      final bytes = await _buildVideoThumbnailFromLocalPath(localPath);
      if (!mounted || bytes == null || bytes.isEmpty) {
        return;
      }
      setState(() {
        _videoThumbnailCache[mediaPath] = bytes;
      });
    }());
  }

  Widget _buildFileTransferProgress({
    required String mediaPath,
    required Color textColor,
  }) {
    final progress = _mediaDownloadProgress(mediaPath);
    final hasTotal = (_mediaDownloadTotalBytes[mediaPath] ?? 0) > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: LinearProgressIndicator(
              value: hasTotal ? progress : null,
              minHeight: 6,
              backgroundColor: textColor.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(
                textColor.withValues(alpha: 0.9),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _mediaDownloadProgressLabel(mediaPath),
            style: TextStyle(
              color: textColor.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _setMediaTransferStatus(String status) {
    if (!mounted) {
      return;
    }
    setState(() {
      _mediaTransferStatus = status.trim();
    });
  }

  void _startPreparingMediaUi({
    required String displayFileName,
    required bool isVideo,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isPreparingMedia = true;
      _isSendingMedia = false;
      _uploadingMediaName = displayFileName;
      _mediaTransferIsVideo = isVideo;
      _mediaTransferStatus = 'Preparazione file...';
      _mediaTransferPreviewBytes = null;
      _uploadProgressSentBytes = 0;
      _uploadProgressTotalBytes = 0;
    });
  }

  Future<Uint8List?> _buildImagePreviewBytes(String localPath) async {
    try {
      final previewBytes = await FlutterImageCompress.compressWithFile(
        localPath,
        quality: 48,
        minWidth: 360,
        minHeight: 360,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (previewBytes != null && previewBytes.isNotEmpty) {
        return previewBytes;
      }
    } catch (_) {
      // Fallback below.
    }
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPreparingMediaPreview({
    required String localPath,
    required bool isImage,
    required bool isVideo,
    required String displayFileName,
  }) async {
    Uint8List? bytes;
    if (isVideo) {
      bytes = await _buildVideoThumbnailFromLocalPath(localPath);
    } else if (isImage) {
      bytes = await _buildImagePreviewBytes(localPath);
    }
    if (!mounted) {
      return;
    }
    if (_uploadingMediaName != displayFileName) {
      return;
    }
    if (!_isPreparingMedia && !_isSendingMedia) {
      return;
    }
    setState(() {
      _mediaTransferPreviewBytes = bytes;
    });
  }

  String _replaceFileExtension(String fileName, String newExt) {
    final cleanName = fileName.trim();
    final ext = newExt.trim().toLowerCase();
    if (cleanName.isEmpty || ext.isEmpty) {
      return cleanName;
    }
    final dotIndex = cleanName.lastIndexOf('.');
    final base =
        dotIndex > 0 ? cleanName.substring(0, dotIndex).trim() : cleanName;
    return '$base.$ext';
  }

  Future<String> _compressImageForChatUpload(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return sourcePath;
      }
      final sourceBytes = await sourceFile.length();
      if (sourceBytes <= _imageCompressionThresholdBytes) {
        return sourcePath;
      }
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          '${tempDir.path}/chat_img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        format: CompressFormat.jpeg,
        quality: _imageCompressionQuality,
        minWidth: _imageCompressionMaxDimension,
        minHeight: _imageCompressionMaxDimension,
        keepExif: false,
      );
      final compressedPath = compressed?.path ?? '';
      if (compressedPath.isEmpty) {
        return sourcePath;
      }
      final compressedFile = File(compressedPath);
      if (!await compressedFile.exists()) {
        return sourcePath;
      }
      final compressedBytes = await compressedFile.length();
      if (compressedBytes <= 0 || compressedBytes >= sourceBytes) {
        try {
          await compressedFile.delete();
        } catch (_) {}
        return sourcePath;
      }
      return compressedPath;
    } catch (_) {
      return sourcePath;
    }
  }

  Future<String> _compressVideoForChatUpload(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return sourcePath;
      }
      final sourceBytes = await sourceFile.length();
      if (sourceBytes <= _videoCompressionThresholdBytes) {
        return sourcePath;
      }
      final sourceExt = _fileExtensionFromName(sourcePath);
      if (sourceExt.isEmpty || !_videoExtensions.contains(sourceExt)) {
        return sourcePath;
      }
      final info = await VideoCompress.compressVideo(
        sourcePath,
        quality: VideoQuality.MediumQuality,
        includeAudio: true,
        deleteOrigin: false,
        frameRate: 24,
      ).timeout(const Duration(seconds: 40));
      final compressedPath = info?.file?.path ?? '';
      if (compressedPath.isEmpty) {
        return sourcePath;
      }
      final compressedFile = File(compressedPath);
      if (!await compressedFile.exists()) {
        return sourcePath;
      }
      final compressedBytes = await compressedFile.length();
      if (compressedBytes <= 0 || compressedBytes >= sourceBytes) {
        if (compressedPath != sourcePath) {
          try {
            await compressedFile.delete();
          } catch (_) {}
        }
        return sourcePath;
      }
      return compressedPath;
    } on TimeoutException {
      try {
        await VideoCompress.cancelCompression();
      } catch (_) {
        // Ignore cancellation failures.
      }
      return sourcePath;
    } catch (_) {
      return sourcePath;
    }
  }

  Future<_PreparedMediaUpload> _prepareMediaForUpload({
    required String localPath,
    required String kind,
    required String displayFileName,
    void Function(String status)? onStatus,
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    var uploadPath = localPath;
    var uploadFileName = displayFileName;
    var shouldDeleteUploadFile = false;
    onStatus?.call('Analisi file...');

    if (normalizedKind == 'image') {
      try {
        final sourceFile = File(localPath);
        if (await sourceFile.exists()) {
          final sourceBytes = await sourceFile.length();
          if (sourceBytes > _imageCompressionThresholdBytes) {
            onStatus?.call('Compressione foto in corso...');
          } else {
            onStatus?.call('Foto pronta, avvio invio...');
          }
        }
      } catch (_) {
        // Best effort.
      }
      final compressedPath = await _compressImageForChatUpload(localPath);
      if (compressedPath != localPath) {
        uploadPath = compressedPath;
        uploadFileName = _replaceFileExtension(displayFileName, 'jpg');
        shouldDeleteUploadFile = true;
        onStatus?.call('Foto compressa, avvio invio...');
      }
    } else {
      final isVideo =
          _isVideoFileName(displayFileName) || _isVideoFileName(localPath);
      if (isVideo) {
        var shouldAttemptCompression = false;
        try {
          final sourceFile = File(localPath);
          if (await sourceFile.exists()) {
            final sourceBytes = await sourceFile.length();
            if (sourceBytes > _videoCompressionThresholdBytes) {
              shouldAttemptCompression = true;
              onStatus?.call('Compressione video in corso...');
            } else {
              onStatus?.call('Video pronto, avvio invio...');
            }
          }
        } catch (_) {
          // Best effort.
        }
        final compressedPath = await _compressVideoForChatUpload(localPath);
        if (compressedPath != localPath) {
          uploadPath = compressedPath;
          final compressedExt = _fileExtensionFromName(compressedPath);
          if (compressedExt.isNotEmpty) {
            uploadFileName =
                _replaceFileExtension(displayFileName, compressedExt);
          }
          shouldDeleteUploadFile = true;
          onStatus?.call('Video compresso, avvio invio...');
        } else if (shouldAttemptCompression) {
          onStatus?.call('Invio originale (compressione saltata)...');
        }
      } else {
        onStatus?.call('Preparazione allegato...');
      }
    }

    return _PreparedMediaUpload(
      uploadPath: uploadPath,
      previewPath: localPath,
      uploadFileName: uploadFileName,
      shouldDeleteUploadFile: shouldDeleteUploadFile,
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
      final isVideo = _isVideoFileName(fileName) || _isVideoFileName(localPath);
      _startPreparingMediaUi(
        displayFileName: fileName,
        isVideo: isVideo,
      );
      unawaited(
        _loadPreparingMediaPreview(
          localPath: localPath,
          isImage: kind == 'image',
          isVideo: isVideo,
          displayFileName: fileName,
        ),
      );
      final prepared = await _prepareMediaForUpload(
        localPath: localPath,
        kind: kind,
        displayFileName: fileName,
        onStatus: _setMediaTransferStatus,
      );
      await _sendMediaMessage(
        uploadPath: prepared.uploadPath,
        previewPath: prepared.previewPath,
        kind: kind,
        displayFileName: prepared.uploadFileName,
        deleteUploadAfterSend: prepared.shouldDeleteUploadFile,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isPreparingMedia = false;
          _isSendingMedia = false;
          _mediaTransferStatus = '';
          _mediaTransferPreviewBytes = null;
          _uploadingMediaName = '';
        });
      }
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
      _startPreparingMediaUi(
        displayFileName: fileName,
        isVideo: false,
      );
      unawaited(
        _loadPreparingMediaPreview(
          localPath: photo.path,
          isImage: true,
          isVideo: false,
          displayFileName: fileName,
        ),
      );
      final prepared = await _prepareMediaForUpload(
        localPath: photo.path,
        kind: 'image',
        displayFileName: fileName,
        onStatus: _setMediaTransferStatus,
      );
      await _sendMediaMessage(
        uploadPath: prepared.uploadPath,
        previewPath: prepared.previewPath,
        kind: 'image',
        displayFileName: prepared.uploadFileName,
        deleteUploadAfterSend: prepared.shouldDeleteUploadFile,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isPreparingMedia = false;
          _isSendingMedia = false;
          _mediaTransferStatus = '';
          _mediaTransferPreviewBytes = null;
          _uploadingMediaName = '';
        });
      }
      _showSnack('Non riesco ad aprire la fotocamera.');
    }
  }

  Future<void> _onComposerMediaActionSelected(
    _ChatComposerMediaAction action,
  ) async {
    switch (action) {
      case _ChatComposerMediaAction.file:
        await _pickAndSendAttachment();
        break;
      case _ChatComposerMediaAction.camera:
        await _captureAndSendImage();
        break;
      case _ChatComposerMediaAction.voice:
        await _startVoiceRecording();
        break;
    }
  }

  Future<void> _showMessageActions(Map<String, dynamic> data) async {
    if (!mounted) {
      return;
    }
    final canSave = _canSaveMessageAttachment(data);
    final selected = await showModalBottomSheet<_ChatMessageAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (canSave)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Salva file sul dispositivo'),
                onTap: () => Navigator.of(context).pop(
                  _ChatMessageAction.saveAttachment,
                ),
              ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Elimina per me'),
              onTap: () =>
                  Navigator.of(context).pop(_ChatMessageAction.hideForMe),
            ),
          ],
        ),
      ),
    );
    switch (selected) {
      case _ChatMessageAction.saveAttachment:
        await _saveMessageAttachmentLocally(data);
        break;
      case _ChatMessageAction.hideForMe:
        await _hideMessageForMe(data);
        break;
      case null:
        break;
    }
  }

  Future<void> _saveMessageAttachmentLocally(Map<String, dynamic> data) async {
    final offerId = _parsedOfferId;
    final otherUserId = _parsedOtherUserId;
    if (offerId == null ||
        offerId <= 0 ||
        otherUserId == null ||
        otherUserId <= 0) {
      _showSnack('Dati evento non validi per salvare l\'allegato.');
      return;
    }

    final type = data['type']?.toString().toLowerCase().trim() ?? '';
    try {
      String localPath;
      if (type == 'audio') {
        final audioPath = data['audioPath']?.toString().trim() ?? '';
        if (audioPath.isEmpty) {
          _showSnack('Audio non disponibile.');
          return;
        }
        localPath = await _ensureCachedAudioFile(
          offerId: offerId,
          otherUserId: otherUserId,
          audioPath: audioPath,
        );
      } else if (type == 'image' || type == 'file') {
        final mediaPath = data['mediaPath']?.toString().trim() ?? '';
        if (mediaPath.isEmpty) {
          _showSnack('Allegato non disponibile.');
          return;
        }
        final fileName = data['mediaFileName']?.toString().trim() ?? '';
        localPath = await _ensureCachedMediaFile(
          offerId: offerId,
          otherUserId: otherUserId,
          mediaPath: mediaPath,
          fileName: fileName,
        );
      } else {
        _showSnack('Questo messaggio non contiene un file da salvare.');
        return;
      }

      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: localPath,
          fileName: _downloadFileNameForMessage(data),
        ),
      );

      if (!mounted) {
        return;
      }
      if (savedPath == null || savedPath.trim().isEmpty) {
        _showSnack('Salvataggio annullato.');
        return;
      }
      _showSnack('File salvato sul dispositivo.');
    } catch (_) {
      _showSnack('Non riesco a salvare questo file. Riprova.');
    }
  }

  Future<void> _sendMediaMessage({
    required String uploadPath,
    required String previewPath,
    required String kind,
    required String displayFileName,
    bool deleteUploadAfterSend = false,
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    if (normalizedKind != 'image' && normalizedKind != 'file') {
      _showSnack('Tipo allegato non valido.');
      return;
    }
    if (_isSendingAudio || _isSendingMedia || _isRecording) {
      return;
    }
    if (!await _ensureCanSendChat()) {
      return;
    }

    if (mounted) {
      setState(() {
        _isPreparingMedia = false;
        _isSendingMedia = true;
        _uploadingMediaName = displayFileName;
        _mediaTransferStatus = 'Upload in corso...';
        _uploadProgressSentBytes = 0;
        _uploadProgressTotalBytes = 0;
      });
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

      final uploadPayload = await widget.apiClient.uploadChatMedia(
        offerId: offerId,
        receiverId: receiverId,
        filePath: uploadPath,
        kind: normalizedKind,
        fileName: displayFileName,
        onProgress: (sentBytes, totalBytes) {
          if (!mounted) {
            return;
          }
          setState(() {
            _mediaTransferStatus = 'Upload in corso...';
            _uploadProgressSentBytes = sentBytes;
            _uploadProgressTotalBytes = totalBytes;
          });
        },
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
      _mediaFileCache[mediaPath] = previewPath;
      if (kindFromServer == 'file' && _isVideoFileName(fileName)) {
        _primeVideoThumbnailFromLocalPath(
          mediaPath: mediaPath,
          localPath: previewPath,
        );
      }

      final previewText = kindFromServer == 'image'
          ? 'Foto inviata'
          : 'Allegato: ${fileName.isNotEmpty ? fileName : "file"}';

      await widget.apiClient.sendChatMessage(
        offerId: offerId,
        receiverId: receiverId,
        type: kindFromServer == 'image' ? 'image' : 'file',
        text: previewText,
        mediaPath: mediaPath,
        mediaFileName: fileName,
        mediaContentType: contentType,
        mediaSizeBytes: bytes,
      );
      await _refreshMessages(silent: true);

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
      if (deleteUploadAfterSend && uploadPath != previewPath) {
        try {
          final tempUpload = File(uploadPath);
          if (await tempUpload.exists()) {
            await tempUpload.delete();
          }
        } catch (_) {
          // Best effort cleanup.
        }
      }
      try {
        await VideoCompress.deleteAllCache();
      } catch (_) {
        // Best effort cleanup.
      }
      if (mounted) {
        setState(() {
          _isPreparingMedia = false;
          _isSendingMedia = false;
          _uploadingMediaName = '';
          _mediaTransferStatus = '';
          _mediaTransferIsVideo = false;
          _mediaTransferPreviewBytes = null;
          _uploadProgressSentBytes = 0;
          _uploadProgressTotalBytes = 0;
        });
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

  DateTime _messageDateTime(Map<String, dynamic> data) {
    return _parseMessageTimestamp(data['timestamp']) ?? DateTime.now();
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _shouldShowDaySeparator({
    required List<Map<String, dynamic>> messages,
    required int index,
  }) {
    final currentAt = _messageDateTime(messages[index]);
    if (index == messages.length - 1) {
      return true;
    }
    final olderAt = _messageDateTime(messages[index + 1]);
    return !_isSameCalendarDay(currentAt, olderAt);
  }

  String _daySeparatorLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diffDays = today.difference(target).inDays;
    if (diffDays == 0) {
      return 'Oggi';
    }
    if (diffDays == 1) {
      return 'Ieri';
    }
    const months = <String>[
      'gen',
      'feb',
      'mar',
      'apr',
      'mag',
      'giu',
      'lug',
      'ago',
      'set',
      'ott',
      'nov',
      'dic',
    ];
    final month = months[(date.month - 1).clamp(0, 11)];
    return '${date.day} $month ${date.year}';
  }

  String _messageTimeLabel(Map<String, dynamic> data) {
    final date = _messageDateTime(data);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}';
  }

  Widget _buildDaySeparator(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.paper.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Text(
            _daySeparatorLabel(date),
            style: const TextStyle(
              color: AppTheme.brown,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageMeta({
    required Map<String, dynamic> data,
    required bool isMe,
  }) {
    final time = _messageTimeLabel(data);
    final color = isMe
        ? Colors.white.withValues(alpha: _isMusicAiDark ? 0.76 : 0.68)
        : (_isMusicAiDark
            ? const Color(0xFFD5DFFF).withValues(alpha: 0.74)
            : AppTheme.brown.withValues(alpha: 0.66));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 3),
          Icon(
            Icons.done_rounded,
            size: 12,
            color: color,
          ),
        ],
      ],
    );
  }

  Future<void> _openFileAttachment(Map<String, dynamic> data) async {
    final mediaPath = data['mediaPath']?.toString().trim() ?? '';
    if (mediaPath.isEmpty) {
      _showSnack('Allegato non disponibile.');
      return;
    }
    if (_isMediaDownloadInProgress(mediaPath)) {
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
      if (mounted) {
        setState(() {
          _mediaDownloadSentBytes[mediaPath] = 0;
          _mediaDownloadTotalBytes[mediaPath] = 0;
        });
      }
      final localPath = await _ensureCachedMediaFile(
        offerId: offerId,
        otherUserId: otherUserId,
        mediaPath: mediaPath,
        fileName: fileName,
        onProgress: (sentBytes, totalBytes) {
          if (!mounted) {
            return;
          }
          setState(() {
            _mediaDownloadSentBytes[mediaPath] = sentBytes;
            _mediaDownloadTotalBytes[mediaPath] = totalBytes;
          });
        },
      );
      if (_isVideoMessage(data)) {
        _primeVideoThumbnailFromLocalPath(
          mediaPath: mediaPath,
          localPath: localPath,
        );
      }
      final result = await OpenFilex.open(localPath);
      if (result.type != ResultType.done) {
        _showSnack('Impossibile aprire il file sul dispositivo.');
      }
    } on ApiException catch (e) {
      _showSnack(
          e.message.isNotEmpty ? e.message : 'Download allegato non riuscito.');
    } catch (_) {
      _showSnack('Impossibile aprire questo allegato.');
    } finally {
      if (mounted) {
        setState(() {
          _mediaDownloadSentBytes.remove(mediaPath);
          _mediaDownloadTotalBytes.remove(mediaPath);
        });
      }
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

      final uploadPayload = await widget.apiClient.uploadChatAudio(
        offerId: offerId,
        receiverId: receiverId,
        filePath: localPath,
      );
      final storagePath = uploadPayload['audio_path']?.toString().trim() ?? '';
      if (storagePath.isEmpty) {
        throw Exception('Audio caricato ma path mancante.');
      }

      await widget.apiClient.sendChatMessage(
        offerId: offerId,
        receiverId: receiverId,
        type: 'audio',
        text: previewText,
        audioPath: storagePath,
        audioDurationSec: durationSec,
      );
      await _refreshMessages(silent: true);

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

      final localFilePath = await _ensureCachedAudioFile(
        offerId: offerId,
        otherUserId: otherUserId,
        audioPath: audioPath,
      );

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
    final textColor = isMe
        ? Colors.white
        : (_isMusicAiDark ? const Color(0xFFEAF0FF) : AppTheme.espresso);
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
                width: 148,
                height: 148,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 148,
                  height: 148,
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
      final mediaPath = data['mediaPath']?.toString().trim() ?? '';
      final fileName =
          (data['mediaFileName']?.toString().trim().isNotEmpty == true)
              ? data['mediaFileName'].toString().trim()
              : 'Allegato';
      final isVideo = _isVideoMessage(data);
      final sizeBytes = data['mediaSizeBytes'] is num
          ? (data['mediaSizeBytes'] as num).toInt()
          : int.tryParse(data['mediaSizeBytes']?.toString() ?? '') ?? 0;
      final sizeLabel = _formatBytes(sizeBytes);
      final hasProgress =
          mediaPath.isNotEmpty && _isMediaDownloadInProgress(mediaPath);

      if (isVideo) {
        final thumbnailFuture =
            mediaPath.isNotEmpty && offerId != null && otherUserId != null
                ? _videoThumbnailForMediaPath(
                    offerId: offerId,
                    otherUserId: otherUserId,
                    mediaPath: mediaPath,
                    fileName: fileName,
                  )
                : Future<Uint8List?>.value(null);
        return InkWell(
          onTap: () => _openFileAttachment(data),
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 118,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 118,
                    height: 70,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FutureBuilder<Uint8List?>(
                          future: thumbnailFuture,
                          builder: (context, snapshot) {
                            final bytes = snapshot.data;
                            if (bytes != null && bytes.isNotEmpty) {
                              return Image.memory(
                                bytes,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              );
                            }
                            return Container(
                              color: textColor.withValues(alpha: 0.18),
                              alignment: Alignment.center,
                                child: Icon(
                                  Icons.movie_creation_outlined,
                                size: 20,
                                  color: textColor.withValues(alpha: 0.9),
                                ),
                            );
                          },
                        ),
                        Container(
                          color: Colors.black.withValues(alpha: 0.18),
                        ),
                        Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            size: 28,
                            color: Colors.white.withValues(alpha: 0.94),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.62),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'VIDEO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (hasProgress) ...[
                  _buildFileTransferProgress(
                    mediaPath: mediaPath,
                    textColor: textColor,
                  ),
                ],
              ],
            ),
          ),
        );
      }

      return InkWell(
        onTap: () => _openFileAttachment(data),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
            if (hasProgress) ...[
              _buildFileTransferProgress(
                mediaPath: mediaPath,
                textColor: textColor,
              ),
            ],
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
              color: _chatInputSurface,
              border: Border.all(color: _chatInputBorder),
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

  // ignore: unused_element
  Widget _buildMediaUploadingComposer() {
    final progress = _uploadProgress;
    final progressPercent = (progress * 100).round();
    final displayName = _uploadingMediaName.trim().isEmpty
        ? 'Allegato'
        : _uploadingMediaName.trim();
    final sentLabel = _uploadProgressSentBytes > 0
        ? _formatBytes(_uploadProgressSentBytes)
        : '';
    final totalLabel = _uploadProgressTotalBytes > 0
        ? _formatBytes(_uploadProgressTotalBytes)
        : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _chatInputSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _chatInputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.upload_file_rounded, color: AppTheme.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Caricamento: $displayName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.brown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _uploadProgressTotalBytes > 0 ? progress : null,
              minHeight: 7,
              backgroundColor: AppTheme.mist,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.orange),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _uploadProgressTotalBytes > 0
                ? '$progressPercent%${sentLabel.isNotEmpty && totalLabel.isNotEmpty ? " • $sentLabel / $totalLabel" : ""}'
                : 'Preparazione upload...',
            style: TextStyle(
              color: AppTheme.brown.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTransferComposer() {
    final isPreparingOnly = _isPreparingMedia && !_isSendingMedia;
    final progress = _uploadProgress;
    final progressPercent = (progress * 100).round();
    final displayName = _uploadingMediaName.trim().isEmpty
        ? 'Allegato'
        : _uploadingMediaName.trim();
    final sentLabel = _uploadProgressSentBytes > 0
        ? _formatBytes(_uploadProgressSentBytes)
        : '';
    final totalLabel = _uploadProgressTotalBytes > 0
        ? _formatBytes(_uploadProgressTotalBytes)
        : '';
    final statusLabel = _mediaTransferStatus.trim().isNotEmpty
        ? _mediaTransferStatus.trim()
        : (isPreparingOnly ? 'Preparazione file...' : 'Upload in corso...');

    final previewWidget = _mediaTransferPreviewBytes != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              _mediaTransferPreviewBytes!,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 52,
                height: 52,
                color: AppTheme.mist,
                child: Icon(
                  _mediaTransferIsVideo
                      ? Icons.videocam_rounded
                      : Icons.insert_drive_file_rounded,
                  color: AppTheme.brown.withValues(alpha: 0.7),
                ),
              ),
            ),
          )
        : Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.mist,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Icon(
              _mediaTransferIsVideo
                  ? Icons.videocam_rounded
                  : Icons.insert_drive_file_rounded,
              color: AppTheme.brown.withValues(alpha: 0.8),
            ),
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _chatInputSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _chatInputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              previewWidget,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.brown,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.brown.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppTheme.orange),
                  value:
                      isPreparingOnly ? null : (progress > 0 ? progress : null),
                ),
              ),
            ],
          ),
          if (!isPreparingOnly) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _uploadProgressTotalBytes > 0 ? progress : null,
                minHeight: 7,
                backgroundColor: AppTheme.mist,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.orange),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _uploadProgressTotalBytes > 0
                  ? '$progressPercent%${sentLabel.isNotEmpty && totalLabel.isNotEmpty ? " • $sentLabel / $totalLabel" : ""}'
                  : 'Preparazione upload...',
              style: TextStyle(
                color: AppTheme.brown.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextComposer() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _messageController,
            enabled: !_isSendingSomething,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: 1,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: _isSendingSomething
                  ? 'Invio in corso...'
                  : 'Scrivi un messaggio...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: _chatInputSurface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          backgroundColor: AppTheme.cardBorder,
          child: PopupMenuButton<_ChatComposerMediaAction>(
            enabled: !_isSendingSomething,
            tooltip: 'Multimediale',
            color: AppTheme.paper,
            surfaceTintColor: Colors.transparent,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.cardBorder),
            ),
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: AppTheme.brown,
            ),
            onSelected: (action) =>
                unawaited(_onComposerMediaActionSelected(action)),
            itemBuilder: (context) => [
              PopupMenuItem<_ChatComposerMediaAction>(
                value: _ChatComposerMediaAction.file,
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.orange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.orange.withValues(alpha: 0.28),
                        ),
                      ),
                      child: const Icon(
                        Icons.attach_file_rounded,
                        color: AppTheme.espresso,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Allega file',
                      style: TextStyle(
                        color: AppTheme.espresso,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<_ChatComposerMediaAction>(
                value: _ChatComposerMediaAction.camera,
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.orange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.orange.withValues(alpha: 0.28),
                        ),
                      ),
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        color: AppTheme.espresso,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Fotocamera',
                      style: TextStyle(
                        color: AppTheme.espresso,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<_ChatComposerMediaAction>(
                value: _ChatComposerMediaAction.voice,
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.orange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.orange.withValues(alpha: 0.28),
                        ),
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: AppTheme.espresso,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Messaggio vocale',
                      style: TextStyle(
                        color: AppTheme.espresso,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
        future: _chatBootstrapFuture,
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
                child: Builder(
                  builder: (context) {
                    if (_isLoadingMessages && _messages.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (_messagesError != null && _messages.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Errore: $_messagesError',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final visibleMessages = _messages
                        .where(_isMessageVisible)
                        .toList(growable: false);
                    if (visibleMessages.isEmpty) {
                      return Center(
                        child: Text(
                          'Nessun messaggio ancora.\nScrivi qualcosa per iniziare!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isMusicAiDark
                                ? const Color(0xFF8F9BB9)
                                : Colors.grey,
                          ),
                        ),
                      );
                    }

                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [_chatCanvasTop, _chatCanvasBottom],
                        ),
                      ),
                      child: ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        itemCount: visibleMessages.length,
                        itemBuilder: (context, index) {
                        final data = visibleMessages[index];
                        final messageId = _messageLocalId(data);
                        final isMe = data['senderId']?.toString() ==
                            widget.currentUserId.toString();
                        final type =
                            data['type']?.toString().trim().toLowerCase() ??
                                'text';
                        final isVideoBubble =
                            type == 'file' && _isVideoMessage(data);
                        final maxBubbleFactor = switch (type) {
                          'image' => 0.70,
                          'file' => isVideoBubble ? 0.46 : 0.68,
                          'audio' => 0.68,
                          _ => 0.64,
                        };
                        final bubbleColor = isVideoBubble
                            ? (isMe
                                ? _outgoingVideoBubbleColor
                                : _incomingVideoBubbleColor)
                            : (isMe
                                ? _outgoingBubbleColor
                                : _incomingBubbleColor);
                        final showDaySeparator = _shouldShowDaySeparator(
                          messages: visibleMessages,
                          index: index,
                        );
                        final messageAt = _messageDateTime(data);

                          return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showDaySeparator) _buildDaySeparator(messageAt),
                              Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            maxBubbleFactor,
                                  ),
                                  child: GestureDetector(
                                    onLongPress: () =>
                                        unawaited(_showMessageActions(data)),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            vertical: isVideoBubble ? 2 : 8,
                                            horizontal: isVideoBubble ? 3 : 11,
                                          ),
                                          decoration: BoxDecoration(
                                            color: bubbleColor,
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(18),
                                              topRight: const Radius.circular(18),
                                              bottomLeft: Radius.circular(
                                                isMe ? 18 : 6,
                                              ),
                                              bottomRight: Radius.circular(
                                                isMe ? 6 : 18,
                                              ),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.045,
                                                ),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                            border: isVideoBubble
                                                ? Border.all(
                                                    color: AppTheme.cardBorder
                                                        .withValues(
                                                      alpha: 0.55,
                                                    ),
                                                    width: 0.8,
                                                  )
                                                : null,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildMessageContent(
                                                messageId: messageId,
                                                data: data,
                                                isMe: isMe,
                                              ),
                                              if (!isVideoBubble) ...[
                                                const SizedBox(height: 4),
                                                Align(
                                                  alignment: Alignment.centerRight,
                                                  child: _buildMessageMeta(
                                                    data: data,
                                                    isMe: isMe,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (!isVideoBubble)
                                          Positioned(
                                            right: isMe ? -2 : null,
                                            left: isMe ? null : -2,
                                            bottom: 7,
                                            child: Transform.rotate(
                                              angle: math.pi / 4,
                                              child: Container(
                                                width: 7,
                                                height: 7,
                                                decoration: BoxDecoration(
                                                  color:
                                                      bubbleColor.withValues(
                                                    alpha: 0.92,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: _isMusicAiDark
                      ? const Color(0xFF0B111C)
                      : Colors.white,
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
                    : ((_isPreparingMedia || _isSendingMedia)
                        ? _buildMediaTransferComposer()
                        : (_isRecording
                            ? _buildRecordingComposer()
                            : _buildTextComposer())),
              ),
            ],
          );
        },
      ),
    );
  }
}
