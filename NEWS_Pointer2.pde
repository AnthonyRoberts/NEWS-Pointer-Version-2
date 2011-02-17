/*
A lot of this is based on the Pong Clock
February 2011
*/

#include <ht1632c.h>                     // Holtek LED driver by WestFW - updated to HT1632C by Nick Hall
#include <avr/pgmspace.h>                // Enable data to be stored in Flash Mem as well as SRAM              
#include <Font.h>                        // Font library
#include <Button.h>                      // Button library by Alexander Brevig
#include <Servo.h>                       // Servo Library
#include <SPI.h>
#include <Ethernet.h>

Servo myservo;                           // create servo object to control a servo

// Enter a MAC address and IP address for your controller below.
// The IP address will be dependent on your local network:
byte mac[] = { 0x90, 0xA2, 0xDA, 0x00, 0x1F, 0x72 };
byte ip[] = { 192,168,128,6 };
byte gateway[] = { 192,168,128,254};	
byte subnet[] = { 255, 255, 255, 0 };
byte server[] = { 192,168,128,50 }; // NEWS

// Initialize the Ethernet client library
// with the IP address and port of the server 
// that you want to connect to (port 80 is default for HTTP):
Client client(server, 80);

#define ASSERT(condition)                // Nothing
#define X_MAX 47                         // Matrix X max LED coordinate (for 2 displays placed next to each other)
#define Y_MAX 15                         // Matrix Y max LED coordinate (for 2 displays placed next to each other)
#define NUM_DISPLAYS 2                   // Num displays for shadow ram data allocation
#define FADEDELAY 40                     // Time to fade display to black
#define plot(x,y,v)  ht1632_plot(x,y,v)  // Plot LED
#define cls          ht1632_clear        // Clear display
#define MAX_MODE 4                       // Number of Modes
#define CURRENT_VERSION "2.0"            // Version - Shown at startup
#define GREENSTATUS 1
#define REDSTATUS 2
#define WAKEFIELD_LED 4
#define WARWICK_LED 8
#define WATFORD_LED 16
#define BOURNEEND_LED 32
#define GLOBIX_LED 64
#define MAIDSTONE_LED 128


static const byte ht1632_data = 2;      // Data pin for sure module (Pin 7)
static const byte ht1632_wrclk = 3;     // Write clock pin for sure module (Pin 5)
static const byte ht1632_cs[2] = {4,5};  // Chip_selects one for each sure module. Remember to set the DIP switches on the modules too.

Button buttonA = Button(A2,PULLUP);       // Setup button A (using button library)
Button buttonB = Button(A3,PULLUP);       // Setup button B (using button library)

int news_mode = 0;                      // Default clock mode (NEWS)
int max_critical = 15;                   // Maximum Critical Calls (for pointer)
int servo_start = 38;                    // Servo Start Angle (for zero critical)
int servo_end = 136;                     // Servo Finish Angle (for max_critical)
int critical_LED = GREENSTATUS;

int clockPin = 8;                        // Green
int latchPin = 7;                        // Yellow
int dataPin = 6;                         // White

int led_mask = 0;                        // This will be read from the NEWS server
byte LED_State = 0;                      // Current byte we send to the 595 Shift Register

// ****** SET-UP ******

void setup ()  
{
  Serial.begin(9600);                    // DS1307 clock chip setup
  myservo.attach(9);                     // attaches the servo on pin 9 to the servo object
  myservo.write(90);                     // Safe Position
  
  pinMode(latchPin, OUTPUT);
  pinMode(clockPin, OUTPUT);
  pinMode(dataPin, OUTPUT);

  Ethernet.begin(mac, ip);
  delay(1000);

  ht1632_setup();                        // Setup display (uses flow chart from page 17 of sure datasheet)
  randomSeed(analogRead(1));             // Setup random number generator
  printver();                            // Display clock software version on led screen
  LED_State = 252 & GREENSTATUS;         // Set the default LED condition (All Offices + Green)
  set_LED(0, 0);                         // Turn the LEDs on
  delay(2000);
}


// ****** MAIN ******

