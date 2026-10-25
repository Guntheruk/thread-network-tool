import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared by the real isolated runtime test and its bounded layout regression.
Future<void> ensureIsolatedAction(WidgetTester tester, String key,
    {void Function()? onBlocked}) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    // ensureVisible needs an existing Element; a lazy ListView may not have
    // built this action after a large review card was inserted above it.
    final scrollable = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 250,
        scrollable: scrollable, maxScrolls: 40);
  }
  expect(finder, findsOneWidget, reason: 'isolated action must exist');
  await tester.ensureVisible(finder);
  await tester.pump();
  final action = tester.widget(finder);
  final enabled = switch (action) {
    ButtonStyleButton button => button.onPressed != null,
    CheckboxListTile checkbox => checkbox.onChanged != null,
    ListTile tile => tile.enabled && tile.onTap != null,
    _ => false,
  };
  if (!enabled) {
    onBlocked?.call();
    throw StateError('isolated UI action is disabled');
  }
}
