import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../network/api_client.dart';
import '../theme/app_theme.dart';

class BugReportOverlay extends StatefulWidget {
  const BugReportOverlay({
    super.key,
    required this.apiClient,
    required this.navigatorKey,
    required this.scaffoldMessengerKey,
    required this.child,
  });

  final ApiClient apiClient;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final Widget child;

  @override
  State<BugReportOverlay> createState() => _BugReportOverlayState();
}

class _BugReportOverlayState extends State<BugReportOverlay> {
  static const double _collapsedWidth = 44;
  static const double _expandedWidth = 172;
  static const double _tabHeight = 54;
  static const int _maxScreenshotBytes = 12 * 1024 * 1024;

  double? _dragLeft;
  double? _top;
  bool _dockRight = true;
  bool _expanded = false;
  bool _dialogOpen = false;

  void _showSnackBar(String message) {
    final messenger = widget.scaffoldMessengerKey.currentState;
    if (messenger == null) {
      return;
    }
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  double _tabWidth() => _expanded ? _expandedWidth : _collapsedWidth;

  double _defaultTop(BoxConstraints constraints) {
    final mediaQuery = MediaQuery.of(context);
    final minTop = mediaQuery.viewPadding.top + 96;
    final maxTop = math.max(
      minTop,
      constraints.maxHeight - _tabHeight - mediaQuery.viewPadding.bottom - 112,
    );
    return (constraints.maxHeight * 0.46).clamp(minTop, maxTop).toDouble();
  }

  double _leftForDock(BoxConstraints constraints, double width) {
    return _dockRight ? constraints.maxWidth - width : 0;
  }

  double _clampTop(double value, BoxConstraints constraints) {
    final mediaQuery = MediaQuery.of(context);
    final minTop = mediaQuery.viewPadding.top + 12;
    final maxTop = math.max(
      minTop,
      constraints.maxHeight - _tabHeight - mediaQuery.viewPadding.bottom - 92,
    );
    return value.clamp(minTop, maxTop).toDouble();
  }

  void _startMove(BoxConstraints constraints) {
    final width = _tabWidth();
    _dragLeft = _leftForDock(constraints, width);
  }

  void _move(DragUpdateDetails details, BoxConstraints constraints) {
    final width = _tabWidth();
    final maxLeft = math.max(0.0, constraints.maxWidth - width);
    setState(() {
      _dragLeft =
          ((_dragLeft ?? _leftForDock(constraints, width)) + details.delta.dx)
              .clamp(0.0, maxLeft)
              .toDouble();
      _top = _clampTop(
          (_top ?? _defaultTop(constraints)) + details.delta.dy, constraints);
    });
  }

  void _endMove(BoxConstraints constraints) {
    final width = _tabWidth();
    final left = (_dragLeft ?? _leftForDock(constraints, width))
        .clamp(0.0, math.max(0.0, constraints.maxWidth - width))
        .toDouble();
    setState(() {
      _dockRight = left + width / 2 >= constraints.maxWidth / 2;
      _dragLeft = null;
    });
  }

  Future<void> _pickScreenshot(
      StateSetter setDialogState, _AttachmentState attachment) async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (image == null) {
        return;
      }
      final file = File(image.path);
      final size = await file.length();
      if (size > _maxScreenshotBytes) {
        _showSnackBar(
            'Lo screenshot e troppo pesante. Usa un file sotto i 12 MB.');
        return;
      }
      setDialogState(() {
        attachment.path = image.path;
        attachment.name =
            image.name.isNotEmpty ? image.name : file.uri.pathSegments.last;
        attachment.size = size;
      });
    } catch (error) {
      _showSnackBar('Non riesco ad allegare lo screenshot: $error');
    }
  }

  Future<void> _openDialog() async {
    if (_dialogOpen) {
      return;
    }
    setState(() => _dialogOpen = true);
    final controller = TextEditingController();
    final attachment = _AttachmentState();
    var isSubmitting = false;
    final navigator = widget.navigatorKey.currentState;
    final dialogContext = navigator?.overlay?.context;

    if (dialogContext == null) {
      controller.dispose();
      if (mounted) {
        setState(() => _dialogOpen = false);
      }
      _showSnackBar('Non riesco ad aprire la segnalazione adesso.');
      return;
    }

    bool? sent;
    try {
      sent = await showDialog<bool>(
        context: dialogContext,
        builder: (alertContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Segnalazione bug'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Le segnalazioni vere ci aiutano a migliorare l\'app. Dopo la verifica dell\'admin possono assegnare ApprofittOffro Points, utilizzabili in futuro per vantaggi e tessere socio.',
                          style: TextStyle(
                            color: AppTheme.brown.withValues(alpha: 0.78),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: controller,
                          minLines: 4,
                          maxLines: 7,
                          maxLength: 2000,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            labelText: 'Descrivi il problema',
                            hintText:
                                'Esempio: non riesco ad aprire la chat...',
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: isSubmitting
                              ? null
                              : () => _pickScreenshot(
                                    setDialogState,
                                    attachment,
                                  ),
                          icon: const Icon(Icons.attach_file_rounded),
                          label: Text(
                            attachment.hasFile
                                ? 'Cambia screenshot'
                                : 'Allega screenshot',
                          ),
                        ),
                        if (attachment.hasFile) ...[
                          const SizedBox(height: 10),
                          _ScreenshotPreview(
                            path: attachment.path!,
                            name: attachment.name ?? 'screenshot',
                            size: attachment.size,
                            onRemove: isSubmitting
                                ? null
                                : () {
                                    setDialogState(attachment.clear);
                                  },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () => Navigator.of(alertContext).pop(false),
                    child: const Text('Annulla'),
                  ),
                  FilledButton.icon(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final message = controller.text.trim();
                            if (message.length < 5) {
                              _showSnackBar(
                                'Scrivi almeno qualche parola sul bug.',
                              );
                              return;
                            }
                            setDialogState(() => isSubmitting = true);
                            final dialogNavigator = Navigator.of(alertContext);
                            try {
                              final result =
                                  await widget.apiClient.submitBugReport(
                                message: message,
                                screenshotPath: attachment.path,
                              );
                              if (!mounted) {
                                return;
                              }
                              _showSnackBar(result);
                              if (dialogNavigator.mounted) {
                                dialogNavigator.pop(true);
                              }
                            } catch (error) {
                              if (!mounted) {
                                return;
                              }
                              setDialogState(() => isSubmitting = false);
                              _showSnackBar(error.toString());
                            }
                          },
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('Invia'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
      if (mounted) {
        setState(() {
          _dialogOpen = false;
          _expanded = false;
        });
      }
    }
    if (sent == true && mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _handleTabTap() {
    if (_expanded) {
      _openDialog();
      return;
    }
    setState(() => _expanded = true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _tabWidth();
        final left = (_dragLeft ?? _leftForDock(constraints, width))
            .clamp(0.0, math.max(0.0, constraints.maxWidth - width))
            .toDouble();
        final top = _clampTop(_top ?? _defaultTop(constraints), constraints);

        return Stack(
          children: [
            widget.child,
            if (!_dialogOpen)
              Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  onPanStart: (_) => _startMove(constraints),
                  onPanUpdate: (details) => _move(details, constraints),
                  onPanEnd: (_) => _endMove(constraints),
                  onTap: _handleTabTap,
                  child: Tooltip(
                    message: 'Segnala un bug',
                    child: _BugSideTab(
                      dockRight: _dockRight,
                      expanded: _expanded,
                      width: width,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AttachmentState {
  String? path;
  String? name;
  int size = 0;

  bool get hasFile => path != null && path!.trim().isNotEmpty;

  void clear() {
    path = null;
    name = null;
    size = 0;
  }
}

class _BugSideTab extends StatelessWidget {
  const _BugSideTab({
    required this.dockRight,
    required this.expanded,
    required this.width,
  });

  final bool dockRight;
  final bool expanded;
  final double width;

  @override
  Widget build(BuildContext context) {
    final radius = dockRight
        ? const BorderRadius.horizontal(left: Radius.circular(24))
        : const BorderRadius.horizontal(right: Radius.circular(24));
    final icon = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Icon(
        Icons.bug_report_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
    final label = Expanded(
      child: AnimatedOpacity(
        opacity: expanded ? 1 : 0,
        duration: const Duration(milliseconds: 140),
        child: const Text(
          'Segnala bug',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      height: _BugReportOverlayState._tabHeight,
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient,
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.vividViolet.withValues(alpha: 0.38),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: dockRight ? 12 : 7,
          right: dockRight ? 7 : 12,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: dockRight
              ? [
                  if (expanded) label,
                  icon,
                ]
              : [
                  icon,
                  if (expanded) label,
                ],
        ),
      ),
    );
  }
}

class _ScreenshotPreview extends StatelessWidget {
  const _ScreenshotPreview({
    required this.path,
    required this.name,
    required this.size,
    required this.onRemove,
  });

  final String path;
  final String name;
  final int size;
  final VoidCallback? onRemove;

  String get _sizeLabel {
    if (size <= 0) {
      return '';
    }
    final mb = size / (1024 * 1024);
    if (mb >= 1) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    return '${(size / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.paper.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(path),
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.brown,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_sizeLabel.isNotEmpty)
                  Text(
                    _sizeLabel,
                    style: TextStyle(
                      color: AppTheme.brown.withValues(alpha: 0.62),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Rimuovi screenshot',
          ),
        ],
      ),
    );
  }
}
