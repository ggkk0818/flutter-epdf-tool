import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epdf_tool/app.dart';

void main() {
  testWidgets('document page is the default route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: EpdfToolApp()));
    await tester.pumpAndSettle();

    expect(find.text('文档'), findsWidgets);
    expect(find.byType(BottomAppBar), findsOneWidget);
    expect(find.text('遥控'), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
  });
}