void loop ()
{

  
  //reset clock type news_mode
  switch (news_mode){
    case 0: NEWS(); break;
    case 1: LED_Test(); break; 
    case 2: NEWS_Demo(); break; 
    case 3: calibrate(); break;
  }
  
}


void set_LED(byte TurnOn, byte TurnOff) {
  LED_State = LED_State | TurnOn;
  LED_State = LED_State ^ TurnOff;
  
  LED_State = LED_State & 252;           // Clear the two bits for the Status LED
  LED_State = LED_State | critical_LED;  // Set the Status LED
  
  digitalWrite(latchPin, LOW);
  shiftOut(dataPin, clockPin, MSBFIRST, LED_State);
  digitalWrite(latchPin, HIGH);
}


void NEWS() {
  char line1[] = "CRIT:   ";
  char line2[] = "WARN:   ";
  
  LED_State = 0;

  while (1) {
    int crit = 0;
    int warn = 0;
    
// Get the number of Critical    
    if (client.connect()) {
        client.print("GET /just_critical.php");
        client.println();
        delay(1000);
    }
    
    do {
      if (client.available()) {
        crit = client.read();
        client.flush();
      }
    } while ( client.connected() );
    
    if (!client.connected()) {
      client.stop();
    } 

    critical_arm(crit);
    line1[5] = ' ';
    line1[6] = ' ';
    line1[7] = ' ';
    if (crit <= 9) itoa(crit, &line1[7], 10);
    else if (crit <= 99) itoa(crit, &line1[6], 10);
    else itoa(crit, &line1[7], 10);


// Get the number of Warning
    if (client.connect()) {
        client.print("GET /just_warning.php");
        client.println();
        delay(1000);
    }
    
    do {
      if (client.available()) {
        warn = client.read();
        client.flush();
      }
    } while ( client.connected() );
    
    if (!client.connected()) {
      client.stop();
    } 

    line2[5] = ' ';
    line2[6] = ' ';
    line2[7] = ' ';
    if (warn <= 9) itoa(warn, &line2[7], 10);
    else if (warn <= 99) itoa(warn, &line2[6], 10);
    else itoa(warn, &line2[7], 10);
    
// Get the LED Mask 
    if (client.connect()) {
        client.print("GET /led_mask.php");
        client.println();
        delay(1000);
    }
    
    do {
      if (client.available()) {
        led_mask = client.read();
        client.flush();
      }
    } while ( client.connected() );
    
    if (!client.connected()) {
      client.stop();
    }
    set_LED(252, 0);         // Turn all the Office LEDs on
    set_LED(0, led_mask);    // Now turn off any where something is critical
    


  cls();
  flashing_cursor(0,0,5,7,1);    // Change the 1 at the end for a more "considerd" pause before the display
  int i = 0;
  while (line1[i]) {
    flashing_cursor(i*6,0,5,7,0);
    ht1632_putchar(i*6, 0, line1[i]);
    i++;
//check for button press and exit if there is one.
    if(buttonA.uniquePress()) {
       switch_mode();
       return;      
    }
  }
  i = 0;
  while (line2[i]) {
    flashing_cursor(i*6,8,5,7,0);
    ht1632_putchar(i*6, 8, line2[i]);
//check for button press and exit if there is one.
    if(buttonA.uniquePress()) {
       switch_mode();
       return;      
    }
    i++;
  }
  NEWS_delay(20000);
  if (buttonA.isPressed()) {
    switch_mode();
    return;
  }
  }
}


/*
 * copy of the button_delay but with added office flash
 * like regular delay but can be quit by a button press
 */
void NEWS_delay(int wait) {
  int i = 0;
  long time = millis();
  int flasher = 0;
  
  while ( i < wait) {
    //check if a button is pressed, if it is, quit waiting
    if(buttonA.uniquePress()) {
      return;
      }
      if (millis() > (time + 500 + (flasher * 500))) {  // It's been a second, so lets toggle any LED mask
        if (flasher == 0) {   // Are all the LEDs on at the moment?
          set_LED(0, led_mask);         // turn off those that are critical
          flasher = 1;
        } else {
          set_LED(252, 0);              // Turn all the office LED's on  
          flasher = 0;
          }
        time = millis();
      }
      //else wait a moment
      delay (1);
      i++;
  }
}


