// Basic Flutter widget test for tv_app_books.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tv_app_books/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
