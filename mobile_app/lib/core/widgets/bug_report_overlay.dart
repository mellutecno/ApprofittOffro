import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  static const double _buttonWidth = 156;
  static const double _buttonHeight = 50;
  double? _left;
  double? _top;
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

  void _move(DragUpdateDetails details, BoxConstraints constraints) {
    final mediaQuery = MediaQuery.of(context);
    const minLeft = 12.0;
    final maxLeft = math.max(minLeft, constraints.maxWidth - _buttonWidth - 12);
    final minTop = mediaQuery.viewPadding.top + 12;
    final maxTop = math.max(
      minTop,
      constraints.maxHeight -
          _buttonHeight -
          mediaQuery.viewPadding.bottom -
          92,
    );
    setState(() {
      _left = ((_left ?? maxLeft) + details.delta.dx).clamp(minLeft, maxLeft);
      _top = ((_top ?? maxTop) + details.delta.dy).clamp(minTop, maxTop);
    });
  }

  Future<void> _openDialog() async {
    if (_dialogOpen) {
      return;
    }
    setState(() => _dialogOpen = true);
    final controller = TextEditingController();
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
                title: const Text('Segnala un bug'),
                content: Column(
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
                        hintText: 'Esempio: non riesco ad aprire la chat...',
                      ),
                    ),
                  ],
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
                              final result = await widget.apiClient
                                  .submitBugReport(message: message);
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
        setState(() => _dialogOpen = false);
      }
    }
    if (sent == true && mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        const minLeft = 12.0;
        final minTop = mediaQuery.viewPadding.top + 12;
        final maxLeft =
            math.max(minLeft, constraints.maxWidth - _buttonWidth - 12);
        final maxTop = math.max(
          minTop,
          constraints.maxHeight -
              _buttonHeight -
              mediaQuery.viewPadding.bottom -
              92,
        );
        final left = (_left ?? maxLeft).clamp(minLeft, maxLeft);
        final top = (_top ?? maxTop).clamp(minTop, maxTop);

        return Stack(
          children: [
            widget.child,
            if (!_dialogOpen)
              Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  onPanUpdate: (details) => _move(details, constraints),
                  onTap: _openDialog,
                  child: Tooltip(
                    message: 'Segnala un bug',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.accentGradient,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.vividViolet.withValues(alpha: 0.38),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const SizedBox(
                        width: _buttonWidth,
                        height: _buttonHeight,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 15),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bug_report_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Segnala bug',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
