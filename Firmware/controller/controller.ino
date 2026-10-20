// Memory Meter controller v4 -> iPhone app over Bluetooth Low Energy
// The box (19 Oct 2026), seen from above:
//
//   [ Back ]                 ( Knob )
//
//   < Left      ( Confirm )     Right >
//
// Five controls: Back, a rotary encoder knob, Left, the round Confirm, Right.
// Confirm also starts and stops filming. Powered by a USB power bank.
//
// Board:     classic ESP32 DevKit (ESP32-WROOM-32) or ESP32-S3-DevKitC (pins are chosen automatically)
// Library:   NimBLE-Arduino 2.x by h2zero (Library Manager). The knob needs no library.
// Serial Monitor at 115200 baud shows every press and turn.
//
// The controller only reports what was used. The app decides what it means on each screen
// (docs/SPEC.md section 6).
//
// Input characteristic (notify), 2 bytes [controlId, value]:
//   1  knob turn      value = signed detents since the last packet (+ clockwise)
//   13 Confirm        1
//   14 Left           1
//   15 Right          1
//   23 Back           1
// No light: the box has no LED, so there is no light characteristic (the app skips it).

// Encoder steps per click you feel. Most EC11 / KY-040 knobs: 4.
// If one click moves the height by 0.2 cm, set 2. If it takes two clicks to move once, set 4 -> 2.
#define COUNTS_PER_DETENT 4
// Turn the knob clockwise: the height should go up. If it goes down, set 1.
#define REVERSE_KNOB 0
// Print presses, turns and sent packets to the Serial Monitor (115200 baud): 1 = on, 0 = off
#define SERIAL_DEBUG 1

#include <NimBLEDevice.h>

#define DEVICE_NAME  "MemoryMeter"
#define SERVICE_UUID "6f1d0001-8a3c-4b6e-9a51-2c7e0b1d4a01"
#define INPUT_UUID   "6f1d0002-8a3c-4b6e-9a51-2c7e0b1d4a01"

// ---- Pins. Every button: one leg to the pin, the other leg to GND (internal pull-up). ----
#if CONFIG_IDF_TARGET_ESP32S3
const int PIN_BACK    = 6;
const int PIN_LEFT    = 16;
const int PIN_CONFIRM = 17;
const int PIN_RIGHT   = 18;
const int PIN_ENC_A   = 4;    // encoder CLK
const int PIN_ENC_B   = 5;    // encoder DT
#else
// The box as soldered (20 Oct): Back 25, Left 33, Right 14, Confirm 27, knob CLK 32 / DT 26.
// Avoid 34 to 39: input only, no internal pull-ups.
const int PIN_BACK    = 25;
const int PIN_LEFT    = 33;
const int PIN_CONFIRM = 27;
const int PIN_RIGHT   = 14;
const int PIN_ENC_A   = 32;   // encoder CLK
const int PIN_ENC_B   = 26;   // encoder DT
#endif

enum : uint8_t { ID_KNOB = 1, ID_CONFIRM = 13, ID_LEFT = 14, ID_RIGHT = 15, ID_BACK = 23 };

const unsigned long DEBOUNCE_MS = 25;
const unsigned long KNOB_SEND_MS = 20;   // turns are summed and sent at most every 20 ms

// ---- Buttons, debounced ----
struct Button {
  int pin;
  uint8_t id;
  const char* name;
  bool stable;          // debounced level, HIGH = released
  bool lastRead;
  unsigned long changedAt;
};

Button buttons[] = {
  {PIN_BACK,    ID_BACK,    "Back"},
  {PIN_LEFT,    ID_LEFT,    "Left"},
  {PIN_CONFIRM, ID_CONFIRM, "Confirm"},
  {PIN_RIGHT,   ID_RIGHT,   "Right"},
};

// Returns true once per press (the debounced level went to LOW).
bool pressed(Button& b) {
  bool reading = digitalRead(b.pin);
  if (reading != b.lastRead) {
    b.lastRead = reading;
    b.changedAt = millis();
  }
  if (reading != b.stable && millis() - b.changedAt > DEBOUNCE_MS) {
    b.stable = reading;
    return reading == LOW;
  }
  return false;
}