/*
 * TEST - Activate all devices and lights
 */
void LED_Test() {
  char line1[] = "TESTING";
  char line2[] = "1: LED";
  
  cls();
  int i = 0;
  while (line1[i]) {
    flashing_cursor(i*6,0,5,7,0);
    ht1632_putchar(i*6, 0, line1[i]);
    i++;
//check for button press and exit if there is one.
    if(buttonA.uniquePress()) {
       switch_mode();
       return;      
    }
  }
  i = 0;
  while (line2[i]) {
    flashing_cursor(i*6,8,5,7,0);
    ht1632_putchar(i*6, 8, line2[i]);
//check for button press and exit if there is one.
    if(buttonA.uniquePress()) {
       switch_mode();
       return;      
    }
    i++;
  }

    digitalWrite(latchPin, LOW);
    shiftOut(dataPin, clockPin, MSBFIRST, 16);
    digitalWrite(latchPin, HIGH);
    
    delay(2000);

  for (int blueLoop = 0; blueLoop < 5; blueLoop++) {
    digitalWrite(latchPin, LOW);
    shiftOut(dataPin, clockPin, MSBFIRST, 0);
    digitalWrite(latchPin, HIGH);
    delay(200);

    digitalWrite(latchPin, LOW);
    shiftOut(dataPin, clockPin, MSBFIRST, 255);
    digitalWrite(latchPin, HIGH);
    delay(200);
  }

  for (int blueLoop = 0; blueLoop < 3; blueLoop++) {
    int blueLED = 1;
    while (blueLED < 256) {
      digitalWrite(latchPin, LOW);
      shiftOut(dataPin, clockPin, MSBFIRST, 0);
      digitalWrite(latchPin, HIGH);
      button_delay(250);
      if (buttonA.isPressed()) {
        news_mode = 0;
        return;
      }

      digitalWrite(latchPin, LOW);
      shiftOut(dataPin, clockPin, MSBFIRST, blueLED);
      digitalWrite(latchPin, HIGH);
      button_delay(250);
      if (buttonA.isPressed()) {
        news_mode = 0;
        return;
      }
      
      blueLED = blueLED << 1;
    }
  }

  news_mode = 0;
}



/*
 * DEMO - Sample Behaviour
 */
void NEWS_Demo() {
  char line1[] = "DEMO";
  char line2[] = "MODE";
  
  cls();
  int i = 0;
  while (line1[i]) {
    flashing_cursor(i*6,0,5,7,0);
    ht1632_putchar(i*6, 0, line1[i]);
    i++;
//check for button press and exit if there is one.
    if(buttonA.uniquePress()) {
       switch_mode();
       return;      
    }
  }
  i = 0;
  while (line2[i]) {
    flashing_cursor(i*6,8,5,7,0);
    ht1632_putchar(i*6, 8, line2[i]);
//check for button press and exit if there is one.
    if(buttonA.uniquePress()) {
       switch_mode();
       return;      
    }
    i++;
  }
  delay(1500);

  int last_crit_demo = 0;
  int crit_demo = 0;
  char crit_line[] = "CRIT:   ";  
  for (i = 0; crit_line[i]; ht1632_putchar(i * 6, 8, crit_line[i++]));
  delay(1000);
  for (int demo_loop = 0; demo_loop < 8; demo_loop++) {
    while (crit_demo == last_crit_demo) {
      crit_demo = random(max_critical + 3);
    }
    last_crit_demo = crit_demo;
    itoa(crit_demo, &crit_line[6], 10);
    for (i = 0; i <  3; ht1632_putchar(((5 + i++) * 6), 8, ' '));
    for (i = 0; crit_line[i]; ht1632_putchar(i * 6, 8, crit_line[i++]));
    critical_arm(crit_demo);
    button_delay(2000);
    if (buttonA.isPressed()) {
      news_mode = 0;
      return;
    }
  }
  critical_arm(0);  // Put the arm to the Zero position
  
  
// Turn on the Office LEDs
  textline(2, "Wakef'ld");
  digitalWrite(latchPin, LOW);
  shiftOut(dataPin, clockPin, MSBFIRST, 4);
  digitalWrite(latchPin, HIGH);
  button_delay(2000);
  if (buttonA.isPressed()) {
    news_mode = 0;
    return;
  }

  textline(2, "Warwick ");
  digitalWrite(latchPin, LOW);
  shiftOut(dataPin, clockPin, MSBFIRST, 8);
  digitalWrite(latchPin, HIGH);
  button_delay(2000);
  if (buttonA.isPressed()) {
    news_mode = 0;
    return;
  }

  textline(2, "Watford ");
  digitalWrite(latchPin, LOW);
  shiftOut(dataPin, clockPin, MSBFIRST, 16);
  digitalWrite(latchPin, HIGH);
  button_delay(2000);
  if (buttonA.isPressed()) {
    news_mode = 0;
    return;
  }

  textline(2, "Bourne E");
  digitalWrite(latchPin, LOW);
  shiftOut(dataPin, clockPin, MSBFIRST, 32);
  digitalWrite(latchPin, HIGH);
  button_delay(2000);
  if (buttonA.isPressed()) {
    news_mode = 0;
    return;
  }

  textline(2, "Globix  ");
  digitalWrite(latchPin, LOW);
  shiftOut(dataPin, clockPin, MSBFIRST, 64);
  digitalWrite(latchPin, HIGH);
  button_delay(2000);
  if (buttonA.isPressed()) {
    news_mode = 0;
    return;
  }

  textline(2, "Maidst'n");
  digitalWrite(latchPin, LOW);
  shiftOut(dataPin, clockPin, MSBFIRST, 128);
  digitalWrite(latchPin, HIGH);

  button_delay(2000);
  if (buttonA.isPressed()) {
    news_mode = 0;
    return;
  }

  button_delay(2000);
  news_mode = 0;
}

