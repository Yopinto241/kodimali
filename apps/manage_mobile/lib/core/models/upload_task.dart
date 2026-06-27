import 'package:storage_client/storage_client.dart';

class UploadProgressSnapshot {
  const UploadProgressSnapshot({
    required this.value,
    required this.label,
    this.canCancel = true,
  });

  final double value;
  final String label;
  final bool canCancel;
}

typedef UploadProgressCallback = void Function(
  UploadProgressSnapshot progress,
);

class UploadTaskController {
  final StorageRetryController retryController = StorageRetryController();

  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    retryController.cancel();
  }
}

class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() => "Upload cancelled.";
}
