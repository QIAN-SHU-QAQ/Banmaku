import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/scraper_provider.dart';

class SourcePicker extends ConsumerWidget {
  const SourcePicker({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSourceConfigProvider);
    final sources = ref.watch(enabledSourcesProvider);
    final text = label ?? '片源：${active.name}';
    return PopupMenuButton<String>(
      tooltip: text,
      enabled: sources.isNotEmpty,
      initialValue: active.id,
      onSelected: ref.read(selectSourceProvider),
      itemBuilder:
          (context) => [
            for (final source in sources)
              PopupMenuItem(value: source.id, child: Text(source.name)),
          ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

Future<void> pickSourceForSearch(
  BuildContext context,
  WidgetRef ref,
  String title,
) async {
  final sources = ref.read(enabledSourcesProvider);
  final selectSource = ref.read(selectSourceProvider);
  final id = await showDialog<String>(
    context: context,
    builder:
        (dialogContext) => SimpleDialog(
          title: const Text('选择片源'),
          children: [
            for (final source in sources)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, source.id),
                child: Text(source.name),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
          ],
        ),
  );
  if (id == null || !context.mounted) return;
  await selectSource(id);
  if (!context.mounted) return;
  context.push(Uri(path: '/search', queryParameters: {'q': title}).toString());
}