void textline(int which_Line, char text_Msg[]) {
  for (int i = 0; text_Msg[i]; ht1632_putchar(i * 6, 8, text_Msg[i++]));
}



/*
 * CALIBRATE - Adjust Pointer Start & End
 */
void calibrate() {
  max_critical = set_value(0, max_critical, 5, 100);
  servo_start  = set_value(1, servo_start, 0, 100);
  servo_end    = set_value(1, servo_end, servo_start+1, 180);
  cls();
  news_mode = 0;
}


/*
 * Move the ARM based on Critical Calls
 */
void critical_arm(int critical_calls) {
  if (critical_calls > max_critical) {
    critical_calls = max_critical;
  }
  if (critical_calls < 0) {
    critical_calls = 0;
  }
  
  int arm_angle = map(critical_calls, 0, max_critical, servo_start, servo_end);
 
  myservo.write(arm_angle);
  
// Light the Status LED
  if (critical_calls == 0) {
    critical_LED = GREENSTATUS;
    set_LED(0,0);     // Green On, Red Off
  } else {
    critical_LED = REDSTATUS;
    set_LED(0,0);     // Red On, Green Off
  }

}
 



/*
 * ht1632_chipselect / ht1632_chipfree
 * Select or de-select a particular ht1632 chip. De-selecting a chip ends the commands being sent to a chip.
 * CD pins are active-low; writing 0 to the pin selects the chip.
 */
void ht1632_chipselect(byte chipno)
{
  DEBUGPRINT("\nHT1632(%d) ", chipno);
  digitalWrite(chipno, 0);
}

void ht1632_chipfree(byte chipno)
{
  DEBUGPRINT(" [done %d]", chipno);
  digitalWrite(chipno, 1);
}


/*
 * ht1632_writebits
 * Write bits (up to 8) to h1632 on pins ht1632_data, ht1632_wrclk Chip is assumed to already be chip-selected
 * Bits are shifted out from MSB to LSB, with the first bit sent being (bits & firstbit), shifted till firsbit is zero.
 */
void ht1632_writebits (byte bits, byte firstbit)
{
  DEBUGPRINT(" ");
  while (firstbit) {
    DEBUGPRINT((bits&firstbit ? "1" : "0"));
    digitalWrite(ht1632_wrclk, LOW);
    if (bits & firstbit) {
      digitalWrite(ht1632_data, HIGH);
    } 
    else {
      digitalWrite(ht1632_data, LOW);
    }
    digitalWrite(ht1632_wrclk, HIGH);
    firstbit >>= 1;
  }
}


