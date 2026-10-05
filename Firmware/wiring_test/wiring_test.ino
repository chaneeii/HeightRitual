// Wiring test, live view. No Bluetooth, no libraries. Serial Monitor at 115200 baud.
// Twice a second it prints the state of all five buttons, so a button that is held
// (or stuck) keeps showing as DOWN. The LED is on while any button reads DOWN.

const int   N = 5;
const int   PINS[N]  = {18, 25, 26, 27, 14};
const char* NAMES[N] = {"Record", "Cancel", "Left", "Confirm", "Right"};
const int   PIN_LED  = 2;   // labelled TX2 on the 30-pin board
unsigned long lastPrint = 0;

void setup() {
  Serial.begin(115200);
  pinMode(PIN_LED, OUTPUT);
  for (int i = 0; i < N; i++) pinMode(PINS[i], INPUT_PULLUP);
  for (int i = 0; i < 3; i++) { digitalWrite(PIN_LED, HIGH); delay(200); digitalWrite(PIN_LED, LOW); delay(200); }
  Serial.println();
  Serial.println("Wiring test. '----' = not pressed, 'DOWN' = pressed (connected to GND).");
  Serial.println("With no finger on any button, every column must show ----");
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
    Serial.println();
  }
  delay(10);
}
