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

  components MainC, GroupProjectC as App;
  components LocalTimeMilliC;
  
  // radio stuff
  components CC2420TimeSyncMessageC as Radio;
  components new AMSenderC(AM_GROUP_PROJECT_MSG);
  components new AMReceiverC(AM_GROUP_PROJECT_MSG);
  components new AMSenderC(AM_ACK) as AMSenderCAck;
  components new AMReceiverC(AM_ACK) as AMReceiverCAck;
  components new TimerMilliC() as TimerSendC;
  components new TimerMilliC() as TimerSendAckC;
  components new TimerMilliC() as TimerSerialC;
  components new TimerMilliC() as TimeSyncTimerC;
  components new TimerMilliC() as TimeSyncLaunchC;
  components new TimerMilliC() as TimeSyncSlotsC;
  
  // serial port
  components PrintfC, SerialStartC;
  //components SerialPrintfC;
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
  components LedsC;
  App.Leds -> LedsC;
    
  App.Notify -> DataGeneratorC;
  App.Cache -> GroupProjectCacheC;
  App.Pool -> PoolC;
  App.Queue -> QueueC;
  App.Random -> RandomC;
  
  App.Boot -> MainC.Boot;
  
  App.RadioReceive -> AMReceiverC;
  App.RadioSend -> AMSenderC;
  App.RadioAckReceive -> AMReceiverCAck;
  App.RadioAckSend -> AMSenderCAck;
  App.RadioControl -> Radio;
  App.RadioPacket -> AMSenderC;
  App.RadioPacketInfo -> AMSenderC;
  App.RadioTimeSyncReceive -> Radio.Receive[AM_SYNC];
  App.RadioTimeSyncSend -> Radio.TimeSyncAMSendMilli[AM_SYNC];
  App.RadioTimeSyncPacket -> Radio.TimeSyncPacketMilli;

  App.SerialSend -> SerialAMSenderC;
  App.TimerSend -> TimerSendC;
  App.TimerSendAck -> TimerSendAckC;
  App.TimerSerial -> TimerSerialC;
  App.LocalTime -> LocalTimeMilliC;
  App.TimeSyncTimer -> TimeSyncTimerC;
  App.TimeSyncLaunch -> TimeSyncLaunchC;
  App.TimeSyncSlots -> TimeSyncSlotsC;
}
