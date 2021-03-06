#include <ctype.h>

int LED      = 9;
int CC_DC    = 5;
int CC_DD    = 6;
int CC_RST   = 7;

#define CMD_XDATA        'M'
#define CMD_READ_CODE    'C'
#define CMD_LED          'L'
#define CMD_ENTER_DEBUG  'D'
#define CMD_EXTENDED     'X'
#define CMD_RESET        'R'

#define BUFFER_SIZE      140

byte inByte;
byte inBuffer[BUFFER_SIZE];
byte idx;
byte data0;
byte data1;
byte data2;

void setup()
{
  CLKPR = 0x80;
  CLKPR = 0;

  pinMode(LED, OUTPUT);

  pinMode(CC_DC, OUTPUT);
  digitalWrite(CC_DC, LOW);
  pinMode(CC_DD, OUTPUT);
  digitalWrite(CC_DD, LOW);
  pinMode(CC_RST, INPUT);
  digitalWrite(CC_RST, LOW);

  Serial.begin(115200);
  LED_OFF();
  Serial.print("\r\n:");
  data1 = 0;
  idx = 0;
}

void loop()
{
  if (Serial.available() <= 0)
    return;

  inByte = Serial.read();
  if (inByte != '\r') {
    inByte = toupper(inByte);
    if (inByte >= ' ') {
      Serial.print(inByte);
      if (data1)
        return;
      if (idx < BUFFER_SIZE) {
        inBuffer[idx] = inByte;
        ++idx;
        return;
      }
      data1 = 1;
      return;
    }
    data1 = 2;
    return;
  }

  Serial.println();
  if (!idx) {
    sendOK();
    return;
  }
  if (data1 || idx <= 2) {
    Serial.print("BAD PACKET:");
    printHexln(data1);
    sendERROR();
    return;
  }

  inByte = checkChecksum();
  if (inByte) {
    Serial.print("BAD CHECKSUM:");
    printHexln(0-inByte);
    sendERROR();
    return;
  }
  // Remove checksum from length
  idx -= 2;

  switch(inBuffer[0]) {
  default:
    Serial.print("BAD COMMAND:");
    Serial.println(inBuffer[0]);
    break;
  case CMD_ENTER_DEBUG:
    if(idx == 1) {
      dbg_enter();
      sendOK();
      return;
    }
    break;
  case CMD_LED:
    if (idx == 2)
      switch (inBuffer[1]){
      case '0':
        LED_OFF();
        sendOK();
        return;
      case '1':
        LED_ON();
        sendOK();
        return;
      case '3':
        digitalWrite(CC_DC, HIGH);
        sendOK();
        return;
      case '4':
        digitalWrite(CC_DC, LOW);
        sendOK();
        return;
      case '5':
        digitalWrite(CC_DD, HIGH);
        sendOK();
        return;
      case '6':
        digitalWrite(CC_DD, LOW);
        sendOK();
        return;
      case '7':
        digitalWrite(CC_RST, HIGH);
        sendOK();
        return;
      case '8':
        digitalWrite(CC_RST, LOW);
        sendOK();
        return;
      }
    break;
  case CMD_RESET:
    if (idx == 2)
      switch (inBuffer[1]){
      case '0':
        dbg_reset(0);
        sendOK();
        return;
      case '1':
        dbg_reset(1);
        sendOK();
        return;
      }
    break;
  case CMD_XDATA:
    if (idx >= 8) {
      if(isHexByte(2) & isHexByte(4) & isHexByte(6)) {
        byte cnt = getHexByte(6);
        if(!cnt) {
          sendOK();
          return;
        }
        if(cnt > 64) {
          Serial.println("NO MORE 64 BYTES");
          sendERROR();
          return;
        }
        byte i = 8;
        dbg_instr(0x90, getHexByte(2), getHexByte(4));            // MOV DPTR #high #low
        data1 = 1;
        LED_TOGGLE();
        if (inBuffer[1] == 'W') {
          while (cnt-- > 0) {
            if (i + 1 >= idx) {
              Serial.println("NO DATA");
              sendERROR();
              return;
            }
            if (isHexByte(i)) {
              dbg_instr(0x74, getHexByte(i));
              dbg_instr(0xF0);
              dbg_instr(0xA3);
              i += 2;
            } 
            else {
              Serial.println("NO HEX");
              sendERROR();
              return;
            }
          }
        } 
        else if (inBuffer[1] == 'R' || inBuffer[1] == 'C') {
          data2 = 1;
          if (inBuffer[1] == 'C')
            data2 = 0;
          Serial.print("READ:");
          byte csum = 0;
          while (cnt > 0) {
            --cnt;
            if(data2)
              data0 = dbg_instr(0xE0);
            else {
              dbg_instr(0xE4);
              data0 = dbg_instr(0x93);
            }
            dbg_instr(0xA3);
            csum += data0;
            printHex(data0);
          }
          csum = (0 - (~csum));
          printHexln(csum);
        }
        else
          break;
        sendOK();
        return;
      }
    }
    break;
  case CMD_EXTENDED:
    LED_TOGGLE();
    byte i = 1;
    byte cnt;
    data1 = 1;
    while (data1 && i < idx) {
      switch (inBuffer[i++]) {
      case 'W':
        if (i < idx && isdigit(inBuffer[i])) {
          cnt = inBuffer[i++] - '0';
          if (!cnt)
            continue;
          while (cnt > 0) {
            if (i + 1 >= idx) {
              data1 = 0;
              break;
            }
            --cnt;
            if (isHexByte(i)) {
              dbg_write(getHexByte(i));
              i += 2;
            } 
            else {
              data1 = 0;
              break;
            }
          }
          if(data1)
          {
            cc_delay(10);
            continue;
          }
        }
        data1 = 0;
        break;
      case 'R':
        if (i < idx && isdigit(inBuffer[i])) {
          cnt = inBuffer[i++] - '0';
          Serial.print("READ:");
          byte csum = 0;
          while (cnt > 0) {
            --cnt;
            data0 = dbg_read();
            csum += data0;
            printHex(data0);
          }
          csum = (0 - (~csum));
          printHexln(csum);
          continue;
        }
        data1 = 0;
        break;
      default:
        data1 = 0;
        break;
      }
    }
    LED_TOGGLE();
    if (data1) {
      sendOK();
      return;
    }
    break;
  }

  sendERROR();
}