// ---- Knob: quadrature decoding in an interrupt, no library ----
// Each valid change of the two pins moves the count by one; invalid ones (bounce) are ignored.
volatile long encCount = 0;
volatile uint8_t encState = 0;
const int8_t ENC_TABLE[16] = {0, -1, 1, 0, 1, 0, 0, -1, -1, 0, 0, 1, 0, 1, -1, 0};

void IRAM_ATTR onEncoder() {
  encState = ((encState << 2) | (digitalRead(PIN_ENC_A) << 1) | digitalRead(PIN_ENC_B)) & 0x0F;
  encCount += ENC_TABLE[encState];
}

long lastDetent = 0;
unsigned long lastKnobSend = 0;

long detents() {
  noInterrupts();
  long count = encCount;
  interrupts();
  long d = count / COUNTS_PER_DETENT;
  return REVERSE_KNOB ? -d : d;
}

// ---- Bluetooth ----
NimBLEServer* server = nullptr;
NimBLECharacteristic* inputChar = nullptr;

bool isConnected() { return server && server->getConnectedCount() > 0; }

void send(uint8_t id, int8_t value, const char* name) {
#if SERIAL_DEBUG
  Serial.printf("[%s] %-8s [%d, %d]\n", isConnected() ? "SEND" : "----", name, id, value);
#endif
  if (!isConnected() || !inputChar) return;
  uint8_t packet[2] = {id, (uint8_t)value};
  inputChar->setValue(packet, 2);
  inputChar->notify();
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s, NimBLEConnInfo& info) override {
#if SERIAL_DEBUG
    Serial.println("[BLE] phone connected");
#endif
  }
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo& info, int reason) override {
#if SERIAL_DEBUG
    Serial.println("[BLE] phone disconnected, advertising again");
#endif
    NimBLEDevice::startAdvertising();
  }
};

void setup() {
#if SERIAL_DEBUG
  Serial.begin(115200);
  Serial.println();
  Serial.printf("Memory Meter controller v4. Back %d, Left %d, Confirm %d, Right %d, knob %d/%d\n",
                PIN_BACK, PIN_LEFT, PIN_CONFIRM, PIN_RIGHT, PIN_ENC_A, PIN_ENC_B);
#endif
  for (Button& b : buttons) {
    pinMode(b.pin, INPUT_PULLUP);
    b.stable = b.lastRead = digitalRead(b.pin);
    b.changedAt = 0;
  }

  pinMode(PIN_ENC_A, INPUT_PULLUP);
  pinMode(PIN_ENC_B, INPUT_PULLUP);
  encState = (digitalRead(PIN_ENC_A) << 1) | digitalRead(PIN_ENC_B);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_A), onEncoder, CHANGE);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_B), onEncoder, CHANGE);

  NimBLEDevice::init(DEVICE_NAME);
  server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService* service = server->createService(SERVICE_UUID);
  inputChar = service->createCharacteristic(INPUT_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  service->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->enableScanResponse(true);   // the name does not fit next to the long UUID, so it goes in the scan response
  adv->setName(DEVICE_NAME);
  adv->start();
#if SERIAL_DEBUG
  Serial.println("[BLE] advertising as " DEVICE_NAME ", waiting for the phone");
#endif
}

void loop() {
  for (Button& b : buttons) {
    if (pressed(b)) send(b.id, 1, b.name);
  }

  // Knob: send the clicks turned since the last packet, as one signed number.
  long now = detents();
  if (now != lastDetent && millis() - lastKnobSend >= KNOB_SEND_MS) {
    long delta = constrain(now - lastDetent, -127, 127);
    send(ID_KNOB, (int8_t)delta, delta > 0 ? "Knob +" : "Knob -");
    lastDetent += delta;
    lastKnobSend = millis();
  }

  delay(2);
}
