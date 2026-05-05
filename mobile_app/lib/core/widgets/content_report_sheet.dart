import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../theme/app_theme.dart';

Future<bool> showContentReportSheet({
  required BuildContext context,
  required ApiClient apiClient,
  required String title,
  required String targetType,
  int? targetId,
  int? reportedUserId,
  int? offerId,
  int? chatThreadId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final controller = TextEditingController();
      var isSending = false;

      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> submit() async {
            final message = controller.text.trim();
            if (message.length < 8) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                const SnackBar(
                  content: Text('Scrivi almeno qualche parola.'),
                ),
              );
              return;
            }
            setSheetState(() => isSending = true);
            try {
              final resultMessage = await apiClient.submitContentReport(
                targetType: targetType,
                targetId: targetId,
                reportedUserId: reportedUserId,
                offerId: offerId,
                chatThreadId: chatThreadId,
                message: message,
              );
              if (!sheetContext.mounted) {
                return;
              }
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text(resultMessage)),
              );
              Navigator.of(sheetContext).pop(true);
            } on ApiException catch (error) {
              if (!sheetContext.mounted) {
                return;
              }
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text(error.message)),
              );
              setSheetState(() => isSending = false);
            } catch (_) {
              if (!sheetContext.mounted) {
                return;
              }
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                const SnackBar(
                  content: Text('Non riesco a inviare la segnalazione adesso.'),
                ),
              );
              setSheetState(() => isSending = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 18,
              bottom: MediaQuery.of(context).viewInsets.bottom + 18,
            ),
            child: Material(
              color: AppTheme.cream,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.cardBorder,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppTheme.espresso,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Descrivi cosa non va. La segnalazione arriva solo all\'admin e verra verificata.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.brown.withValues(alpha: 0.78),
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: 4,
                      maxLines: 7,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Motivo della segnalazione',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: isSending ? null : submit,
                      icon: isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.report_problem_rounded),
                      label: Text(
                        isSending ? 'Invio in corso...' : 'Invia segnalazione',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
  return result == true;
}
