# JOL Cargo — Django API

Бэкенд MVP по ТЗ JOL Cargo v1.0: Django REST Framework, PostgreSQL, JWT.
Подходит для Next.js и Flutter. Это сервер API; интерфейс и размещение на хостинге не входят в этот репозиторий.

## Запуск на Windows

Установите Docker Desktop с Docker Compose. В PowerShell:

```powershell
git clone https://github.com/KuatBakyt/cargo-jol.git
cd cargo-jol
Copy-Item .env.example .env
docker compose up -d db
docker compose run --rm api python manage.py migrate
docker compose run --rm api python manage.py createsuperuser
docker compose up -d api
```

Swagger: http://localhost:8000/api/docs
Админка: http://localhost:8000/admin/
OpenAPI: http://localhost:8000/api/schema
Логи: `docker compose logs -f api`
Остановка: `docker compose down` (данные сохраняются в volumes).
При обновлении кода: `git pull`, `docker compose build api`, повторить migrate, `docker compose up -d api`.

В `.env` задайте собственный SECRET_KEY и пароль PostgreSQL. Файл `.env` не коммитится.
Compose запускает сервер разработки. Для публичного сервера используйте Gunicorn из Dockerfile, HTTPS reverse proxy, DEBUG=false, реальные ALLOWED_HOSTS/CORS и отдельную раздачу staticfiles. Выполните `collectstatic`, резервное копирование БД и настройте общий кеш для лимитов запросов. Не публикуйте private_uploads через nginx.

## Что реализовано

- Регистрация с ролью shipper/carrier, вход по email, JWT access/refresh с ротацией.
- Профиль, приватный аватар, компания, запрос проверки компании администратором.
- Собственный транспорт перевозчика, грузы грузовладельца, фильтры и рейтинг соответствия.
- Предложения, принятие/отклонение/отмена; атомарное назначение машины и создание заказа/чата.
- Переходы перевозки, подтверждение доставки грузовладельцем, отмена до отправления.
- REST-чат: текст, JPEG/PNG, PDF, координаты; чтение сообщений, закрытая выдача файлов.
- Избранное, уведомления внутри API, отзывы после завершения и рейтинг компании.
- Миграции, Swagger, тесты и GitHub Actions с PostgreSQL.

SMS-подтверждение, email-рассылки, push, WebSocket, карты, GPS, платежи и фронтенд не подключены. `is_phone_verified` изменяет только администратор после внешней проверки; новая смена телефона сбрасывает флаг. Поля payment_type и body_type — строковые коды, общий справочник задается клиентами.

## API

Все URL без завершающего `/`, кроме `/admin/`. Запросы JSON; загрузка файлов multipart/form-data.
После login отправляйте `Authorization: Bearer <access>`; access действует 15 минут, refresh 7 дней.
После обновления сохраняйте **новый** refresh: старый отзывается.
Денежные суммы — десятичные строки в тенге, вес — кг, объем — м³, даты — YYYY-MM-DD, телефон — международный формат +77001234567.

| URL | Действия |
| --- | --- |
| `/api/auth/register` | POST email, phone, password, role, first_name, last_name |
| `/api/auth/login` | POST email, password → access, refresh |
| `/api/auth/refresh` | POST refresh → новая пара токенов |
| `/api/auth/me` | GET, PATCH собственный профиль |
| `/api/auth/avatar` | PUT avatar, GET приватное изображение |
| `/api/companies` | GET, POST; PATCH `/id`; POST `/id/request-verification` |
| `/api/vehicles` | GET, POST; GET/PATCH/DELETE `/id` |
| `/api/cargo` | GET, POST; GET/PATCH/DELETE `/id` |
| `/api/cargo/id/offers` | GET, POST vehicle, price, message |
| `/api/offers/id` | PATCH price, message или status=cancelled |
| `/api/offers/id/accept` | POST → созданный заказ |
| `/api/offers/id/reject` | POST |
| `/api/orders` | GET; GET `/id` |
| `/api/orders/id/status` | PATCH status |
| `/api/orders/id/conversation` | GET |
| `/api/orders/id/reviews` | GET, POST rating, comment |
| `/api/conversations` | GET; GET `/id` |
| `/api/conversations/id/messages` | GET, POST |
| `/api/conversations/id/read` | POST отмечает сообщения собеседника |
| `/api/messages/id/file` | GET только участникам заказа |
| `/api/cargo/id/favorite` | POST, DELETE |
| `/api/favorites` | GET |
| `/api/notifications` | GET; POST `/id/read`, `/read-all` |

Пагинация: `?page=2`, ответ `{count,next,previous,results}`. Ошибки: 400 — валидация/конфликт состояния, 401 — авторизация, 403 — права, 404 — отсутствующий/недоступный объект, 429 — лимит.

