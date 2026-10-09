import 'package:flutter_test/flutter_test.dart';
import 'package:netguard/core/utils/validators.dart';

void main() {
  test('MAC validation', () {
    expect(isValidMac('AA:BB:CC:DD:EE:FF'), true);
    expect(isValidMac('aa-bb-cc-dd-ee-ff'), true);
    expect(isValidMac('AA:BB:CC'), false);
  });
  test('domain normalization', () {
    expect(normalizeDomain('https://www.Facebook.com/'), 'facebook.com');
    expect(normalizeDomain('youtube.com'), 'youtube.com');
    expect(normalizeDomain('not a domain'), null);
  });
}
