{{flutter_js}}
{{flutter_build_config}}

// Новая сборка — новый адрес main.dart.js: браузер не возьмёт старую версию из кэша.
const buildVersion = {{flutter_service_worker_version}};
for (const b of _flutter.buildConfig.builds) {
  if (b.mainJsPath) b.mainJsPath += '?v=' + buildVersion;
}
_flutter.loader.load();
