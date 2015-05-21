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


char apn[] = "web.be";
char login[] = "web";
char password[] = "web";


int8_t answer;

int8_t state = 0;

unsigned long DEVICELast;

uint8_t TCPsendStatus = 1;

void activate3G()
{
  //activates the _3G module:
  answer = _3G.ON(); 
  if ((answer == 1) || (answer == -3))
  {
    state = 1;
    if (_3G.setPIN("1111")) 
    {
      USB.println(F("_3G module ready..."));
    }
    else
    {
      USB.println(F("PIN not set"));
    }
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

void showNetWorkInfo()
{
  USB.print(F("Network Mode: "));
  switch (_3G.showsNetworkMode()) {
    case -1:
      USB.print(F("CME error code: "));
      USB.println(_3G.CME_CMS_code, DEC);
      break;
    case 0:
      USB.println(F("Error"));
      break;
    case 1:
      USB.println(F("No Service"));
      break;
    case 2:
      USB.println(F("GSM"));
      break;
    case 3:
      USB.println(F("GPRS"));
      break;
    case 4:
      USB.println(F("EGPRS (EDGE)"));
      break;
    case 5:
      USB.println(F("WCDMA"));
      break;
    case 6:
      USB.println(F("HSDPA only"));
      break;
    case 7:
      USB.println(F("HSUPA only"));
      break;
    case 8:
      USB.println(F("HSPA (HSDPA and HSUPA)"));
      break;
  }

  answer = _3G.getRSSI();
  if (answer != 1)
  {
      USB.print(F("Received signal strength indication: "));
      USB.print(answer,DEC);
      USB.println(F("dBm"));
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
    USB.println(F("Configuration success. "));
    if (_3G.getIP() == 1) {
      USB.print(F("IP address: ")); 
      USB.println(_3G.buffer_3G);
    } 
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
    MQTT_Connect();
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
          USB.println(_3G.CME_CMS_code, DEC);
          if(_3G.CME_CMS_code == 0) {
            // disconnect
          }
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

boolean sendData(uint8_t *buf, uint16_t size) {
  int8_t answer;

  answer = _3G.sendData(buf, size);
  if(answer == 1){
    return true;
  }
  else if(answer == 0) {
    USB.println(F("> Error Occurred on Sending Data."));
    //return false;
  }
  else if((answer == -2) || (answer == -3)) {
    USB.print(F("> Sending Data Fail. Error code: \t"));
    USB.println(answer, DEC);
    USB.print(F("> CME or IP error code: \t\t"));
    USB.println(_3G.CME_CMS_code, DEC);
    if(_3G.CME_CMS_code == 0) {
      stop();
    }
    //return false;
  }
  else {
    USB.print(F("> Unexpected error with code: \t"));
    USB.println(answer);
    stop();
  }
  return false;
}

/* Device */
void sendDevice (unsigned long sendInterval) {
  if(millis() > DEVICELast + sendInterval){
    showNetWorkInfo();

    uint8_t BattLevel = PWR.getBatteryLevel();

    float BattVolt = PWR.getBatteryVolts();
    char BattVoltStr[10];
    dtostrf( BattVolt, 2, 4, BattVoltStr );

    float DeviceTemp = RTC.getTemperature();
    char DeviceTempStr[5];
    dtostrf(DeviceTemp,3,1, DeviceTempStr);

    RTC.setMode(RTC_ON,RTC_NORMAL_MODE);;

    char DEVICEData[200];
    snprintf(DEVICEData,sizeof(DEVICEData),"{\"d\":{\"b\":%i,\"p\":%s,\"t\":%s},\"t\":%lu}",
      BattLevel,
      BattVoltStr,
      DeviceTempStr,
      RTC.getEpochTime()
    );

    RTC.setMode(RTC_OFF,RTC_NORMAL_MODE);;

    sendData(DEVICEData);
    USB.println(F("DEVICE"));
    DEVICELast = millis();
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
    case 3:
    case 4:
      configureConnection();
      break;
    case 5:
      TCPConnect();
      break;
    case 6:
    case 7:
      sendDevice(6000);
  }
}

