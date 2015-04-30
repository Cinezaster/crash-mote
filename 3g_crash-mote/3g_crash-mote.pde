/*  
 *  ------  3G crash mote  -------- 
 *  
 *  Explanation: This sketch sends data of the car to a server.
 *  It collects data of the CAN-bus, acceleromerter, GPS and 6 channels  
 *
 *  Copyright (C) 2015 Toon Nelissen 
 *  
 *  Version:           0.1
 *  Programmed:        Toon Nelissen 
 */

#include <Wasp3G.h>
#include <WaspPWR.h>
#include <WaspFrame.h>
#include <WaspCAN.h>

char apn[] = "m2m.be";
char login[] = "";
char password[] = "";

int8_t answer;

int8_t state = 0;

int GPS_status = 0;
int8_t gpsState = -1;
unsigned long GPSLast;
unsigned long GPSCheckLast;

bool timeNotSet = true;

int16_t ACCStore[6];
int16_t CANStore[2];
unsigned long ACCLast;

unsigned long CANLast;
unsigned long RPMLast;

unsigned long DEVICELast;

uint8_t TCPsendStatus = 1;

void activate3G()
{
  //activates the _3G module:
  answer = _3G.ON(); 
  if ((answer == 1) || (answer == -3))
  {
    state = 1;
    USB.println(F("_3G module ready..."));
  }
  else
  {
    USB.println(F("_3G module not ready"));
  }
}

void connectToNetwork()
{
  //waits for connection to the network:
  answer = _3G.check(90);    
  if (answer == 1)
  {
    USB.println(F("_3G module connected to the network..."));
    state = 2;
  }
  else
  {
    USB.println(F("_3G module cannot connect to the network"));
    delay(1000);    
  }
}

void configureConnection()
{
  //configures IP connection
  USB.print(F("Setting connection..."));
  answer = _3G.configureTCP_UDP();
  if (answer == 1)
  {
    state = 5;
    USB.println(F("Done"));
    USB.print(F("Configuration success. IP address: ")); 
    USB.println(_3G.buffer_3G);     
  }
  else if (answer < -14)
  {
    USB.print(F("Configuration failed. Error code: "));
    USB.println(answer, DEC);
    USB.print(F("CME error code: "));
    USB.println(_3G.CME_CMS_code, DEC);
  }
  else 
  {
    USB.print(F("Configuration failed. Error code: "));
    USB.println(answer, DEC);
  }
}

void TCPConnect ()
{
  USB.print(F("Opening TCP socket..."));        
  answer = _3G.createSocket(TCP_CLIENT, "88.80.184.131",3102);
  if (answer == 1)
  {
    state = 6;
    USB.println(F("Connected"));
  }
  else if (answer == -2)
  {
    USB.print(F("Connection failed. Error code: "));
    USB.println(answer, DEC);
    USB.print(F("CME error code: "));
    USB.println(_3G.CME_CMS_code, DEC);
    delay(1000);
  }
  else 
  {
    USB.print(F("Connection failed. Error code: "));
    USB.println(answer, DEC);
    delay(1000);
  }
}

void closeTCPConnection () {
  USB.print(F("Closing TCP socket..."));  
  // 10. closes socket
  if (_3G.closeSocket() == 1) // Closes socket
  {
      USB.println(F("Done"));
  }
  else
  {
      USB.println(F("Fail"));
  }
}

void sendData (const char* buff) 
{
  if(state > 3 && TCPsendStatus == 1){
    USB.print(F("Sending a Package..."));
    TCPsendStatus = 3; 
    TCPsendStatus = _3G.sendData(buff);
  } 
  else if (state > 3)
  {
    USB.print(F("Previous Package was not send nore this one"));
    // what is the state??
    switch (TCPsendStatus) {
        case 0:
          USB.print(F("Waiting for error"));
          break;
        case -2:
          USB.print(F("error with CME"));
          break;
        case -3:
          USB.print(F("error with no feedback"));
          break;
        case -4:
          USB.print(F("Sending data Failed"));
          break;
        default:
          USB.print(F("TCPsendStatus code is: "));
          USB.print(TCPsendStatus);
    }
    USB.println(F(""));
  }
}

