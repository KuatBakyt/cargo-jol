# JOL Cargo Flutter

Flutter + Dart, Material 3, Provider/ChangeNotifier, Dio, flutter_secure_storage.

Запуск: `flutter pub get`, затем `flutter run -d chrome --web-port=3000 --dart-define=API_URL=http://localhost:8000/api`.
Backend запускается из корня репозитория через Docker Compose.

Структура: `core` — API и сессия; `features/auth` — вход/регистрация; `features/cargo` — каталог, публикация, карточка и предложения; `features/orders` — заказы, статусы, чат и отзывы; `features/profile` — профиль, компания и транспорт; `shared` — общие виджеты и форматирование.

API возвращает decimal как строки. Клиент не округляет суммы перед отправкой.
JWT обновляется автоматически одним запросом при нескольких одновременных 401.
Чат в этой версии текстовый, REST polling каждые 8 секунд; polling прекращается при закрытии экрана.
Секреты, тестовые логины и пароли в приложение не вшиты.
