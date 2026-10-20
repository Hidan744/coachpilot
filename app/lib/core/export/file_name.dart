const _tr = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y',
  'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
  'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
};

/// Имя файла латиницей без пробелов: кириллица в имени скачиваемого файла теряется в части браузеров.
String safeFileName(String name) {
  final b = StringBuffer();
  for (final ch in name.split('')) {
    final low = ch.toLowerCase();
    final t = _tr[low];
    if (t != null) {
      b.write(ch == low || t.isEmpty ? t : t[0].toUpperCase() + t.substring(1));
    } else if (RegExp(r'[A-Za-z0-9._-]').hasMatch(ch)) {
      b.write(ch);
    } else {
      b.write('_');
    }
  }
  return b.toString().replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'_(?=\.)'), '');
}
