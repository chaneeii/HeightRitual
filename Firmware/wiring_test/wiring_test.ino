// Wiring test for the Memory Meter box, live view. No Bluetooth, no libraries.
// Serial Monitor at 115200 baud. Twice a second it prints the four buttons and the knob count,
// so a button that is held (or stuck) keeps showing as DOWN. The board LED is on while any
// button reads DOWN. Classic ESP32 DevKit pins (same as Firmware/controller).

const int   N = 4;
const int   PINS[N]  = {25, 33, 27, 14};
const char* NAMES[N] = {"Back", "Left", "Confirm", "Right"};
const int   PIN_ENC_A = 32;   // encoder CLK
const int   PIN_ENC_B = 26;   // encoder DT
const int   PIN_LED   = 2;
unsigned long lastPrint = 0;

volatile long encCount = 0;
volatile uint8_t encState = 0;
const int8_t ENC_TABLE[16] = {0, -1, 1, 0, 1, 0, 0, -1, -1, 0, 0, 1, 0, 1, -1, 0};

void IRAM_ATTR onEncoder() {
  encState = ((encState << 2) | (digitalRead(PIN_ENC_A) << 1) | digitalRead(PIN_ENC_B)) & 0x0F;
  encCount += ENC_TABLE[encState];
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_LED, OUTPUT);
  for (int i = 0; i < N; i++) pinMode(PINS[i], INPUT_PULLUP);
  pinMode(PIN_ENC_A, INPUT_PULLUP);
  pinMode(PIN_ENC_B, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_A), onEncoder, CHANGE);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_B), onEncoder, CHANGE);
  for (int i = 0; i < 3; i++) { digitalWrite(PIN_LED, HIGH); delay(200); digitalWrite(PIN_LED, LOW); delay(200); }
  Serial.println();
  Serial.println("Wiring test. '----' = not pressed, 'DOWN' = pressed (connected to GND).");
  Serial.println("With no finger on any button, every column must show ----.");
  Serial.println("Turn the knob one click clockwise: knob should go up by 4 (or 2 on some knobs).");
}

void loop() {
  bool any = false;
  bool down[N];
  for (int i = 0; i < N; i++) {
    down[i] = digitalRead(PINS[i]) == LOW;
    any = any || down[i];
  }
  digitalWrite(PIN_LED, any ? HIGH : LOW);

  if (millis() - lastPrint >= 500) {
    lastPrint = millis();
    for (int i = 0; i < N; i++) {
      Serial.printf("%s(%d): %s   ", NAMES[i], PINS[i], down[i] ? "DOWN" : "----");
    }
    noInterrupts();
    long count = encCount;
    interrupts();
    Serial.printf("knob: %ld\n", count);
  }
  delay(10);
}
