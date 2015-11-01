#include "printf.h"
#include "GroupProject.h"

/**
 * This is the skeleton app for the group project of the Low-Power Systems Design course.
 * 
 * A data generation component (DataGeneratorC) signals data events at a fixed interval. The data rate 
 * can be configured at compile by defining the constant DATARATE, e.g. "-DDATARATE=10" for 10 packets
 * per second.
 * The skeleton app broadcasts one packet for every generated event. On receive, every node forwards
 * packet that it has not seen yet. This forwarding concept, called flooding, propagates the packets in
 * the whole network. A sink node prints out the received packets.
 */

configuration GroupProjectAppC {}
implementation {

  components MainC, GroupProjectC as App, LedsC;
  
  // radio stuff
  components ActiveMessageC;
  components new AMSenderC(AM_GROUP_PROJECT_MSG);
  components new AMReceiverC(AM_GROUP_PROJECT_MSG);
  components new TimerMilliC();
  
  // serial port
  components PrintfC, SerialStartC;
  components new SerialAMSenderC(AM_GROUP_PROJECT_MSG);

  // data generation and forwarding logic
  components DataGeneratorC;
  components new PoolC(message_t, MSG_POOL_SIZE);
  components new QueueC(message_t *, MSG_POOL_SIZE);
  components new GroupProjectCacheC(20);
  components RandomC;
  
  // FlockLab
#ifndef COOJA
  components Msp430DcoCalibC;
  App.ClockCalibControl -> Msp430DcoCalibC;
#endif
    
  App.Notify -> DataGeneratorC;
  App.Cache -> GroupProjectCacheC;
  App.Pool -> PoolC;
  App.Queue -> QueueC;
  App.Random -> RandomC;
  
  App.Boot -> MainC.Boot;
  
  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.AMControl -> ActiveMessageC;
  App.Packet -> AMSenderC;

  App.SerialSend -> SerialAMSenderC;
  App.Leds -> LedsC;
  App.MilliTimer -> TimerMilliC;
  
}