/*
 * ht1632_sendcmd
 * Send a command to the ht1632 chip. A command consists of a 3-bit "CMD" ID, an 8bit command, and one "don't care bit".
 *   Select 1 0 0 c7 c6 c5 c4 c3 c2 c1 c0 xx Free
 */
static void ht1632_sendcmd (byte d, byte command)
{
  ht1632_chipselect(ht1632_cs[d]);        // Select chip
  ht1632_writebits(HT1632_ID_CMD, 1<<2);  // send 3 bits of id: COMMMAND
  ht1632_writebits(command, 1<<7);        // send the actual command
  ht1632_writebits(0, 1);         	  // one extra dont-care bit in commands.
  ht1632_chipfree(ht1632_cs[d]);          //done
}


/*
 * ht1632_senddata
 * send a nibble (4 bits) of data to a particular memory location of the
 * ht1632.  The command has 3 bit ID, 7 bits of address, and 4 bits of data.
 *    Select 1 0 1 A6 A5 A4 A3 A2 A1 A0 D0 D1 D2 D3 Free
 * Note that the address is sent MSB first, while the data is sent LSB first!
 * This means that somewhere a bit reversal will have to be done to get
 * zero-based addressing of words and dots within words.
 */
static void ht1632_senddata (byte d, byte address, byte data)
{
  ht1632_chipselect(ht1632_cs[d]);      // Select chip
  ht1632_writebits(HT1632_ID_WR, 1<<2); // Send ID: WRITE to RAM
  ht1632_writebits(address, 1<<6);      // Send address
  ht1632_writebits(data, 1<<3);         // Send 4 bits of data
  ht1632_chipfree(ht1632_cs[d]);        // Done.
}


/*
 * ht1632_setup
 * setup the ht1632 chips
 */
void ht1632_setup()
{
  for (byte d=0; d<NUM_DISPLAYS; d++) {
    pinMode(ht1632_cs[d], OUTPUT);

    digitalWrite(ht1632_cs[d], HIGH);  // Unselect (active low)
     
    pinMode(ht1632_wrclk, OUTPUT);
    pinMode(ht1632_data, OUTPUT);
    
    ht1632_sendcmd(d, HT1632_CMD_SYSON);    // System on 
    ht1632_sendcmd(d, HT1632_CMD_LEDON);    // LEDs on 
    ht1632_sendcmd(d, HT1632_CMD_COMS01);   // NMOS Output 24 row x 24 Com mode
    
    for (byte i=0; i<128; i++)
      ht1632_senddata(d, i, 0);  // clear the display!
  }
}


/*
 * we keep a copy of the display controller contents so that we can know which bits are on without having to (slowly) read the device.
 * Note that we only use the low four bits of the shadow ram, since we're shadowing 4-bit memory.  This makes things faster, and we
 * use the other half for a "snapshot" when we want to plot new data based on older data...
 */
byte ht1632_shadowram[NUM_DISPLAYS * 96];  // our copy of the display's RAM


/*
 * plot a point on the display, with the upper left hand corner being (0,0).
 * Note that Y increases going "downward" in contrast with most mathematical coordiate systems, but in common with many displays
 * No error checking; bad things may happen if arguments are out of bounds!  (The ASSERTS compile to nothing by default
 */
void ht1632_plot (char x, char y, char val)
{

  char addr, bitval;

  ASSERT(x >= 0);
  ASSERT(x <= X_MAX);
  ASSERT(y >= 0);
  ASSERT(y <= y_MAX);

  byte d;
  //select display depending on plot values passed in
  if (x >= 0 && x <=23 ) {
    d = 0;
  }  
  if (x >=24 && x <=47) {
    d = 1;
    x = x-24; 
  }   

  /*
   * The 4 bits in a single memory word go DOWN, with the LSB (first transmitted) bit being on top.  However, writebits()
   * sends the MSB first, so we have to do a sort of bit-reversal somewhere.  Here, this is done by shifting the single bit in
   * the opposite direction from what you might expect.
   */

  bitval = 8>>(y&3);  // compute which bit will need set

  addr = (x<<2) + (y>>2);  // compute which memory word this is in 

  if (val) {  // Modify the shadow memory
    ht1632_shadowram[(d * 96)  + addr] |= bitval;
  } 
  else {
    ht1632_shadowram[(d * 96) + addr] &= ~bitval;
  }
  // Now copy the new memory value to the display
  ht1632_senddata(d, addr, ht1632_shadowram[(d * 96) + addr]);
}


