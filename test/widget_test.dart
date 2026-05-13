import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asc_toolkit/main.dart';

void main() {
  testWidgets('빈 상태 화면이 표시된다', (WidgetTester tester) async {
    await tester.pumpWidget(const AscToolkitApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
