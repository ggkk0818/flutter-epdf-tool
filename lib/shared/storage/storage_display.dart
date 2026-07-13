const int _gigabyteDisplayThresholdMb = 1000;
const int _megabytesPerGigabyte = 1024;
const int _gigabytesPerTerabyte = 1024;
const int _terabyteDisplayThresholdGb = 1024;

String formatStorageUsage(int usedMb, int totalMb) {
  return '${formatStorageSize(usedMb)}/${formatStorageSize(totalMb)}';
}

String formatStorageSize(int megabytes) {
  if (megabytes > _gigabyteDisplayThresholdMb) {
    final gigabytes = megabytes / _megabytesPerGigabyte;
    if (gigabytes > _terabyteDisplayThresholdGb) {
      return '${_formatDecimal(gigabytes / _gigabytesPerTerabyte)} TB';
    }
    return '${_formatDecimal(gigabytes)} GB';
  }
  return '$megabytes MB';
}

String _formatDecimal(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}