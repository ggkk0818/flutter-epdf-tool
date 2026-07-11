import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ble/models.dart';
import 'ble_providers.dart';

class DocumentListNotifier
    extends StateNotifier<AsyncValue<List<DocumentMeta>>> {
  DocumentListNotifier(this._ref) : super(const AsyncValue.loading());

  final Ref _ref;

  Future<void> refresh() async {
    final conn = _ref.read(activeConnectionProvider).valueOrNull?.connection;
    if (conn == null) {
      state = const AsyncValue.error('设备未连接', StackTrace.empty);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final list = await _ref.read(bleServiceProvider).fetchDocumentList(conn);
      state = AsyncValue.data(list);
    } on Object catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final documentListProvider = StateNotifierProvider<DocumentListNotifier,
    AsyncValue<List<DocumentMeta>>>((ref) {
  return DocumentListNotifier(ref);
});
