# Tremor Band MVP

Flutter-приложение для управления ESP32-браслетом и мониторинга сигнала MPU6500.

## Что уже реализовано

- адаптивный интерфейс Android/iOS;
- четыре экрана: главная, мониторинг, управление, браслет;
- живой график тремора;
- Demo mode без физического устройства;
- BLE-поиск ESP32 по UUID сервиса;
- команды запуска, остановки, интенсивности и задержки;
- четыре паттерна для четырёх независимых вибромоторов;
- пример ESP32-прошивки с BLE и PWM.

## Запуск приложения

Требуется Flutter 3.27.4 или новее.

```bash
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

Команда `flutter create` добавит стандартные папки Android и iOS, не заменяя `lib/main.dart`.

## Разрешения Android

Добавить перед тегом `<application>` в `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
```

Минимальный Android SDK должен быть 21 или выше.

## Разрешения iOS

Добавить в `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth используется для подключения к браслету.</string>
```

## Прошивка ESP32

Файл: `firmware/esp32_tremor_band.ino`.

Для сборки нужна библиотека ArduinoJson. Пины моторов в примере: GPIO 25, 26, 27 и 14. Каждый мотор должен подключаться через отдельный MOSFET-канал с защитным диодом и отдельным питанием.

В текущем скетче MPU6500 пока заменён синтетическим сигналом. Следующий этап — подключение конкретной библиотеки MPU6500, калибровка, фильтрация и вычисление частоты тремора.

## BLE-команда

```json
{"cmd":"start","pattern":1,"intensity":60,"delay_ms":180}
```

Паттерны:

- `0` — все моторы одновременно;
- `1` — чередование ремешков;
- `2` — последовательная волна;
- `3` — импульсы.

## Следующая техническая версия

1. Подключить реальные чтения MPU6500.
2. Определить фактическое количество и расположение моторов.
3. Проверить BLE на Android и iPhone.
4. Добавить MQTT/TLS и историю измерений после проверки локального контура.

Устройство является исследовательским прототипом, а не медицинским прибором. Автоматические режимы требуют безопасных ограничений интенсивности и аппаратной кнопки отключения.