/*
 * get_shadowram
 * return the value of a pixel from the shadow ram.
 */
byte get_shadowram(byte x, byte y)
{
  byte addr, bitval, d;

  //select display depending on plot values passed in
  if (x >= 0 && x <=23 ) {
    d = 0;
  }  
  if (x >=24 && x <=47) {
    d = 1;
    x = x-24; 
  }  

  bitval = 8>>(y&3);  // compute which bit will need set
  addr = (x<<2) + (y>>2);       // compute which memory word this is in 
  return (0 != (ht1632_shadowram[(d * 96) + addr] & bitval));
}


/*
 * snapshot_shadowram
 * Copy the shadow ram into the snapshot ram (the upper bits)
 * This gives us a separate copy so we can plot new data while
 * still having a copy of the old data.  snapshotram is NOT
 * updated by the plot functions (except "clear")
 */
void snapshot_shadowram()
{
  for (byte i=0; i< sizeof ht1632_shadowram; i++) {
    ht1632_shadowram[i] = (ht1632_shadowram[i] & 0x0F) | ht1632_shadowram[i] << 4;  // Use the upper bits
  }

}

/*
 * get_snapshotram
 * get a pixel value from the snapshot ram (instead of
 * the actual displayed (shadow) memory
 */
byte get_snapshotram(byte x, byte y)
{

  byte addr, bitval;
  byte d = 0;

  //select display depending on plot values passed in 
  if (x >=24 && x <=47) {
    d = 1;
    x = x-24; 
  }  

  bitval = 128>>(y&3);  // user upper bits!
  addr = (x<<2) + (y>>2);   // compute which memory word this is in 
  if (ht1632_shadowram[(d * 96) + addr] & bitval)
    return 1;
  return 0;
}


/*
 * ht1632_clear
 * clear the display, and the shadow memory, and the snapshot
 * memory.  This uses the "write multiple words" capability of
 * the chipset by writing all 96 words of memory without raising
 * the chipselect signal.
 */
void ht1632_clear()
{
  char i;
  for(byte d=0; d<NUM_DISPLAYS; d++)
  {
    ht1632_chipselect(ht1632_cs[d]);  // Select chip
    ht1632_writebits(HT1632_ID_WR, 1<<2);  // send ID: WRITE to RAM
    ht1632_writebits(0, 1<<6); // Send address
    for (i = 0; i < 96/2; i++) // Clear entire display
      ht1632_writebits(0, 1<<7); // send 8 bits of data
    ht1632_chipfree(ht1632_cs[d]); // done
    for (i=0; i < 96; i++)
      ht1632_shadowram[96*d + i] = 0;
  }
}


/* ht1632_putchar
 * Copy a 5x7 character glyph from the myfont data structure to display memory, with its upper left at the given coordinate
 * This is unoptimized and simply uses plot() to draw each dot.
 */
void ht1632_putchar(byte x, byte y, char c)
{
  byte dots;
  if (c >= 'A' && c <= 'Z' || (c >= 'a' && c <= 'z') ) {
    c &= 0x1F;   // A-Z maps to 1-26
  } 
  else if (c >= '0' && c <= '9') {
    c = (c - '0') + 32;
  } 
  else if (c == ' ') {
    c = 0; // space
  }
  else if (c == '.') {
    c = 27; // full stop
  }
  else if (c == '\'') {
    c = 28; // single quote mark
  }  
  else if (c == ':') {
    c = 29; // news_mode selector arrow
  }
  else if (c == '>') {
    c = 30; // news_mode selector arrow
  }
  else if (c == '-') {
    c = 31; // news_mode selector arrow
  }

  for (char col=0; col< 5; col++) {
    dots = pgm_read_byte_near(&myfont[c][col]);
    for (char row=0; row < 7; row++) {
      if (dots & (64>>row))   	     // only 7 rows.
        plot(x+col, y+row, 1);
      else 
        plot(x+col, y+row, 0);
    }
  }
}


