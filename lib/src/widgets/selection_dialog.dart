import 'package:flutter/material.dart';

/// A reusable modal bottom sheet / dialog for presenting a list of options
/// to the user.  Replaces hand‑written [AlertDialog] instances across the app.
class SelectionItem {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool enabled;

  const SelectionItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });
}

Future<void> showSelectionSheet(
  BuildContext context, {
  required String title,
  required List<SelectionItem> items,
}) {
  final ThemeData theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              ...items.map((SelectionItem item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: item.enabled
                          ? () {
                              Navigator.pop(sheetContext);
                              item.onTap();
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Row(
                        children: <Widget>[
                          if (item.icon != null) ...[
                            Icon(item.icon, size: 20),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: item.enabled ? null : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (item.enabled)
                            const Icon(Icons.chevron_right_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}
