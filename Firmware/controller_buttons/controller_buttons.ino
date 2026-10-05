// Height Ritual controller, buttons-only build -> iPhone over Bluetooth Low Energy
// For the breadboard as it is on 5 Oct 2026: five buttons, no knob, no switches.
// The light is the blue LED that is already on the ESP32 board (pin 2).
//
// Board:   ESP32 Dev Module
// Library: NimBLE-Arduino 2.x by h2zero (Library Manager)
// Serial Monitor at 115200 baud shows what happens.
//
// Same protocol as the full controller (docs/SPEC.md section 6):
//   Input characteristic (notify), 2 bytes [controlId, 1]:
//     11 Record/Stop, 13 Confirm, 23 Cancel/Back, 14 Left, 15 Right
//   Light characteristic (write), 1 byte:
//     0 off, 1 slow blink, 2 on, 3 three quick flashes then off
// Without the mode switch the app's tabs choose Make or Memory.

#include <NimBLEDevice.h>

#define DEVICE_NAME  "HeightController"
#define SERVICE_UUID "6f1d0001-8a3c-4b6e-9a51-2c7e0b1d4a01"
#define INPUT_UUID   "6f1d0002-8a3c-4b6e-9a51-2c7e0b1d4a01"
#define LED_UUID     "6f1d0003-8a3c-4b6e-9a51-2c7e0b1d4a01"

const int N = 5;
const int     PINS[N]  = {18, 25, 26, 27, 14};
const uint8_t IDS[N]   = {11, 23, 14, 13, 15};
const char*   NAMES[N] = {"Record", "Cancel", "Left", "Confirm", "Right"};
const int PIN_LED = 2;                 // on-board LED. Use 17 for an external LED with a 220 ohm resistor
const unsigned long DEBOUNCE_MS = 25;

bool stable[N], lastRead[N];
unsigned long changedAt[N];

NimBLEServer* server = nullptr;
NimBLECharacteristic* inputChar = nullptr;
volatile uint8_t ledMode = 0;
volatile unsigned long ledSince = 0;
volatile bool connected = false;

void setLed(uint8_t pattern) { ledMode = pattern; ledSince = millis(); }

void updateLed() {
  unsigned long t = millis() - ledSince;
  bool on = false;
  if (!connected) on = (millis() % 2000) < 60;                 // short blip every 2 s: waiting for the phone
  else if (ledMode == 1) on = (millis() / 500) % 2 == 0;       // slow blink
  else if (ledMode == 2) on = true;                            // steady
  else if (ledMode == 3) { if (t >= 900) ledMode = 0; else on = (t / 150) % 2 == 0; }
  digitalWrite(PIN_LED, on ? HIGH : LOW);
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s, NimBLEConnInfo& info) override {
    connected = true;
    setLed(3);
    Serial.println("[BLE] phone connected");
  }
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo& info, int reason) override {
    connected = false;
    setLed(0);
    Serial.println("[BLE] phone disconnected, advertising again");
    NimBLEDevice::startAdvertising();
  }
};

class LedCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& info) override {
    NimBLEAttValue value = c->getValue();
    if (value.size() > 0) {
      setLed(value.data()[0]);
      Serial.printf("[BLE] light pattern %d from the phone\n", value.data()[0]);
    }
  }
};

void setup() {
  Serial.begin(115200);
  pinMode(PIN_LED, OUTPUT);
  for (int i = 0; i < N; i++) {
    pinMode(PINS[i], INPUT_PULLUP);
    stable[i] = lastRead[i] = digitalRead(PINS[i]);
    changedAt[i] = 0;
  }

  NimBLEDevice::init(DEVICE_NAME);
  server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService* service = server->createService(SERVICE_UUID);
  inputChar = service->createCharacteristic(INPUT_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* ledChar =
      service->createCharacteristic(LED_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  ledChar->setCallbacks(new LedCallbacks());
  service->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->enableScanResponse(true);       // the name does not fit next to the long UUID, so it goes in the scan response
  adv->setName(DEVICE_NAME);
  adv->start();

  Serial.println();
  Serial.println("Height Ritual controller (buttons only)");
  Serial.println("[BLE] advertising as HeightController, waiting for the phone");
}

void loop() {
  for (int i = 0; i < N; i++) {
    bool reading = digitalRead(PINS[i]);
    if (reading != lastRead[i]) { lastRead[i] = reading; changedAt[i] = millis(); }
    if (reading != stable[i] && millis() - changedAt[i] > DEBOUNCE_MS) {
      stable[i] = reading;
      if (reading == LOW) {                                   // pressed
        if (connected) {
          uint8_t packet[2] = {IDS[i], 1};
          inputChar->setValue(packet, 2);
          inputChar->notify();
          Serial.printf("[SEND] %-8s id %d\n", NAMES[i], IDS[i]);
        } else {
          Serial.printf("[----] %-8s pressed, but no phone is connected\n", NAMES[i]);
        }
      }
    }
  }
  updateLed();
  delay(5);
}
