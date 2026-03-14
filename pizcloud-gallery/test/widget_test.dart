import 'package:flutter_test/flutter_test.dart';

import 'package:pizcloud_gallery/app/pizcloud_app.dart';

void main() {
  testWidgets('PizCloud app boots and shows main navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PizCloudApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('PizCloud Photos'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Backup'), findsOneWidget);
  });
}