byte isHexDigit(unsigned char c) {
  if (c >= '0' && c <= '9')
    return 1;
  else if (c >= 'A' && c <= 'F')
    return 1;
  return 0;
}

byte isHexByte(byte index) {
  return isHexDigit(inBuffer[index]) & isHexDigit(inBuffer[index + 1]);
}

byte getHexDigit(unsigned char c) {
  if (c >= '0' && c <= '9')
    c -= '0';
  else if (c >= 'A' && c <= 'F')
    c -= ('A' - 10);
  return c;
}

byte getHexByte(byte index) {
  return ((getHexDigit(inBuffer[index]) << 4) | getHexDigit(inBuffer[index + 1]));
}

byte checkChecksum() {
  if (idx <= 2)
    return 0;

  byte csum = 0;
  byte imax = idx - 2;
  byte i = 0;
  for(; i < imax; ++i)
    csum += inBuffer[i];
  csum = ~csum;
  return (csum + getHexByte(i));
}

void LED_OFF()
{
  digitalWrite(LED, LOW);
}

void LED_ON()
{
  digitalWrite(LED, HIGH);
}

void LED_TOGGLE()
{
  digitalWrite(LED, !digitalRead(LED));
}

void BlinkLED(byte blinks)
{
  while(blinks-- > 0)
  {
    LED_ON();
    delay(500);
    LED_OFF();
    delay(500);
  }
  delay(1000);
}

