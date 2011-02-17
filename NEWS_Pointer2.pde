// NEWS Status Monitor

#include <SPI.h>
#include <Ethernet.h>
#include <Servo.h> 
 
Servo myservo;  // create servo object to control a servo 
 
int armPosition; // Where the Servo Arm will point 
int greenLED = 7;
int redLED = 8;

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

unsigned long secondsDelay = 30;  //polling interval
int c = 0;

void setup() {
  Serial.begin(9600);
  Ethernet.begin(mac, ip);
  delay(1000);

  myservo.attach(9);
  pinMode(redLED, OUTPUT);
  pinMode(greenLED, OUTPUT);
  digitalWrite(redLED, LOW);
  digitalWrite(greenLED, HIGH);
  
  armPosition = 90;
  myservo.write(armPosition);
}

void loop() {
     if (client.connect()) {
        client.print("GET /just_critical.php");
        client.println();
        delay(1000);
     }
     else
       Serial.println("Connection failed.");
    do {
     if (client.available()) {
      Serial.println("Reading data from server...");
      c = client.read();
      client.flush();
    }
    } while ( client.connected() );
    if (!client.connected()) {
      client.stop();
    } 


    if (c > 11) {
      c = 11;
    }

    Serial.println("Moving the Arm");
    
    armPosition = map(c, 0, 11, 0, 179);
    myservo.write(armPosition);

    if (c == 0) {
      digitalWrite(redLED, LOW);
      digitalWrite(greenLED, HIGH);
    } else {
      digitalWrite(redLED, HIGH);
      digitalWrite(greenLED, LOW);
    }

     Serial.println(c); 
  
   delay(secondsDelay * 1000);
}
