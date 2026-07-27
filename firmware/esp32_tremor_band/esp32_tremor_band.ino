#include <Arduino.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>

// MVP pin map. Change these values to match the PCB.
constexpr uint8_t MOTOR_PINS[4] = {25, 26, 27, 14};
constexpr uint8_t MOTOR_CHANNELS[4] = {0, 1, 2, 3};
constexpr uint32_t PWM_FREQUENCY = 20000;
constexpr uint8_t PWM_RESOLUTION = 8;

constexpr char SERVICE_UUID[] = "8f400001-91b5-4b6a-9f68-74f42a9db001";
constexpr char CONTROL_UUID[] = "8f400002-91b5-4b6a-9f68-74f42a9db001";
constexpr char TELEMETRY_UUID[] = "8f400003-91b5-4b6a-9f68-74f42a9db001";

BLECharacteristic* telemetryCharacteristic = nullptr;
bool clientConnected = false;
bool therapyOn = false;
uint8_t pattern = 1;
uint8_t intensity = 60;
uint16_t strapDelayMs = 180;
uint32_t lastPatternTick = 0;
uint32_t lastTelemetry = 0;
uint8_t patternStep = 0;

void setMotor(uint8_t index, uint8_t percent) {
  percent = constrain(percent, 0, 100);
  ledcWrite(MOTOR_CHANNELS[index], map(percent, 0, 100, 0, 255));
}

void stopAllMotors() {
  for (uint8_t i = 0; i < 4; i++) setMotor(i, 0);
}

void updatePattern() {
  if (!therapyOn) {
    stopAllMotors();
    return;
  }
  const uint32_t now = millis();
  if (now - lastPatternTick < max<uint16_t>(strapDelayMs, 40)) return;
  lastPatternTick = now;
  stopAllMotors();

  switch (pattern) {
    case 0: // All motors together
      for (uint8_t i = 0; i < 4; i++) setMotor(i, intensity);
      break;
    case 1: // Strap A, then strap B
      if (patternStep % 2 == 0) {
        setMotor(0, intensity); setMotor(1, intensity);
      } else {
        setMotor(2, intensity); setMotor(3, intensity);
      }
      patternStep++;
      break;
    case 2: // Wave around the bracelet
      setMotor(patternStep % 4, intensity);
      patternStep++;
      break;
    case 3: // Three short pulses, then a longer pause
      if (patternStep % 6 < 3) for (uint8_t i = 0; i < 4; i++) setMotor(i, intensity);
      patternStep++;
      break;
  }
}

class ServerCallbacks final : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { clientConnected = true; }
  void onDisconnect(BLEServer* server) override {
    clientConnected = false;
    therapyOn = false;
    stopAllMotors();
    server->getAdvertising()->start();
  }
};

class ControlCallbacks final : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const std::string raw = characteristic->getValue();
    JsonDocument command;
    if (deserializeJson(command, raw)) return;
    therapyOn = strcmp(command["cmd"] | "stop", "start") == 0;
    pattern = constrain(command["pattern"] | 1, 0, 3);
    intensity = constrain(command["intensity"] | 60, 0, 100);
    strapDelayMs = constrain(command["delay_ms"] | 180, 40, 2000);
    patternStep = 0;
  }
};

void sendTelemetry() {
  if (!clientConnected || millis() - lastTelemetry < 200) return;
  lastTelemetry = millis();

  // Replace these placeholders with filtered MPU6500 readings and FFT output.
  const float time = millis() / 1000.0f;
  const float gyro = sinf(time * 5.7f * TWO_PI) * (therapyOn ? 0.58f : 1.0f);
  JsonDocument packet;
  packet["gyro"] = gyro;
  packet["tremor_hz"] = 5.7;
  packet["amplitude"] = therapyOn ? 0.72 : 1.25;
  packet["battery"] = 82;

  String json;
  serializeJson(packet, json);
  telemetryCharacteristic->setValue(json.c_str());
  telemetryCharacteristic->notify();
}

void setup() {
  Serial.begin(115200);
  Wire.begin();
  for (uint8_t i = 0; i < 4; i++) {
    ledcSetup(MOTOR_CHANNELS[i], PWM_FREQUENCY, PWM_RESOLUTION);
    ledcAttachPin(MOTOR_PINS[i], MOTOR_CHANNELS[i]);
  }
  stopAllMotors();

  BLEDevice::init("Tremor Band 01");
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService* service = server->createService(SERVICE_UUID);

  BLECharacteristic* control = service->createCharacteristic(
    CONTROL_UUID, BLECharacteristic::PROPERTY_WRITE
  );
  control->setCallbacks(new ControlCallbacks());

  telemetryCharacteristic = service->createCharacteristic(
    TELEMETRY_UUID, BLECharacteristic::PROPERTY_NOTIFY
  );
  telemetryCharacteristic->addDescriptor(new BLE2902());
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
}

void loop() {
  updatePattern();
  sendTelemetry();
  delay(2);
}
