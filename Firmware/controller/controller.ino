// Height Ritual controller v3 -> iPhone app over Bluetooth Low Energy
// Layout from the team sketch (5 Oct 2026):
//   top:    recording light, mode switch (make / memory), auto play toggle
//   middle: Record/Stop button, knob
//   bottom: Cancel/Back, Left, Confirm, Right
//
// Board:     classic ESP32 DevKit or ESP32-S3-DevKitC (pins are chosen automatically)
// Libraries: NimBLE-Arduino 2.x (h2zero). ESP32Encoder only if USE_POT is 0.
//
// The controller only reports what was used. The app decides what it means on each screen.
//
// Input characteristic (notify), 2 bytes [controlId, value]:
//   1  knob turn      value = signed steps (+ clockwise)
//   11 Record/Stop    1
//   13 Confirm        1
//   23 Cancel/Back    1
//   14 Left           1
//   15 Right          1
//   31 mode switch    0 = Memory, 1 = Make (sent on change and when the app subscribes)
//   32 auto play      1 = toggle
// Light characteristic (write), 1 or 2 bytes [recording, mode]:
//   recording: 0 off, 1 slow blink, 2 on, 3 three quick flashes then off
//   mode (optional): 0 = memory light on, 1 = make light on

// Knob type: 1 = potentiometer (3 pins, about 300 degrees), 0 = rotary encoder EC11
#define USE_POT 1
// Auto play control: 1 = latching push switch (every change is a toggle), 0 = momentary button
#define AUTOPLAY_LATCHING 1
// Two extra LEDs that show the mode: 1 = fitted, 0 = not fitted
#define MODE_LEDS 0
// Print pin changes and sent packets to the Serial Monitor (115200 baud): 1 = on, 0 = off
#define SERIAL_DEBUG 1

#include <NimBLEDevice.h>
#if !USE_POT
#include <ESP32Encoder.h>
#endif

#define DEVICE_NAME  "HeightController"
#define SERVICE_UUID "6f1d0001-8a3c-4b6e-9a51-2c7e0b1d4a01"
#define INPUT_UUID   "6f1d0002-8a3c-4b6e-9a51-2c7e0b1d4a01"
#define LED_UUID     "6f1d0003-8a3c-4b6e-9a51-2c7e0b1d4a01"

// ---- Pins (all inputs use internal pull-ups; the other leg goes to GND) ----
#if CONFIG_IDF_TARGET_ESP32S3
const int PIN_POT      = 1;   // potentiometer middle pin (ADC1)
const int PIN_ENC_A    = 4;
const int PIN_ENC_B    = 5;
const int PIN_RECORD   = 7;
const int PIN_AUTOPLAY = 15;
const int PIN_CANCEL   = 6;
const int PIN_LEFT     = 16;
const int PIN_CONFIRM  = 17;
const int PIN_RIGHT    = 18;
const int PIN_MODE     = 8;   // slide switch: middle to GND, Make side to this pin
const int PIN_LED      = 9;   // recording LED through a resistor, short leg to GND
const int PIN_LED_MAKE = 10;
const int PIN_LED_MEMORY = 11;
#else
// Classic ESP32 DevKit (ESP32-WROOM-32). Same wiring as the breadboard guide:
// the old Playback button (19) is now auto play, the old Push button (25) is now Cancel.
const int PIN_POT      = 34;  // potentiometer middle pin (ADC1, input only). Outer pins: 3V3 and GND
const int PIN_ENC_A    = 32;
const int PIN_ENC_B    = 33;
const int PIN_RECORD   = 18;
const int PIN_AUTOPLAY = 19;
const int PIN_CANCEL   = 25;
const int PIN_LEFT     = 26;
const int PIN_CONFIRM  = 27;
const int PIN_RIGHT    = 14;
const int PIN_MODE     = 16;  // slide switch: middle to GND, Make side to this pin
const int PIN_LED      = 17;  // recording LED through a resistor, short leg to GND
const int PIN_LED_MAKE = 22;
const int PIN_LED_MEMORY = 23;
#endif

