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
// Light characteristic (write), 1 or 2 bytes [recording, mode]; only the first byte is used:
//   0 off, 1 slow blink, 2 on, 3 three quick flashes then off
//   The box has no light of its own, so this drives the LED on the board (not visible when closed).

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
#define LED_UUID     "6f1d0003-8a3c-4b6e-9a51-2c7e0b1d4a01"

// ---- Pins. Every button: one leg to the pin, the other leg to GND (internal pull-up). ----
#if CONFIG_IDF_TARGET_ESP32S3
const int PIN_BACK    = 6;
const int PIN_LEFT    = 16;
const int PIN_CONFIRM = 17;
const int PIN_RIGHT   = 18;
const int PIN_ENC_A   = 4;    // encoder CLK
const int PIN_ENC_B   = 5;    // encoder DT
const int PIN_LED     = 48;   // RGB LED on most S3 DevKitC boards; any free pin works
#else
// Same pins as the breadboard (5 Oct): Back 25, Left 26, Confirm 27, Right 14.
// The old Record button on 18 is gone; Confirm films now.
const int PIN_BACK    = 25;
const int PIN_LEFT    = 26;
const int PIN_CONFIRM = 27;
const int PIN_RIGHT   = 14;
const int PIN_ENC_A   = 32;   // encoder CLK. 32 and 33 have internal pull-ups; 34 to 39 do not
const int PIN_ENC_B   = 33;   // encoder DT
const int PIN_LED     = 2;    // blue LED on the board
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
volatile uint8_t ledMode = 0;
volatile unsigned long ledSince = 0;

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

void setLed(uint8_t pattern) { ledMode = pattern; ledSince = millis(); }

void updateLed() {
  unsigned long t = millis() - ledSince;
  bool on = false;
  if (!isConnected()) on = (millis() % 2000) < 60;            // short blip every 2 s: waiting for the phone
  else if (ledMode == 1) on = (millis() / 500) % 2 == 0;      // slow blink
  else if (ledMode == 2) on = true;                           // steady
  else if (ledMode == 3) { if (t >= 900) ledMode = 0; else on = (t / 150) % 2 == 0; }
  digitalWrite(PIN_LED, on ? HIGH : LOW);
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s, NimBLEConnInfo& info) override {
    setLed(3);
#if SERIAL_DEBUG
    Serial.println("[BLE] phone connected");
#endif
  }
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo& info, int reason) override {
    setLed(0);
#if SERIAL_DEBUG
    Serial.println("[BLE] phone disconnected, advertising again");
#endif
    NimBLEDevice::startAdvertising();
  }
};

class LedCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& info) override {
    NimBLEAttValue value = c->getValue();
    if (value.size() > 0) setLed(value.data()[0]);
  }
};

void setup() {
#if SERIAL_DEBUG
  Serial.begin(115200);
  Serial.println();
  Serial.printf("Memory Meter controller v4. Back %d, Left %d, Confirm %d, Right %d, knob %d/%d\n",
                PIN_BACK, PIN_LEFT, PIN_CONFIRM, PIN_RIGHT, PIN_ENC_A, PIN_ENC_B);
#endif
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, LOW);

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
  NimBLECharacteristic* ledChar =
      service->createCharacteristic(LED_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  ledChar->setCallbacks(new LedCallbacks());
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

  updateLed();
  delay(2);
}
