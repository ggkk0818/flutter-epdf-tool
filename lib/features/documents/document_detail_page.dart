import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/ble/models.dart';

class DocumentDetailPage extends StatelessWidget {
  const DocumentDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = GoRouterState.of(context).extra as DocumentMeta?;
    final title = (meta?.name.isEmpty ?? true) ? '文档详情' : meta!.name;
    final pages = meta?.pages ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: pages == 0
          ? Center(
              child: Text(
                '文档没有页面',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              itemCount: pages,
              itemBuilder: (BuildContext context, int index) {
                return Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '第${index + 1}页',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
