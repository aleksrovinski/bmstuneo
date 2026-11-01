# BMSTU neo

<div align="center">

![BMSTU neo](assets/icons/app_icon_512.png)

**Неофициальный клиент Личного кабинета студента МГТУ им. Н.Э. Баумана (ЛКС)**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-4CAF50)]()

</div>

## Возможности

- **Расписание** группы и преподавателей: числитель и знаменатель, свайпы по дням, свои занятия,
  гостевой режим без входа.
- **Успеваемость (БРС)**: баллы по модулям и контрольным точкам, сроки ДЗ и РК по неделям,
  ручные отметки «сдано» / «выдано», результаты сессий.
- **Домашние задания**: свои заметки по предметам — быстрые (к следующей паре, она находится по
  расписанию с учётом числителя и знаменателя) и долгие (к выбранному сроку). Видны на главной и
  в карточках пар; хранятся только на устройстве.
- **Физкультура (ФКиС)**: баллы, посещения, ближайшее занятие.
- **Студенческий** и QR-пропуск.
- **Почта** `@student.bmstu.ru`: папки, непрочитанные на главной, чтение, ответ, пересылка
  с вложениями, удаление в корзину. Работает через XIMSS — HTTP-протокол веб-клиента CommuniGate
  Pro (Pronto) на `student.bmstu.ru`; вложения открываются через системное меню «Поделиться».
- **Уведомления** о новых баллах, выданных заданиях и сроках на этой неделе, а также о новых
  письмах (включаются отдельно). Приложение проверяет ЛКС и почту в фоне со своей сессией;
  сервер только будит его тихим push.
- **Виджет** на рабочий стол (Android и iOS) и **Live Update** с текущей парой (Android).
- **Офлайн-режим**: расписание и оценки кэшируются.
- **Обновления на Android** прямо из приложения: APK с сайта, проверка контрольной суммы,
  установка поверх с сохранением данных.
- **Material You**, светлая и чёрная тёмная тема, крупный шрифт.

Пароль хранится только на устройстве (Keychain / Keystore) и отправляется только на SSO МГТУ,
а пароль от почты — только на почтовый сервер `student.bmstu.ru`.
Подробно — в [политике конфиденциальности](PRIVACY_POLICY.md).

## Структура репозитория

```text
app/
├── lib/               main.dart — приложение, main_demo.dart — демо-версия
│   ├── demo/            примеры данных и подставной ЛКС для демо-версии
│   ├── models/          модели данных (расписание, профиль, БРС, ФКиС)
│   ├── providers/       состояние (Provider)
│   ├── screens/         экраны, включая настройки
│   ├── services/        клиент ЛКС, кэш, фоновая синхронизация, push, виджет
│   └── widgets/         компоненты интерфейса
├── android/             нативная часть: виджет, Live Update, FCM
├── ios/                 нативная часть: WidgetKit, APNs
├── macos/
├── assets/              иконки и шрифт Onest
├── test/                тесты (flutter test)
├── tool/                утилиты: обновление каталога групп, тестовые push
├── server/              сервер тихих push-уведомлений (Dart) — см. server/README.md
│   └── deploy/          развёртывание сервера и сайта на VPS, публикация APK
└── .github/workflows/   CI: анализ и тесты
```

Лендинг приложения живёт в отдельном репозитории (папка `website/` рядом с этой).

## Запуск

