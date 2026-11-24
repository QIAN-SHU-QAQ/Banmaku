import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/video_model.dart';
import 'search_result_preview.dart';

Future<void> showCatalogWork(BuildContext context, VideoModel work) async {
  final findSource = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 460,
            height: 560,
            child: SearchResultPreview(
              result: work,
              onOpenDetails: () => Navigator.of(dialogContext).pop(true),
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
  );
  if (context.mounted && findSource == true) {
    openSourceSearch(context, work.title, fromCatalog: true);
  }
}

void openSourceSearch(
  BuildContext context,
  String keyword, {
  bool fromCatalog = false,
}) {
  var query = keyword.trim();
  if (fromCatalog) {
    // Some sources concatenate Chinese season labels. Keep Latin word spaces.
    query = query.replaceAll(
      RegExp(r'(?<=[\u3400-\u9fff])\s+(?=[\u3400-\u9fff])'),
      '',
    );
  }
  context.push(
    Uri(
      path: '/search',
      queryParameters: {
        'mode': 'source',
        if (fromCatalog) 'from': 'catalog',
        if (query.isNotEmpty) 'q': query,
      },
    ).toString(),
  );
}
