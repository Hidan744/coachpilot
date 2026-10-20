import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_name.dart';

Future<void> saveFile(Uint8List bytes, String fileName, String mime) async {
  final name = safeFileName(fileName);
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  // Ссылку освобождаем не сразу: часть браузеров начинает загрузку асинхронно.
  Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
