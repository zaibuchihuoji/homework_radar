import 'dart:io';

/// Only remove test-owned temporary directories after resolving both paths.
Future<void> deleteTestDirectory(Directory directory) async {
  final root = await Directory.systemTemp.resolveSymbolicLinks();
  final target = await directory.resolveSymbolicLinks();
  if (!target.toLowerCase().startsWith(
    '${root.toLowerCase()}${Platform.pathSeparator}',
  )) {
    throw StateError(
      'Refusing to remove a test directory outside the temp root',
    );
  }
  await directory.delete(recursive: true);
}
