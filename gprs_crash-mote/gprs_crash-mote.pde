/*  
 *  ------  GPRS908 crash mote  -------- 
 *  
 *  Explanation: This sketch sends data of the car to a server.
 *  It collects data of the CAN-bus, acceleromerter, GPS and 6 channels  
 *
 *  Copyright (C) 2015 Toon Nelissen 
 *  
 *  Version:           0.1
 *  Programmed:        Toon Nelissen 
 */
#include "WaspGPRS_SIM908.h"
#include <WaspPWR.h>
#include <WaspFrame.h>

char apn[] = "m2m.be";
char login[] = "";
char password[] = "";

char ip[] = "88.80.184.131";
char port[] = "3102";

int8_t answer;

int8_t state = 0;

int8_t GPS_status = 0;
int8_t gpsState = -1;
unsigned long GPSLast = millis();
unsigned long GPSCheckLast = millis();

bool timeNotSet = true;

int16_t ACCStore[6];

unsigned long ACCLast = millis();
unsigned long RPMLast = millis();
unsigned long DEVICELast = millis();

uint8_t TCPsendStatus = 1;

void activateGPRS()
{
  //activates the GPRS_SIM908 module:
  answer = GPRS_SIM908.ON(); 
  if ((answer == 1) || (answer == -3))
  {
    state = 1;
    USB.println(F("GPRS ready"));
    USB.println(F("********************************"));
  }
  else
  {
    USB.println(F("GPRS_SIM908 module not ready"));
  }
}

void connectToNetwork()
{
  //waits for connection to the network:
  answer = GPRS_SIM908.check(180);    
  if (answer == 1)
  {
    USB.println(F("GPRS connected to the network"));
    USB.println(F("********************************"));
    state = 2;
  }
  else
  {
    USB.println(F("GPRS_SIM908 module cannot connect to the network"));
    delay(1000);    
  }
}

void configureConnection()
{
  //configures IP connection
  USB.print(F("Setting connection..."));
  answer = GPRS_SIM908.configureGPRS_TCP_UDP(MULTI_CONNECTION);
  if (answer == 1)
  {
    state = 5;
    USB.println(F("Done"));
    USB.print(F("Configuration success. IP address: ")); 
    USB.println(GPRS_SIM908.IP_dir);     
  }
  else if (answer < -14)
  {
    USB.print(F("Configuration failed. Error code: "));
    USB.println(answer, DEC);
    USB.print(F("CME error code: "));
    USB.println(GPRS_SIM908.CME_CMS_code, DEC);
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
  answer = GPRS_SIM908.createSocket(TCP_CLIENT,1, ip,port );
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
    USB.println(GPRS_SIM908.CME_CMS_code, DEC);
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
  // 9. changes from data mode to command mode:
  GPRS_SIM908.switchtoCommandMode();

  USB.print(F("Closing TCP socket..."));  
  // 10. closes socket
  if (GPRS_SIM908.closeSocket() == 1) // Closes socket
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
    TCPsendStatus = GPRS_SIM908.sendData(buff, 1);
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
  GPS_status = GPRS_SIM908.GPS_ON();
  if (GPS_status == 1)
  { 
    USB.println(F("GPS ON"));
    USB.println(F("********************************"));
    USB.println(F("Waiting for signal..."));
    GPRS_SIM908.waitForGPSSignal();
    USB.println(F("********************************"));
    state = 3;
  }
  else
  {
    USB.println(F("Failed"));   
  }
}

void checkForGPSFix() 
{
  if (millis() > GPSCheckLast + 2000) {
    int status = GPRS_SIM908.checkGPS();
    if ((GPS_status == 1) && (status > 2))
    {
      state = 4;
      GPSLast = millis();
      if(timeNotSet)
      {
        if(GPRS_SIM908.getGPSData(ZDA, 1))
        {
          if (GPRS_SIM908.setRTCTimeFromGPS()){
            
            RTC.setMode(RTC_ON,RTC_NORMAL_MODE);
            USB.println(RTC.getTime());
            RTC.setMode(RTC_OFF,RTC_NORMAL_MODE);
            USB.println(F("********************************"));

            timeNotSet = false;
          } 
          else 
          {
            USB.println(F("RTC NOT SET"));
          }   
        }  
      }
    }
    else if((GPS_status == 1) && (status <= 2))
    {
      USB.println(F("GPS not fixed")); 
    }
    else
    {
      USB.println(F("GPS not started")); 
    }
    GPSCheckLast = millis();
  }
}

void sendPosition (int sendInterval)
{
  if(millis() > GPSLast + sendInterval){
    if(GPRS_SIM908.getGPSData(BASIC, 1)){
      float latitude = GPRS_SIM908.convert2Degrees(GPRS_SIM908.latitude, GPRS_SIM908.NS_indicator);
      char latStr[20];
      dtostrf( latitude, 4, 15, latStr );

      float longitude = GPRS_SIM908.convert2Degrees(GPRS_SIM908.longitude, GPRS_SIM908.EW_indicator);
      char lotStr[20];
      dtostrf( longitude, 4, 15, lotStr );

      float speedOG = GPRS_SIM908.speedOG;
      char speedOGStr[10];
      dtostrf( speedOG, 2, 4, speedOGStr );

      RTC.setMode(RTC_ON,RTC_NORMAL_MODE);

      char posData[150];
      snprintf(posData,sizeof(posData),"{\"g\":{\"la\":%s,\"lo\":%s,\"s\":%s},\"t\":%lu}",
        latStr,
        lotStr,
        speedOGStr,
        RTC.getEpochTime()
      );

      RTC.setMode(RTC_OFF,RTC_NORMAL_MODE);
      sendData(posData);
      USB.println(F("GPS"));
      GPSLast = millis();
    }
  }
}

/* Accelerometer */
void activateACC () 
{
  USB.println(F("********************************"));
  USB.println(F("ACC ON ==> 8G mode, 50Hz"));
  USB.println(F("********************************"));
  ACC.ON(FS_8G);
  //ACC.unset6DPosition();
  //ACC.unset6DMovement();
  //ACC.unsetIWU();
  //ACC.unsetFF();
  //ACC.unSetSleepToWake();
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
      RTC.OFF();
      ACC.OFF();
      Wire.close();
      delay(100);
      RTC.ON();
      activateACC();
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
    
    // setup for Serial port over USB:
    USB.ON();
    USB.println(F("<><><><><><><><><><><><><><><><>"));
    USB.println(F("<><><> CRASH MOTE STARTED <><><>"));
    USB.println(F("<><><><><><><><><><><><><><><><>"));
    USB.println(F(""));
    USB.println(F("********************************"));

    USB.print(F("Battery Level ==> "));
    USB.println(PWR.getBatteryLevel(),DEC);

    USB.println(F("********************************"));

    RTC.ON();
    USB.print(F("Date & Time ==> "));
    USB.println(RTC.getTime());
    RTC.setMode(RTC_OFF,RTC_NORMAL_MODE);
    
    USB.println(F("********************************"));

    GPRS_SIM908.set_APN(apn, login, password);
    USB.print(F("Set APN ==> "));
    USB.println(apn);

    USB.println(F("********************************"));

    cleanACCStore();
}

void loop()
{
  switch (state) {
      case 0:
      activateGPRS();
      break;
    case 1:
      connectToNetwork();
      break;
    case 2:
      startGPS();
      break;
    case 3:
      checkForGPSFix();
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

