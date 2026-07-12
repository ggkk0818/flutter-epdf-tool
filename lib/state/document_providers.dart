import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ble/models.dart';
import 'ble_providers.dart';

enum DocumentPageStatus {
  connecting,
  ready,
  offline,
  noDevice,
}

class DocumentListNotifier
    extends StateNotifier<AsyncValue<List<DocumentMeta>>> {
  DocumentListNotifier(this._ref) : super(const AsyncValue.loading());

  final Ref _ref;

  Future<void> refresh() async {
    final conn = _ref.read(activeConnectionProvider).valueOrNull?.connection;
    if (conn == null) {
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

final documentPageStatusProvider = Provider<DocumentPageStatus>((ref) {
  final currentDeviceId = ref.watch(currentDeviceIdProvider);
  if (currentDeviceId == null || currentDeviceId.isEmpty) {
    return DocumentPageStatus.noDevice;
  }

  final activeConnection = ref.watch(activeConnectionProvider);
  if (activeConnection.isLoading) {
    return DocumentPageStatus.connecting;
  }

  final current = activeConnection.valueOrNull;
  if (current?.connection != null && current?.isOffline == false) {
    return DocumentPageStatus.ready;
  }

  return DocumentPageStatus.offline;
});
