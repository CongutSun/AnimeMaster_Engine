import 'package:flutter/material.dart';

import '../utils/app_strings.dart';

class ErrorStateWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const ErrorStateWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  factory ErrorStateWidget.networkError({VoidCallback? onRetry}) {
    return ErrorStateWidget(
      message: AppStrings.networkError,
      onRetry: onRetry,
      icon: Icons.wifi_off_rounded,
    );
  }

  factory ErrorStateWidget.loadFailed({VoidCallback? onRetry}) {
    return ErrorStateWidget(
      message: AppStrings.loadFailed,
      onRetry: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: colors.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(AppStrings.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
