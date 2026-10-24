# JOL Cargo
[![Backend checks](https://github.com/KuatBakyt/cargo-jol/actions/workflows/tests.yml/badge.svg)](https://github.com/KuatBakyt/cargo-jol/actions/workflows/tests.yml) [![Flutter client](https://github.com/KuatBakyt/cargo-jol/actions/workflows/flutter.yml/badge.svg)](https://github.com/KuatBakyt/cargo-jol/actions/workflows/flutter.yml)

MVP платформы грузоперевозок: грузовладелец публикует груз, перевозчики предлагают транспорт и цену, после принятия предложения создаются заказ и чат.

**Стек:** Python · Django REST Framework · PostgreSQL · JWT · Docker · Flutter.

## Возможности

- Роли грузовладельца и перевозчика, профили компаний и транспорт.
- Каталог грузов, предложения и атомарное назначение перевозчика.
- Статусы доставки, подтверждение завершения и отзывы.
- REST-чат и приватная выдача вложений через API.
- Flutter-клиент: каталог, заявки, предложения, заказы и текстовый чат.

## Что посмотреть в коде

- [Модели и ограничения](backend/marketplace/models.py).
- [Бизнес-операции и транзакции](backend/marketplace/services.py).
- [API-тесты](backend/marketplace/tests/test_api.py) и [конкурентное назначение](backend/marketplace/tests/test_concurrency.py).
- [Flutter-клиент](frontend).

## Запуск и проверки

[Полная инструкция](docs/reference.md): Docker, настройка окружения, Swagger, тесты и запуск Flutter.

Backend: `http://localhost:8000`; Swagger: `http://localhost:8000/api/docs`.
Flutter запускается с `--dart-define=API_URL=http://localhost:8000/api`.

CI запускает backend-проверки с PostgreSQL и отдельные проверки Flutter.

## Статус и ограничения

MVP для локального запуска; публичное демо пока не размещено.
SMS, push, GPS, карты, платежи и WebSocket не подключены.
Загрузка вложений реализована в API; в Flutter пока доступен текстовый чат с опросом REST.