/* ht1632_putbigchar
 * Copy a 10x14 character glyph from the myfont data structure to display memory, with its upper left at the given coordinate
 * This is unoptimized and simply uses plot() to draw each dot.
 */
void ht1632_putbigchar(byte x, byte y, char c)
{
  byte dots;
  if (c >= 'A' && c <= 'Z' || (c >= 'a' && c <= 'z') ) {
    return;   //return, as the 10x14 font contains only numeric characters 
  } 
  if (c >= '0' && c <= '9') {
    c = (c - '0');
    c &= 0x1F;
  } 

  for (char col=0; col< 10; col++) {
    dots = pgm_read_byte_near(&mybigfont[c][col]);
    for (char row=0; row < 8; row++) {
      if (dots & (128>>row))   	   
        plot(x+col, y+row, 1);
      else 
        plot(x+col, y+row, 0);
    }

    dots = pgm_read_byte_near(&mybigfont[c][col+10]);
    for (char row=0; row < 8; row++) {
      if (dots & (128>>row))   	   
        plot(x+col, y+row+8, 1);
      else 
        plot(x+col, y+row+8, 0);
    } 
  }  
}


/* ht1632_puttinychar
 * Copy a 3x5 character glyph from the myfont data structure to display memory, with its upper left at the given coordinate
 * This is unoptimized and simply uses plot() to draw each dot.
 */
void ht1632_puttinychar(byte x, byte y, char c)
{
  byte dots;
  if (c >= 'A' && c <= 'Z' || (c >= 'a' && c <= 'z') ) {
    c &= 0x1F;   // A-Z maps to 1-26
  } 
  else if (c >= '0' && c <= '9') {
    c = (c - '0') + 31;
  } 
  else if (c == ' ') {
    c = 0; // space
  }
  else if (c == '.') {
    c = 27; // full stop
  }
  else if (c == '\'') {
    c = 28; // single quote mark
  } else if (c == '!') {
    c = 29; // single quote mark
  }  else if (c == '?') {
    c = 30; // single quote mark
  }

  for (char col=0; col< 3; col++) {
    dots = pgm_read_byte_near(&mytinyfont[c][col]);
    for (char row=0; row < 5; row++) {
      if (dots & (16>>row))   	   
        plot(x+col, y+row, 1);
      else 
        plot(x+col, y+row, 0);
    }
  }  
}



 
/*
 * flashing_cursor
 * print a flashing_cursor at xpos, ypos and flash it repeats times 
 */
void flashing_cursor(byte xpos, byte ypos, byte cursor_width, byte cursor_height, byte repeats)
{
  for (byte r = 0; r <= repeats; r++) {    
    for (byte x = 0; x <= cursor_width; x++) {
      for (byte y = 0; y <= cursor_height; y++) {
        plot(x+xpos, y+ypos, 1);
      }
    }
    
    if (repeats > 0) {
      delay(400);
    } else {
      delay(70);
    }
        
    for (byte x = 0; x <= cursor_width; x++) {
      for (byte y = 0; y <= cursor_height; y++) {
        plot(x+xpos, y+ypos, 0);
      }
    }   
    //if cursor set to repeat, wait a while
    if (repeats > 0) {
     delay(400); 
    }
  }
}


/*
 * fade_down
 * fade the display to black
 */
void fade_down() {
  char intensity;
  for (intensity=14; intensity >= 0; intensity--) {
    ht1632_sendcmd(0, HT1632_CMD_PWM + intensity); //send intensity commands using CS0 for display 0
    ht1632_sendcmd(1, HT1632_CMD_PWM + intensity); //send intensity commands using CS0 for display 1
    delay(FADEDELAY);
  }
  //clear the display and set it to full brightness again so we're ready to plot new stuff
  cls();
  ht1632_sendcmd(0, HT1632_CMD_PWM + 15);
  ht1632_sendcmd(1, HT1632_CMD_PWM + 15);
}


/*
 * fade_up
 * fade the display up to full brightness
 */
