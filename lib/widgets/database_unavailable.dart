import 'package:flutter/material.dart';

class DatabaseUnavailable extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const DatabaseUnavailable({super.key, this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.storage_outlined,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('OptimalOrganizer could not open its database',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              if (message != null) ...[
                const SizedBox(height: 8),
                SelectableText(message!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry')),
            ]),
          ),
        ),
      );
}
