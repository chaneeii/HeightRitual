// Memory Meter controller -> iPhone app over Bluetooth Low Energy
//
//   [ Back ]                 ( Knob )
//   < Left      ( Confirm )     Right >
//
// Board:     ESP32 Dev Module
// Libraries: NimBLE-Arduino 2.x (h2zero), ESP32Encoder (madhephaestus) - both from Library Manager
// Serial Monitor: 115200 baud
//
// Packets [id, value]: knob [1, +n] / [1, -n], Confirm [13, 1], Left [14, 1], Right [15, 1],
// Back [23, 1]. The app decides what each control does on each screen.

#include <NimBLEDevice.h>
#include <ESP32Encoder.h>

#define DEVICE_NAME  "MemoryMeter"
#define SERVICE_UUID "6f1d0001-8a3c-4b6e-9a51-2c7e0b1d4a01"
#define INPUT_UUID   "6f1d0002-8a3c-4b6e-9a51-2c7e0b1d4a01"

// Pins as soldered on the box.
const int PIN_BACK    = 25;
const int PIN_LEFT    = 33;
const int PIN_RIGHT   = 14;
const int PIN_CONFIRM = 27;
const int PIN_CLK     = 32;   // knob CLK
const int PIN_DT      = 26;   // knob DT

// Encoder counts per click. 1 for the box's knob. One click moves two steps: 2.
#define COUNTS_PER_CLICK 1
// The knob turns the wrong way round: set to 1.
#define REVERSE_KNOB 0

// ---- Bluetooth ----
NimBLEServer* server = nullptr;
NimBLECharacteristic* inputChar = nullptr;

bool connected() { return server && server->getConnectedCount() > 0; }

void send(uint8_t id, int8_t value, const char* name) {
  Serial.printf("[%s] %s [%d, %d]\n", connected() ? "SEND" : "----", name, id, value);
  if (!connected()) return;
  uint8_t packet[2] = {id, (uint8_t)value};
  inputChar->setValue(packet, 2);
  inputChar->notify();
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override { Serial.println("[BLE] phone connected"); }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    Serial.println("[BLE] phone disconnected");
    NimBLEDevice::startAdvertising();
  }
};

// ---- Buttons: one packet per press, 25 ms debounce ----
struct Button {
  int pin;
  uint8_t id;
  const char* name;
  bool down;
  unsigned long changedAt;
};

Button buttons[] = {
  {PIN_BACK,    23, "Back"},
  {PIN_LEFT,    14, "Left"},
  {PIN_RIGHT,   15, "Right"},
  {PIN_CONFIRM, 13, "Confirm"},
};

void readButtons() {
  for (Button& b : buttons) {
    bool down = digitalRead(b.pin) == LOW;
    if (down != b.down && millis() - b.changedAt > 25) {
      b.down = down;
      b.changedAt = millis();
      if (down) send(b.id, 1, b.name);
    }
  }
}

// ---- Knob: the ESP32's hardware pulse counter (PCNT) through ESP32Encoder ----
// The hardware counts every edge with its own glitch filter, so nothing is missed or read late.
ESP32Encoder encoder;
long sentClicks = 0;

void readKnob() {
  long clicks = encoder.getCount() / COUNTS_PER_CLICK;
  if (REVERSE_KNOB) clicks = -clicks;
  if (clicks == sentClicks) return;
  long delta = constrain(clicks - sentClicks, -127, 127);
  sentClicks += delta;
  send(1, (int8_t)delta, delta > 0 ? "Knob +" : "Knob -");
}

// ---- Setup and loop ----
void setup() {
  Serial.begin(115200);
  Serial.println("\nMemory Meter controller");

  for (Button& b : buttons) {
    pinMode(b.pin, INPUT_PULLUP);
    b.down = digitalRead(b.pin) == LOW;
    b.changedAt = 0;
  }

  ESP32Encoder::useInternalWeakPullResistors = puType::up;
  encoder.attachHalfQuad(PIN_DT, PIN_CLK);
  encoder.setFilter(1023);   // the strongest hardware debounce, recommended for KY-040 knobs
  encoder.clearCount();

  NimBLEDevice::init(DEVICE_NAME);
  server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  NimBLEService* service = server->createService(SERVICE_UUID);
  inputChar = service->createCharacteristic(INPUT_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  service->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->enableScanResponse(true);
  adv->setName(DEVICE_NAME);
  adv->start();
  Serial.println("[BLE] advertising as " DEVICE_NAME);
}

void loop() {
  readButtons();
  readKnob();
  delay(10);
}