enum : uint8_t {
  ID_KNOB = 1, ID_RECORD = 11, ID_CONFIRM = 13, ID_LEFT = 14, ID_RIGHT = 15,
  ID_CANCEL = 23, ID_MODE = 31, ID_AUTOPLAY = 32
};

const unsigned long DEBOUNCE_MS = 25;
const int POT_STEPS = 24;         // the turn range is split into this many steps
const int POT_MARGIN = 30;        // extra ADC counts needed to leave a step, stops flicker
const int COUNTS_PER_DETENT = 4;  // encoder only

// ---- Debounced input ----
struct Input {
  int pin;
  uint8_t id;
  bool stable;          // debounced level, HIGH = released
  bool lastRead;
  unsigned long changedAt;
};

Input record   = {PIN_RECORD,   ID_RECORD};
Input cancel   = {PIN_CANCEL,   ID_CANCEL};
Input btnLeft  = {PIN_LEFT,     ID_LEFT};
Input confirm  = {PIN_CONFIRM,  ID_CONFIRM};
Input btnRight = {PIN_RIGHT,    ID_RIGHT};
Input autoplay = {PIN_AUTOPLAY, ID_AUTOPLAY};
Input mode     = {PIN_MODE,     ID_MODE};
Input* pressButtons[] = {&record, &cancel, &btnLeft, &confirm, &btnRight};

#if USE_POT
int potStep = 0;
float potSmooth = 0;
#else
ESP32Encoder encoder;
long lastDetent = 0;
#endif

NimBLEServer* server = nullptr;
NimBLECharacteristic* inputChar = nullptr;
volatile bool sendModeSoon = false;
volatile uint8_t ledMode = 0;
volatile unsigned long ledModeSince = 0;

void setupInput(Input& in) {
  pinMode(in.pin, INPUT_PULLUP);
  in.stable = in.lastRead = digitalRead(in.pin);
  in.changedAt = 0;
}

// Returns true when the debounced level changed.
bool updateInput(Input& in) {
  bool reading = digitalRead(in.pin);
  if (reading != in.lastRead) {
    in.lastRead = reading;
    in.changedAt = millis();
  }
  if (reading != in.stable && millis() - in.changedAt > DEBOUNCE_MS) {
    in.stable = reading;
#if SERIAL_DEBUG
    Serial.printf("pin %d -> %s\n", in.pin, reading == LOW ? "LOW (pressed)" : "HIGH (released)");
#endif
    return true;
  }
  return false;
}

bool isConnected() {
  return server && server->getConnectedCount() > 0;
}

void send(uint8_t id, int8_t value) {
#if SERIAL_DEBUG
  Serial.printf("send [%d, %d]%s\n", id, value, isConnected() ? "" : "  (not sent: no app connected)");
#endif
  if (!isConnected() || !inputChar) return;
  uint8_t packet[2] = {id, (uint8_t)value};
  inputChar->setValue(packet, 2);
  inputChar->notify();
}

#if USE_POT
int readPot() {
  long sum = 0;
  for (int i = 0; i < 8; i++) sum += analogRead(PIN_POT);
  return sum / 8;                                   // 0..4095
}

// Turns the absolute position into steps, so the app sees the same packets as with an encoder.
void updatePot() {
  potSmooth += (readPot() - potSmooth) * 0.2f;
  const float width = 4096.0f / POT_STEPS;
  float center = (potStep + 0.5f) * width;
  if (fabsf(potSmooth - center) > width * 0.5f + POT_MARGIN) {
    int next = constrain((int)(potSmooth / width), 0, POT_STEPS - 1);
    if (next != potStep) {
      send(ID_KNOB, (int8_t)(next - potStep));
      potStep = next;
    }
  }
}
#endif

void setLed(uint8_t pattern) {
  ledMode = pattern;
  ledModeSince = millis();
}

