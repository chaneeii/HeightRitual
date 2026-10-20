// Memory Meter controller -> iPhone app over Bluetooth Low Energy
//
//   [ Back ]                 ( Knob )
//   < Left      ( Confirm )     Right >
//
// Board:   ESP32 Dev Module
// Library: NimBLE-Arduino 2.x by h2zero
// Serial Monitor: 115200 baud
//
// Packets [id, value]: knob [1, +1] / [1, -1], Confirm [13, 1], Left [14, 1], Right [15, 1],
// Back [23, 1]. The app decides what each control does on each screen.

#include <NimBLEDevice.h>

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

// ---- Knob ----
// The box's knob rests with CLK and DT at the same level and both change on every click.
// Counter-clockwise DT moves first; clockwise CLK moves first or both move at the same moment.
// So: DT first is counter-clockwise, anything else clockwise. An interrupt on each pin notes
// which moved first; the click counts once both pins rest at a new level for 3 ms.

volatile bool moving = false;
volatile bool dtFirst = false;
volatile unsigned long lastChange = 0;
volatile int restLevel = HIGH;

void IRAM_ATTR onKnobPin() {
  int clk = digitalRead(PIN_CLK);
  int dt = digitalRead(PIN_DT);
  if (!moving && (clk != restLevel || dt != restLevel)) {
    moving = true;
    dtFirst = (dt != restLevel) && (clk == restLevel);
  }
  lastChange = micros();
}

void readKnob() {
  int clk = digitalRead(PIN_CLK);
  int dt = digitalRead(PIN_DT);

  noInterrupts();
  bool isMoving = moving;
  bool counterClockwise = dtFirst;
  unsigned long quietFor = micros() - lastChange;
  int rest = restLevel;
  interrupts();

  if (!isMoving || quietFor < 3000 || clk != dt) return;   // still turning or bouncing

  noInterrupts();
  moving = false;
  restLevel = clk;
  interrupts();

  if (clk == rest) return;   // came back to where it was: no click

  int step = counterClockwise ? -1 : 1;
  if (REVERSE_KNOB) step = -step;
  send(1, step, step > 0 ? "Knob +" : "Knob -");
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

  pinMode(PIN_CLK, INPUT_PULLUP);
  pinMode(PIN_DT, INPUT_PULLUP);
  restLevel = digitalRead(PIN_CLK);
  attachInterrupt(digitalPinToInterrupt(PIN_CLK), onKnobPin, CHANGE);
  attachInterrupt(digitalPinToInterrupt(PIN_DT), onKnobPin, CHANGE);

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
  delay(1);
}
