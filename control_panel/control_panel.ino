/*
 * J.S. AEROSPACE - CONTROL PANEL v1.1 (LCD Edition)
 * 
 * Hardware:
 * - Arduino (Uno/Nano)
 * - LCD 16x2 I2C (SDA -> A4, SCL -> A5)
 * - Botón MISSION GO -> Pin 2 a GND
 * - Botón RESET MET -> Pin 3 a GND
 * 
 * Librería requerida: LiquidCrystal_I2C
 */

#include <Wire.h>
#include <LiquidCrystal_I2C.h>

// Dirección I2C común: 0x27 o 0x3F
LiquidCrystal_I2C lcd(0x27, 16, 2);

const int PIN_GO = 2;
const int PIN_RESET = 3;

bool lastGo = HIGH;
bool lastReset = HIGH;

void setup() {
  pinMode(PIN_GO, INPUT_PULLUP);
  pinMode(PIN_RESET, INPUT_PULLUP);
  
  Serial.begin(9600);
  
  // Inicializar LCD
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("JS AEROSPACE");
  lcd.setCursor(0, 1);
  lcd.print("SISTEMA ONLINE");
  
  delay(1500);
  Serial.println("PANEL_READY");
}

void loop() {
  // 1. ESCUCHAR COMANDOS DESDE PC (FEEDBACK)
  if (Serial.available() > 0) {
    String input = Serial.readStringUntil('\n');
    input.trim();

    if (input.startsWith("ST_CLIENT_GO:")) {
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("ESTADO CLIENTE:");
      lcd.setCursor(0, 1);
      
      if (input.endsWith("1")) {
        lcd.print(">> [ GO ] <<");
      } else {
        lcd.print(">> [ NO-GO ] <<");
      }
    }
  }

  // 2. ENVIAR COMANDOS HACIA PC (BOTONES)
  bool currentGo = digitalRead(PIN_GO);
  if (currentGo == LOW && lastGo == HIGH) {
    Serial.println("CMD_GO");
    delay(250); 
  }
  lastGo = currentGo;

  bool currentReset = digitalRead(PIN_RESET);
  if (currentReset == LOW && lastReset == HIGH) {
    Serial.println("CMD_RESET");
    delay(250);
  }
  lastReset = currentReset;

  delay(20);
}