void cc_delay( unsigned char d )
{
  volatile unsigned char i = d;
  while( i-- );
}

void dbg_clock_high() {
  digitalWrite(CC_DC, HIGH);
}

void dbg_clock_low() {
  digitalWrite(CC_DC, LOW);
}

// 1 - activate RESET (low)
// 0 - deactivate RESET (high)
void dbg_reset(unsigned char state) {
  if (state) {
    pinMode(CC_RST, OUTPUT);
  } 
  else {
    pinMode(CC_RST, INPUT);
  }
  cc_delay(200);
}
void dbg_enter() {
  dbg_reset(1);
  dbg_clock_high();
  cc_delay(1);
  dbg_clock_low();
  cc_delay(1);
  dbg_clock_high();
  cc_delay(1);
  dbg_clock_low();
  cc_delay(200);
  dbg_reset(0);
}

// dir = 1 output
// dir = x input, data = 0xFF;
unsigned char dbg_io(unsigned char data, unsigned char dir) {
  unsigned char cnt;
  if (dir)
    pinMode(CC_DD, OUTPUT);
  else {
    pinMode(CC_DD, INPUT);
    data = 0xFF;
  }

  for (cnt = 8; cnt; cnt--) {
    if (data & 0x80)
      digitalWrite(CC_DD, HIGH);
    else
      digitalWrite(CC_DD, LOW);
    data <<= 1;
    dbg_clock_high();
    cc_delay(3);
    if (digitalRead(CC_DD))
      data |= 0x01;

    dbg_clock_low();
    cc_delay(3);
  }

  if (dir)
    digitalWrite(CC_DD, LOW);
  else {
    pinMode(CC_DD, OUTPUT);
    digitalWrite(CC_DD, LOW);
  }

  return data;
}

byte dbg_read() {
  byte cnt, data;
  pinMode(CC_DD, INPUT);

  for (cnt = 8; cnt; cnt--) {
    data <<= 1;
    dbg_clock_high();
    cc_delay(3);
    if (digitalRead(CC_DD))
      data |= 0x01;
    dbg_clock_low();
    cc_delay(3);
  }
  pinMode(CC_DD, OUTPUT);
  digitalWrite(CC_DD, LOW);
  return data;
}

void dbg_write(byte data) {
  byte cnt;
  pinMode(CC_DD, OUTPUT);

  for (cnt = 8; cnt; cnt--) {
    if (data & 0x80)
      digitalWrite(CC_DD, HIGH);
    else
      digitalWrite(CC_DD, LOW);
    data <<= 1;
    dbg_clock_high();
    cc_delay(3);
    if (digitalRead(CC_DD))
      data |= 0x01;

    dbg_clock_low();
    cc_delay(3);
  }

  digitalWrite(CC_DD, LOW);
}

void printHex(unsigned char data) {
  if (data < 0x10)
    Serial.print('0');
  Serial.print(data, HEX);
}

void printHexln(unsigned char data) {
  if (data < 0x10)
    Serial.print('0');
  Serial.println(data, HEX);
}

byte dbg_instr(byte in0, byte in1, byte in2) {
  dbg_write(0x57);
  dbg_write(in0);
  dbg_write(in1);
  dbg_write(in2);
  cc_delay(6);
  return dbg_read();
}
byte dbg_instr(byte in0, byte in1) {
  dbg_write(0x56);
  dbg_write(in0);
  dbg_write(in1);
  cc_delay(6);
  return dbg_read();
}
byte dbg_instr(byte in0) {
  dbg_write(0x55);
  dbg_write(in0);
  cc_delay(6);
  return dbg_read();
}

void sendERROR() {
  Serial.print("ERROR\r\n:");
  data1 = 0;
  idx = 0;
}

void sendOK() {
  Serial.print("OK\r\n:");
  data1 = 0;
  idx = 0;
}


