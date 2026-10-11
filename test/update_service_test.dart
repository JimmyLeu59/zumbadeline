import 'package:flutter_test/flutter_test.dart';
import 'package:zumbadeline/core/updates/update_service.dart';

void main() {
  test('compareVersions', () {
    expect(compareVersions('v0.2.0', '0.1.0+1'), greaterThan(0));
    expect(compareVersions('0.1.0', '0.1.0+5'), 0);
    expect(compareVersions('0.1.9', '0.2'), lessThan(0));
  });
}
