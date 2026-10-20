"""Тестовые файлы для e2e: список игроков в Word (.docx)."""

import sys
import zipfile

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sostav.docx"
lines = ["Состав U12", "1. Сидоров Иван Петрович, 2014, защитник, №4", "2. Кузнецова Анна 2015 пз",
         "3. Белов Олег 2014 нападающий №9"]
body = "".join(f"<w:p><w:r><w:t>{t}</w:t></w:r></w:p>" for t in lines)
ns = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
xml = f'<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="{ns}"><w:body>{body}</w:body></w:document>'
ct = ('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
with zipfile.ZipFile(out, "w") as z:
    z.writestr("[Content_Types].xml", ct)
    z.writestr("word/document.xml", xml)
print(out)
