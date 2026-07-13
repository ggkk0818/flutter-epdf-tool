import 'package:epdf_tool/shared/storage/storage_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatStorageSize', () {
    test('keeps MB at or below the gigabyte display threshold', () {
      expect(formatStorageSize(1000), '1000 MB');
    });

    test('switches to GB above 1000 MB', () {
      expect(formatStorageSize(1001), '1 GB');
      expect(formatStorageSize(1536), '1.5 GB');
    });

    test('switches to TB only above 1024 GB', () {
      expect(formatStorageSize(1024 * 1024), '1024 GB');
      expect(formatStorageSize(1536 * 1024), '1.5 TB');
    });
  });

  test('formats storage usage with independently scaled units', () {
    expect(formatStorageUsage(900, 1536), '900 MB/1.5 GB');
  });
}