import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/main.dart';

void main() {
  testWidgets('renders queue monitor shell', (WidgetTester tester) async {
    await tester.pumpWidget(const StemFlutterExampleApp());
    await tester.pump();

    expect(find.text('Stem Queue Monitor'), findsOneWidget);
    expect(find.text('Push Job'), findsOneWidget);
  });
}
