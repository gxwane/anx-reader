import 'dart:io';
import 'package:anx_reader/utils/platform_utils.dart';

import 'package:anx_reader/utils/get_path/get_download_path.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

Future<String?> saveFileToDownload(
    {Uint8List? bytes,
    String? sourceFilePath,
    required String fileName,
    String? mimeType}) async {
  if (bytes == null && sourceFilePath == null) {
    throw ArgumentError('Either bytes or sourceFilePath must be provided');
  }

  String downloadPath = await getDownloadPath();
  String fileSavePath = '$downloadPath/$fileName';

  switch (AnxPlatform.type) {
    case AnxPlatformEnum.android:
    case AnxPlatformEnum.ios:
    case AnxPlatformEnum.ohos:
      SaveFileDialogParams params = SaveFileDialogParams(
        sourceFilePath: sourceFilePath,
        data: bytes,
        mimeTypesFilter: [mimeType ?? 'application/zip'],
        fileName: fileName,
      );
      final filePath = await FlutterFileDialog.saveFile(params: params);
      return filePath;
    case AnxPlatformEnum.macos:
      String? outputFile = await FilePicker.platform.saveFile(
        fileName: fileName,
      );
      if (outputFile != null) {
        await _writeOrCopyFile(
          outputFile,
          bytes: bytes,
          sourceFilePath: sourceFilePath,
        );
        return outputFile;
      }
      return outputFile;
    case AnxPlatformEnum.windows:
    case AnxPlatformEnum.linux:
      await _writeOrCopyFile(
        fileSavePath,
        bytes: bytes,
        sourceFilePath: sourceFilePath,
      );
      return fileSavePath;
  }
}

Future<void> _writeOrCopyFile(
  String outputPath, {
  Uint8List? bytes,
  String? sourceFilePath,
}) async {
  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);

  if (bytes != null) {
    await outputFile.writeAsBytes(bytes);
    return;
  }

  final sourceFile = File(sourceFilePath!);
  final input = sourceFile.openRead();
  final output = outputFile.openWrite();
  await input.pipe(output);
}