void setModeLeds(uint8_t makeMode) {
#if MODE_LEDS
  digitalWrite(PIN_LED_MAKE, makeMode ? HIGH : LOW);
  digitalWrite(PIN_LED_MEMORY, makeMode ? LOW : HIGH);
#endif
}

void updateLed() {
  unsigned long t = millis() - ledModeSince;
  bool on = false;
  switch (ledMode) {
    case 1: on = (millis() / 500) % 2 == 0; break;          // slow blink
    case 2: on = true; break;                                // steady
    case 3:                                                  // three flashes, then off
      if (t >= 900) { ledMode = 0; on = false; }
      else on = (t / 150) % 2 == 0;
      break;
    default: on = false;
  }
  digitalWrite(PIN_LED, on ? HIGH : LOW);
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo& info, int reason) override {
    setLed(0);
    NimBLEDevice::startAdvertising();
  }
};

class InputCallbacks : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic* c, NimBLEConnInfo& info, uint16_t subValue) override {
    if (subValue > 0) sendModeSoon = true;  // tell the app where the switch is
  }
};

class LedCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& info) override {
    NimBLEAttValue value = c->getValue();
    if (value.size() > 0) setLed(value.data()[0]);
    if (value.size() > 1) setModeLeds(value.data()[1]);
  }
};

void setup() {
#if SERIAL_DEBUG
  Serial.begin(115200);
  Serial.printf("Height controller. Left %d, Right %d, Confirm %d, Cancel %d, Record %d\n",
                PIN_LEFT, PIN_RIGHT, PIN_CONFIRM, PIN_CANCEL, PIN_RECORD);
#endif
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, LOW);
#if MODE_LEDS
  pinMode(PIN_LED_MAKE, OUTPUT);
  pinMode(PIN_LED_MEMORY, OUTPUT);
#endif

#if USE_POT
  potSmooth = readPot();
  potStep = constrain((int)(potSmooth / (4096.0f / POT_STEPS)), 0, POT_STEPS - 1);
#else
  ESP32Encoder::useInternalWeakPullResistors = puType::up;
  encoder.attachFullQuad(PIN_ENC_A, PIN_ENC_B);
  encoder.clearCount();
#endif

  for (Input* b : pressButtons) setupInput(*b);
  setupInput(autoplay);
  setupInput(mode);
  setModeLeds(mode.stable == LOW ? 1 : 0);

  NimBLEDevice::init(DEVICE_NAME);
  server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService* service = server->createService(SERVICE_UUID);
  inputChar = service->createCharacteristic(INPUT_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  inputChar->setCallbacks(new InputCallbacks());
  NimBLECharacteristic* ledChar =
      service->createCharacteristic(LED_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  ledChar->setCallbacks(new LedCallbacks());
  service->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setName(DEVICE_NAME);
  adv->start();
}

void loop() {
#if USE_POT
  updatePot();
#else
  long detent = encoder.getCount() / COUNTS_PER_DETENT;
  if (detent != lastDetent) {
    long delta = constrain(detent - lastDetent, -127, 127);
    send(ID_KNOB, (int8_t)delta);
    lastDetent = detent;
  }
#endif

  // Momentary buttons: send on press.
  for (Input* b : pressButtons) {
    if (updateInput(*b) && b->stable == LOW) send(b->id, 1);
  }

  // Auto play: a latching switch toggles on every change, a momentary button on press.
  if (updateInput(autoplay)) {
#if AUTOPLAY_LATCHING
    send(ID_AUTOPLAY, 1);
#else
    if (autoplay.stable == LOW) send(ID_AUTOPLAY, 1);
#endif
  }

  // Mode switch: LOW = Make side.
  if (updateInput(mode) || sendModeSoon) {
    sendModeSoon = false;
    send(ID_MODE, mode.stable == LOW ? 1 : 0);
  }

  updateLed();
  delay(5);
}