void startGPS () 
{
  USB.print(F("Starting GPS..."));
  GPS_status = _3G.startGPS(2, "supl.google.com", "7276");
  if (GPS_status == 1)
  { 
    USB.println(F(""));
    USB.println(F("**************************"));
    USB.println(F("GPS ON"));
    USB.println(F("**************************"));
    state = 3;
  }
  else
  {
    USB.println(F("Failed"));   
  }
}

void sendPosition (int sendInterval)
{
  if(millis() > GPSLast + sendInterval){
    if(_3G.getGPSinfo()){
      if(timeNotSet)
      {
        if (_3G.setTimebyGPS(20,1)){
          timeNotSet = false;
        } 
        else 
        {
          USB.println(F("RTC NOT SET"));
        }
      }

      RTC.setMode(RTC_ON,RTC_NORMAL_MODE);

      char posData[150];
      snprintf(posData,sizeof(posData),"{\"g\":{\"la\":%s,\"lo\":%s,\"s\":%s},\"t\":%lu}",
        _3G.convert2Degrees(_3G.latitude),
        _3G.convert2Degrees(_3G.longitude),
        _3G.speedOG,
        RTC.getEpochTime()
      );

      RTC.setMode(RTC_OFF,RTC_NORMAL_MODE);
      sendData(posData);
      USB.println(F("GPS"));
      GPSLast = millis();
    }
    else
    {
      USB.println(F("GPS not fixed"));
    }
  }
}

/* Accelerometer */
void activateACC () 
{
  USB.println(F(""));
  USB.println(F("**************************"));
  USB.println(F("ACC ON"));
  USB.println(F("8G mode"));
  USB.println(F("50Hz"));
  USB.println(F("**************************"));
  ACC.ON(FS_8G);
  ACCLast = millis();
}

void measureMovement()
{
  if(ACC.isON){
    int x_acc = ACC.getX();
    int y_acc = ACC.getY();
    int z_acc = ACC.getZ();
    if(x_acc < ACCStore[0]){
      ACCStore[0] = x_acc;
    }
    if(x_acc > ACCStore[1]){
      ACCStore[1] = x_acc;
    }
    if(y_acc < ACCStore[2]){
      ACCStore[2] = y_acc;
    }
    if(y_acc > ACCStore[3]){
      ACCStore[3] = y_acc;
    }
    if(z_acc < ACCStore[4]){
      ACCStore[4] = z_acc;
    }
    if(z_acc > ACCStore[5]){
      ACCStore[5] = z_acc;
    }
  }
}

void sendMovement(int sendInterval)
{
  measureMovement();
  if(ACC.isON && millis() > ACCLast + sendInterval && ACCStore[0] != 8000){
    if(ACC.check() == 0x32){
      RTC.setMode(RTC_ON,RTC_NORMAL_MODE);

      char movData[150];
      snprintf(movData,sizeof(movData),"{\"a\":{\"d\":[%i,%i],\"s\":[%i,%i],\"a\":[%i,%i]},\"t\":%lu}",
        ACCStore[0],
        ACCStore[1],
        ACCStore[2],
        ACCStore[3],
        ACCStore[4],
        ACCStore[5],
        RTC.getEpochTime()
      );
      sendData(movData);
      USB.println(F("ACC"));
      cleanACCStore();
      ACCLast = millis();
      RTC.setMode(RTC_OFF,RTC_NORMAL_MODE);
    }
    else
    {
      USB.println(F("ACC sensor Wrong"));
      ACC.boot();
      ACCLast = ACCLast + 20000;
    }
  } 
}