Нужен [Flutter](https://docs.flutter.dev/get-started/install) 3.x (stable), для iOS — Xcode,
для Android — Android SDK.

```bash
git clone https://github.com/aleksrovinski/bmstuneo.git
cd bmstuneo
flutter pub get
flutter run
```

Проверки (их же запускает CI):

```bash
flutter analyze
flutter test
```

### Демо-версия

```bash
flutter run -t lib/main_demo.dart
```

Отдельная точка входа с вымышленным студентом (РК6-31Б) и примерами всех данных: расписание с
числителем и знаменателем, баллы за модули, сроки ДЗ и РК, лабораторные и семинары, физкультура,
результаты сессий, поиск преподавателей, домашние задания и студенческая почта с письмами от
преподавателей, деканата и старосты (папки, вложения, флажки, ответы). Пары на сегодня строятся от текущего времени, поэтому
днём на главном экране всегда идёт пара. Подходит для скриншотов, показа функций и проверки
интерфейса без учётной записи МГТУ.

ЛКС, фоновая синхронизация и push в демо не используются. Настройки, кэш и данные входа хранятся
отдельно от основной версии, но установка та же: демо заменяет приложение на устройстве, пока его
не переустановить обычной сборкой. Данные — в `lib/demo/demo_data.dart`, письма — в
`lib/demo/demo_mail_service.dart`.

### Параметры сборки

| `--dart-define` | Зачем |
|---|---|
| `PUSH_SERVER_URL=https://…` | адрес сервера push-уведомлений. Без него приложение не регистрируется на сервере, а фоновая проверка по расписанию ОС работает как обычно |

Отладочная сборка Android разрешает обычный HTTP только к `localhost`, поэтому для локального
сервера на телефоне по USB: `adb reverse tcp:8080 tcp:8080` и
`flutter run --dart-define=PUSH_SERVER_URL=http://localhost:8080`.

### Push-уведомления

- **Android**: Firebase Cloud Messaging. Конфигурация проекта — `android/app/google-services.json`
  (не секрет).
- **iOS**: APNs напрямую, capability Push Notifications и Background Modes в Xcode.
- **Сервер**: [`server/`](server/README.md). Ключ APNs (`.p8`) и сервисный аккаунт Firebase нужны
  только серверу и в репозиторий не попадают.
- Тестовая отправка без сервера: `tool/send_test_push.sh` (iOS) и `tool/send_test_fcm.sh` (Android).

## Релизные сборки

Версия и номер сборки берутся из `version:` в `pubspec.yaml` (например, `1.5.1+15`). Перед каждой
выгрузкой увеличьте число после `+`.

### Android

Релиз подписывается ключом загрузки, который хранится только локально.

1. Один раз создайте keystore (без него и пароля обновление не выпустить):
   ```bash
   keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Скопируйте `android/key.properties.example` в `android/key.properties` и впишите пароли.

```bash
flutter build apk --release --dart-define=PUSH_SERVER_URL=https://bmstuneo.xyz
flutter build appbundle --release --dart-define=PUSH_SERVER_URL=https://bmstuneo.xyz
```

`key.properties` и `*.jks` исключены из git. На CI вместо файла можно задать переменные окружения
`CM_KEYSTORE_PATH`, `CM_KEYSTORE_PASSWORD`, `CM_KEY_ALIAS`, `CM_KEY_PASSWORD`. Без ключа APK
подписывается debug-ключом, а сборка AAB завершается ошибкой.

Приложение обновляется с сайта: раз в 12 часов оно читает `https://bmstuneo.xyz/version.json` и
предлагает новую версию, если `versionCode` больше установленного. Android ставит обновление
поверх только при той же подписи, поэтому все выпуски подписывайте одним ключом — иначе
придётся удалить приложение, а вместе с ним и домашние задания, которые хранятся только на
устройстве. Публикация APK на сайте и обновление `version.json`:

```bash
server/deploy/publish-apk.sh root@HOST build/app/outputs/flutter-apk/app-release.apk "Что нового"
```

Сервер push и сайт разворачиваются на VPS скриптом `server/deploy/deploy.sh` (ключ APNs и сервисный
аккаунт Firebase передаются аргументами и в репозиторий не попадают).

### iOS

```bash
flutter build ipa --release --dart-define=PUSH_SERVER_URL=https://bmstuneo.xyz
```

Готовый архив выгружается в TestFlight через Xcode Organizer или Transporter. Метаданные и
прохождение модерации App Store — в [APP_STORE_SUBMISSION_GUIDE.md](APP_STORE_SUBMISSION_GUIDE.md).

## Участие в разработке

1. Сделайте fork и ветку: `git checkout -b feature/имя`.
2. Перед коммитом: `flutter analyze` и `flutter test`.
3. Откройте pull request.

## Контакты

- Email: [nesegsasa@gmail.com](mailto:nesegsasa@gmail.com)
- Telegram: [@aleksrovi](https://t.me/aleksrovi)

## Лицензия

[MIT](LICENSE)
