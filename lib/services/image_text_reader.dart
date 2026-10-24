import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Bundled Chinese OCR; never uploads images or removes the selected original.
class ImageTextReader {
  static Future<String?> chooseAndRead({
    void Function(String path)? onImageSelected,
  }) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    if (await File(picked.path).length() > 30 * 1024 * 1024) {
      throw const FormatException('图片过大，请选择 30 MB 以内的截图');
    }
    final directory = await Directory.systemTemp.createTemp('homework_ocr_');
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(
        await picked.readAsBytes(),
      );
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      final scale = math.min(1800 / math.min(w, h), 4096 / math.max(w, h));
      var path = picked.path;
      if (scale < .95 || scale > 1.05) {
        codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (w * scale).round()),
          targetHeight: math.max(1, (h * scale).round()),
        );
        image = (await codec.getNextFrame()).image;
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final file = File('${directory.path}/prepared.png');
          await file.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
          path = file.path;
        }
      }
      final text = (await recognizer.processImage(
        InputImage.fromFilePath(path),
      )).text.trim();
      onImageSelected?.call(picked.path);
      return text;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
      await recognizer.close();
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
    }
  }
}
