# Руководство по публикации BMSTU neo в Apple App Store и настройке Codemagic

Данное руководство содержит все необходимые метаданные, инструкции для прохождения модерации Apple App Store Review и настройки сборки в Codemagic.

---

## 1. Настройка Codemagic CI/CD

### Шаг 1. Создание App Store Connect API Key
1. Перейдите в [App Store Connect](https://appstoreconnect.apple.com/) -> **Users and Access** -> вкладка **Integrations** -> **App Store Connect API**.
2. Нажмите **+** (Generate API Key).
3. Укажите имя: `Codemagic CI`.
4. Роль: **App Manager** или **Admin**.
5. Запишите:
   * **Issuer ID** (UUID вверху страницы).
   * **Key ID** (10-значный идентификатор ключа).
   * Скачайте файл ключа: `AuthKey_XXXXXXXXXX.p8` (скачать можно только один раз!).

### Шаг 2. Добавление проекта в Codemagic
1. Войдите в [Codemagic.io](https://codemagic.io/).
2. Добавьте репозиторий проекта из GitHub / GitLab / Bitbucket.
3. В настройках команды (*Teams -> Integrations*) подключите **Apple Developer Portal** / **App Store Connect API**:
   - Вставьте Issuer ID, Key ID и содержимое файла `.p8`.
4. В настройках приложения в Codemagic создайте Environment Variable Group: `app_store_credentials`:
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_KEY_IDENTIFIER`
   - `APP_STORE_CONNECT_PRIVATE_KEY`
5. Нажмите **Start new build** -> выберите workflow `BMSTU neo iOS (TestFlight & App Store)`.
   Codemagic соберет проект на macOS, автоматически подпишет сертификатом Apple Distribution и загрузит сборку в **TestFlight**.

---

## 2. Создание приложения в App Store Connect

1. Перейдите в **App Store Connect** -> **My Apps** -> **+** -> **New App**.
2. Заполните:
   * **Platforms**: iOS
   * **Name**: `BMSTU neo - Расписание МГТУ`
   * **Primary Language**: Russian (Русский)
   * **Bundle ID**: выберите `ru.bmstu.neo`
   * **SKU**: `bmstu_neo_ios_01`
   * **User Access**: Full Access

---

## 3. Метаданные карточки App Store

### Название (до 30 символов):
```text
BMSTU neo - Расписание МГТУ
```

### Подзаголовок (до 30 символов):
```text
Неофициальный клиент ЛКС
```

### Категории:
* Основная: **Образование (Education)**
* Вторичная: **Утилиты (Utilities)**

### Возрастной рейтинг:
* **4+** (контент не содержит неприемлемых материалов).

### Ключевые слова (до 100 символов, через запятую без пробелов):
```text
мгту,бауманка,расписание,лкс,баумана,bmstu,студент,пары,сессия,учеба
```

### Описание (Description):
```text
BMSTU neo — современный, быстрый и удобный мобильный клиент Личного кабинета студента (ЛКС) МГТУ им. Н.Э. Баумана нового поколения.

ВНИМАНИЕ: Приложение является независимой студенческой разработкой и не является официальным сервисом МГТУ им. Н.Э. Баумана.

КЛЮЧЕВЫЕ ВОЗМОЖНОСТИ:
• ИНТЕРАКТИВНОЕ РАСПИСАНИЕ: Расписание занятий на сегодня, завтра и всю неделю. Поддержка числителя и знаменателя, фильтрация по аудиториям, корпусам и преподавателям.
• ЖИВОЙ СТАТУС ПАРЫ: Таймер до конца текущей пары или начала следующей, расписание звонков в реальном времени.
• ОФЛАЙН-РЕЖИМ: Расписание и данные сохраняются на устройстве и доступны даже в подземных переходах и аудиториях без связи.
• ВИДЖЕТ НА РАБОЧИЙ СТОЛ (WidgetKit): Удобные виджеты для главного экрана iPhone с расписанием ближайших пар.
• УСПЕВАЕМОСТЬ И БРС: Модули, текущие баллы, экзамены и зачеты с расчетом рейтинга.
• БАЛЛЫ ПО ФИЗКУЛЬТУРЕ: Учет посещений, нормативов и отработок.
• ЭЛЕКТРОННЫЙ ПРОПУСК: QR-код для турникетов кампуса с автоматическим увеличением яркости экрана.
• ГОСТЕВОЙ РЕЖИМ: Возможность просмотра расписания любой группы МГТУ без ввода учетных данных.
```

### URL Политики конфиденциальности (Privacy Policy URL):
```text
https://ваша-ссылка-на-github-pages-или-notion/PRIVACY_POLICY
```

### URL Поддержки (Support URL):
```text
https://t.me/bmstu_neo_support
```

---

## 4. Заметки для модераторов Apple (App Review Information)

> [!IMPORTANT]
> Это поле обязательно для заполнения в App Store Connect. Модераторы Apple не имеют студенческого билета МГТУ, поэтому используйте следующий текст на английском языке:

```text
Dear Apple App Review Team,

This application is an educational client designed for students of Bauman Moscow State Technical University (BMSTU).

HOW TO TEST THE APP (GUEST / DEMO MODE):
Since user accounts are issued directly by the University administration, you can evaluate ALL app functionality and UI without entering credentials:
1. Launch the app to see the login screen.
2. Tap the secondary button "Войти как гость" (Guest Mode / Demo).
3. Select any academic group from the list (e.g. "ИУ7-43Б" or "РК6-41Б").
4. You will get immediate full access to the interactive class schedule, upcoming lessons countdown, calendar views, and curriculum details.

DATA PRIVACY & ACCOUNT MANAGEMENT:
- User authentication is performed directly via the University Keycloak Single Sign-On (sso.bmstu.ru) using secure HTTPS connections.
- User accounts are institutional and managed exclusively by University administration.
- The app stores credentials locally inside the Apple Keychain (Security.framework) with hardware encryption.
- Users can log out and permanently wipe all cached data and Keychain credentials anytime using the "Выйти из аккаунта" (Sign Out) button on the Profile screen.

THIRD-PARTY BRANDING COMPLIANCE (Guideline 5.2.2):
- The app clearly states in its description, subtitle, and UI that it is an unofficial student-developed tool.
- The app icon uses an original custom vector monogram and does not use the official University seal or crest.

Thank you!
```

---

## 5. Требования к скриншотам App Store

Для подачи требуется загрузить скриншоты минимум для двух диагоналей экранов:
1. **6.7" iPhone** (iPhone 15 Pro Max / 16 Pro Max):
   * Разрешение: **1290 × 2796 пикселей** (или 1320 × 2868).
2. **6.5" iPhone** (iPhone 11 Pro Max / iPhone XS Max):
   * Разрешение: **1242 × 2688 пикселей**.

Рекомендуемый набор из 4-5 слайдов:
1. Главный экран: текущая пара, обратный отсчет времени и быстрые действия.
2. Расписание: сетка занятий на неделю с числителем/знаменателем.
3. Успеваемость (БРС): баллы за модули и экзамены.
4. Электронный пропуск: QR-код для турникетов.
5. Виджеты: демонстрация виджета на экране iPhone.