void cleanACCStore () 
{
  for(int i=0; i<6; i++){
    if ( (i & 0x01) == 0) {
      ACCStore[i] = 8000;
    } else {
      ACCStore[i] = -8000;
    }  
  }
}

/* CAN-bus */
void activateCAN () 
{
  CANI.ON(500);
  CANLast = millis();
  RPMLast = millis();
}

void measureCAN() 
{
  if(millis() > RPMLast+400){
      int engineRPM = CANI.getEngineRPM();
    // Get the throttle position
    int throttlePosition = CANI.getThrottlePosition();
    if(engineRPM > CANStore[0]){
        CANStore[0] = engineRPM;
    }
    if(engineRPM < CANStore[1]){
        CANStore[1] = engineRPM;
    }
    RPMLast = millis();
  }
}

void sendCAN () 
{
  if(millis() > (CANLast + 2000) && CANStore[0] > -1){
    int fuelLevel = CANI.getFuelLevel();
    int engineTemp = CANI.getEngineCoolantTemp();
    char CANData[150];
    snprintf(CANData,sizeof(CANData),"{\"e\":{\"r\":[%i,%i],\"t\":%i,\"f\":%i},\"t\":%lu}",
      CANStore[0],
      CANStore[1],
      engineTemp,
      fuelLevel,
      RTC.getEpochTime()
    );
    USB.println(CANData);
    cleanCANStore();
    CANLast = millis();
  }
}

void cleanCANStore ()
{
  for(int i=0; i<2; i++){
    if ( (i & 0x01) == 0) {
      CANStore[i] = -1;
    } else {
      CANStore[i] = 10000;
    }  
  }
}

/* Device */
void sendDevice (unsigned long sendInterval) {
  if(millis() > DEVICELast + sendInterval){
    
    RTC.setMode(RTC_ON,RTC_NORMAL_MODE);

    uint8_t BattLevel = PWR.getBatteryLevel();

    float BattVolt = PWR.getBatteryVolts();
    char BattVoltStr[10];
    dtostrf( BattVolt, 2, 4, BattVoltStr );

    float DeviceTemp = RTC.getTemperature();
    char DeviceTempStr[5];
    dtostrf(DeviceTemp,3,1, DeviceTempStr);

    char DEVICEData[200];
    snprintf(DEVICEData,sizeof(DEVICEData),"{\"d\":{\"b\":%i,\"p\":%s,\"t\":%s},\"t\":%lu}",
      BattLevel,
      BattVoltStr,
      DeviceTempStr,
      RTC.getEpochTime()
    );
    sendData(DEVICEData);
    USB.println(F("DEVICE"));
    DEVICELast = millis();

    RTC.setMode(RTC_OFF,RTC_NORMAL_MODE);
  }
}

void setup()
{   
    RTC.ON();
    // setup for Serial port over USB:
    USB.ON();
    USB.println(F("**************************"));
    USB.println(F("USB port started..."));
    USB.println(F("**************************"));
    USB.print(F("Battery Level ==> "));
    USB.println(PWR.getBatteryLevel(),DEC);
    USB.println(F("**************************"));
    USB.print(F("Date & Time ==> "));
    USB.println(RTC.getTime());
    USB.println(F("**************************"));
    RTC.setMode(RTC_OFF,RTC_NORMAL_MODE);
    // 1. sets operator parameters
    _3G.set_APN(apn, login, password);
    // And shows them
    _3G.show_APN();
    USB.println(F("**************************"));

    DEVICELast = millis();
    cleanACCStore();
    cleanCANStore();
}

void loop()
{
  switch (state) {
      case 0:
      activate3G();
      break;
    case 1:
      connectToNetwork();
      break;
    case 2:
      startGPS();
      break;
    case 3:
      state = 4;
      break;
    case 4:
      configureConnection();
      break;
    case 5:
      TCPConnect();
      break;
    case 6:
      activateACC();
      state = 7;
      break;
    case 7:
      sendPosition(3000);
      sendDevice(60000);
      sendMovement(3000);
  }
}

