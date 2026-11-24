// מטא-דאטה של שני קובצי ה-exe: מה ש-SmartScreen ומנועי אנטי-וירוס מציגים
// ומשקללים, ואין לו שום בדיקה אחרת (#319, #320).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'הבדיקה רצה משורש החבילה: $path');
    return file.readAsStringSync();
  }

  const manifestPaths = [
    'windows/runner/runner.exe.manifest',
    'windows_stub/stub.exe.manifest',
  ];
  const resourcePaths = ['windows/runner/Runner.rc', 'windows_stub/stub.rc'];

  for (final path in manifestPaths) {
    test('$path מצהיר asInvoker במפורש', () {
      expect(
        read(path),
        contains('requestedExecutionLevel level="asInvoker"'),
      );
    });
  }

  for (final path in resourcePaths) {
    test('$path: CompanyName הוא שם הפרויקט ולא מזהה חבילה', () {
      final rc = read(path);
      expect(rc, contains('VALUE "CompanyName", "Otzaria"'));
      expect(rc, isNot(contains('org.otzaria')));
    });
  }
}