Пример груза (роль shipper, loading_date замените на будущую дату):

```json
{
  "from_city": "Алматы", "from_address": "Склад 1",
  "to_city": "Астана", "to_address": "Склад 2",
  "loading_date": "2027-01-15", "cargo_name": "Мебель", "cargo_type": "furniture",
  "weight_kg": "1000.00", "volume_m3": "20.00", "body_type": "tent",
  "price": "150000.00", "payment_type": "bank_transfer", "status": "active"
}
```

Транспорт создается перевозчиком: brand, model, plate_number, body_type, capacity_kg, volume_m3, current_city. Статус busy назначается только при принятии предложения. У груза с ожидающими предложениями нельзя менять условия; сначала отклоните предложения или отмените груз. У назначенного груза условия зафиксированы.

Фильтры: `from`, `to`, `body_type`, `loading_date`, `loading_date_min/max`, `weight_min/max`, `price_min/max`, `status`, `mine=true`. Сортировка: `ordering=-created_at`, `price`, `-price`, `relevance`.
Для соответствия: `vehicle_id=<своя машина>`, `to=<город>`, `match_date=YYYY-MM-DD`. Баллы: маршрут 40, кузов 25, вместимость 15, дата 10, рейтинг грузовладельца до 10. Без критерия его баллы равны 0. Без конечного города маршрут оценивается только по городу машины. relevance вычисляется в Python — для большого каталога потребуется оптимизация и география маршрутов.

Статусы заказа: `carrier_selected → heading_to_pickup → loading → in_transit → delivered → completed`. Первые четыре изменения делает перевозчик, completed — грузовладелец. cancelled разрешен участникам только до in_transit. После завершения оба могут оставить по одному отзыву. Приватные данные заказа/чата доступны только участникам; опубликованные грузы доступны всем авторизованным пользователям.

Сообщения: `{"type":"text","text":"Выезжаю"}` или `{"type":"location","latitude":"43.25","longitude":"76.95"}`. Изображения/документы: multipart с type=image/document и attachment. Максимум 10 MiB. PDF проверяется по заголовку, изображения декодируются Pillow; антивирусная обработка не подключена. Скачивайте file_url с JWT через HTTP-клиент, а не открытый URL в браузере.

## Структура

`backend/config/` — настройки и маршруты.
`backend/marketplace/models.py` — данные и ограничения БД.
`serializers.py` — вход/выход и валидация.
`services.py` — атомарные операции и переходы статусов.
`views.py` — HTTP и права доступа.
`tests/` — API сценарии и конкурентное назначение PostgreSQL.
В админке транспорт/грузы/заказы доступны для просмотра; проверка компании — через actions «verify/reject» для pending.

## Проверки

```powershell
docker compose run --rm api python manage.py test --settings=config.postgres_test_settings
```

Без PostgreSQL можно запустить быстрые тесты:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
cd backend
python manage.py test --settings=config.test_settings
```

SQLite-тесты пропускают две проверки конкурентного назначения: блокировки проверяются только PostgreSQL. CI запускает весь набор на PostgreSQL 16, lint, отсутствие незаписанных миграций и валидацию OpenAPI. Docker/CI нужно проверять отдельно от локальных SQLite-тестов.

Для S3 заполните AWS_* в `.env`; bucket должен быть приватным. Без S3 файлы хранятся в private_uploads volume. Документы не публикуются через MEDIA_URL.

## Интерфейс Flutter

Клиент находится в `frontend/`. Вход, регистрация с выбором роли, каталог, публикация груза, предложения, заказы, текстовый чат, отзывы, избранное, уведомления, компания и добавление транспорта обращаются к реальному API.

Запуск в Chrome (backend должен работать):

```powershell
cd frontend
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=API_URL=http://localhost:8000/api
```

Порт 3000 уже разрешен в CORS backend. Токены сохраняются через flutter_secure_storage; при 401 клиент обновляет access и сохраняет новый refresh. При невалидном refresh открывается экран входа. Ошибки сети позволяют повторить загрузку.

Проверки: `flutter analyze`, `flutter test`, `flutter build web`. CI выполняет их автоматически. Мобильные платформенные проекты можно создать из той же папки: `flutter create --platforms=android,ios --project-name=jol_cargo .` (требуются Android SDK / macOS с Xcode для соответствующей платформы). На Android Emulator адрес API: `http://10.0.2.2:8000/api`; для физического устройства требуется доступный по сети HTTPS API. Compose по умолчанию слушает только localhost.

Это первая версия интерфейса MVP: текстовый чат работает через REST с обновлением каждые 8 секунд. Загрузка и открытие вложений, аватары, карты, редактирование профиля/транспорта и продвинутая фильтрация будут добавлены следующими этапами. Выбор перевозчика и обновление статусов уже доступны через интерфейс.