void fade_up() {
  char intensity;
  for ( intensity=0; intensity < 15; intensity++) {
    ht1632_sendcmd(0, HT1632_CMD_PWM + intensity); //send intensity commands using CS0 for display 0
    ht1632_sendcmd(1, HT1632_CMD_PWM + intensity); //send intensity commands using CS0 for display 1
    delay(FADEDELAY);
  }
}


/*
 * button_delay
 * like regular delay but can be quit by a button press
 */
void button_delay(int wait) {
  int i = 0;
  while ( i < wait){
    //check if a button is pressed, if it is, quit waiting
    if(buttonA.uniquePress()) {
      return;
      }
      //else wait a moment
      delay (1);
      i++;
  }
}


//display software version number
void printver(){
  char line1[] = "NEWS";
  char line2[] = "MONITOR";
  char ver[] = CURRENT_VERSION;
  cls();

  int i = 0;
  while (line1[i]) {
    ht1632_putchar(i*6, 0, line1[i]);
    i++;
  }
  i = 0;
  while (line2[i]) {
    ht1632_putchar(i*6, 8, line2[i]);
    i++;
  }
  delay(1000);
  i = 0;
  while (ver[i]) {
    flashing_cursor((i*6)+5*6,0,5,7,0);
    ht1632_putchar((i*6)+5*6, 0, ver[i]);
    i++;
  }
  delay(1500);
  
  fade_down();
}



//print menu to change the mode
void switch_mode() {
  char* modes[] = {"NEWS", "TEST", "DEMO", "SETUP" };
  
  byte next_news_mode;
  byte firstrun = 1;
  
  //loop waiting for button (timeout after X loops to return to mode X)
  for(int count=0; count< 40 ; count++) {
     
    //if user hits button, change the news_mode
    if(buttonA.uniquePress() || firstrun == 1){
      
      count = 0;
      cls();
        
      if (firstrun == 0) { news_mode++; } 
      if (news_mode >= MAX_MODE) { news_mode = 0; }
       
      //print arrown and current news_mode name on line one and print next news_mode name on line two
      char str_top[9];
      char str_bot[9];
      
      strcpy (str_top, ">");
      strcat (str_top, modes[news_mode]);
  
      next_news_mode = news_mode + 1;
      if (next_news_mode >= MAX_MODE) { next_news_mode = 0; }
  
      strcpy (str_bot, " ");
      strcat (str_bot, modes[next_news_mode]);
  
      byte i = 0;
      while(str_top[i]) {
        ht1632_putchar(i*6, 0, str_top[i]); 
        i++;
      }
  
      i = 0;
      while(str_bot[i]) {
        ht1632_putchar(i*6, 8, str_bot[i]); 
        i++;
      }
      firstrun = 0;
    }
    delay(50); 
  }

}



byte set_value(byte message, byte current_value, byte reset_value, byte rollover_limit){
  
  cls();
  char messages[3][17]   = {"MAX CRIT", "SV START", "SV END"};
   
  //Print "set xyz" top line
  byte i = 0;
  while(messages[message][i])
  {
    ht1632_putchar(i*6 , 0, messages[message][i]); 
    i++;
  }
  
  //print digits bottom line
  char buffer[5];
  for (i = 0; i <  3; ht1632_putchar(i++ * 6, 8, ' '));
  itoa(current_value,buffer,10);
  for (i = 0; buffer[i]; ht1632_putchar((i * 6), 8, buffer[i++]));

  if (message == 1 || message == 2) {     // If we're adjusting the Servo Start or End then move the arm so we can see the change
     myservo.write(current_value);
  }
 
  delay(300);
  //wait for button input
  while (!buttonA.uniquePress()) {
    
     while (buttonB.isPressed()){
        
       if(current_value < rollover_limit) { 
         current_value++;
       } else {
         current_value = reset_value;
       }
       //print the new value
       for (i = 0; i <  3; ht1632_putchar(i++ * 6, 8, ' '));
       itoa(current_value, buffer ,10);
       for (i = 0; buffer[i]; ht1632_putchar((i * 6), 8, buffer[i++]));

       if (message == 1 || message == 2) {     // If we're adjusting the Servo Start or End then move the arm so we can see the change
         myservo.write(current_value);
       }
       
       delay(150);
     }
  }
  return current_value;
}

