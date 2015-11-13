#include "Timer.h"
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
 **/
 
module GroupProjectC @safe() {
  uses {
    // Basic interfaces
    interface Leds;
    interface Boot;
#ifndef COOJA
    interface StdControl as ClockCalibControl;
#endif
    interface Random;
    
    // Interfaces for radio communication
    interface Receive as RadioReceive;
    interface Receive as RadioTimeSyncReceive;
    interface AMSend as RadioSend;
    interface SplitControl as RadioControl;
    interface Packet as RadioPacket;
    interface TimeSyncPacket<TMilli, uint32_t> as RadioTimeSyncPacket;
    interface TimeSyncAMSend<TMilli, uint32_t> as RadioTimeSyncSend;
    
    // Timer
    interface Timer<TMilli> as MilliTimer;
    interface Timer<TMilli> as TimeSyncTimer;
    interface Timer<TMilli> as TimeSyncLaunch;
    interface LocalTime<TMilli> as LocalTime;
    
    // Interfaces for message management
    interface Notify<group_project_msg_t>;
    interface Cache<cache_entry_t>;
    interface Pool<message_t>;
    interface Queue<message_t *>;
    
    // Interfaces for serial output
    interface AMSend as SerialSend;
    
  }
}
implementation {

//#undef debug_printf
#ifdef debug_printf
#warning debug printf enabled
#undef dbg
#define dbg(component, fmt, ...) do {\
  printf(fmt, ##__VA_ARGS__);\
  } while(0);
#else
#warning debug printf not enabled
#endif

  bool locked;
  bool radioOn;
  uint8_t seq_no = 0;
  
  /*
   * Time Synchronization
   */
  message_t sync_packet;
  uint16_t sync_tag;
  uint32_t sync_recvTime;
  uint32_t sync_remaining;
  
  // function prototypes
  error_t enqueue(message_t * m);
  message_t * forward(message_t * fm);
  void message_to_cache_entry(message_t *m, cache_entry_t * c);
  void senddone(message_t* bufPtr, error_t error);
  void startForwardTimer();
  
  enum {
    FORWARD_DELAY_MS = 3, // max wait time between two forwarded packets
    TIMESYNC_DELAY_MS = 3, // delay multiplied by id for TDMA-like flooding
  };
  
  schedule_t schedule[] = { {
    0,    // device id
    1000, // period
    22,  // slotsize
    0,    // recv start
    0,    // recv stop
    0,    // recv ack start
    0,    // recv ack stop
    0,    // send start
    1,    // send stop
    3,    // send ack start
    4,    // send ack stop
  },
  {
    1,    // device id
    1000, // period
    22,  // slotsize
    0,    // recv start
    0,    // recv stop
    0,    // recv ack start
    0,    // recv ack stop
    1,    // send start
    2,    // send stop
    3,    // send ack start
    4,    // send ack stop
  },
  {
    2,    // device id
    1000, // period
    22,  // slotsize
    0,    // recv start
    0,    // recv stop
    0,    // recv ack start
    0,    // recv ack stop
    2,    // send start
    3,    // send stop
    3,    // send ack start
    4,    // send ack stop
  },
  {
    3,    // device id
    1000, // period ms
    22,  // slotsize
    0,    // recv start
    3,    // recv stop
    3,    // recv ack start
    4,    // recv ack stop
    8,    // send start
    9,    // send stop
    10,    // send ack start
    11,    // send ack stop
  },
  };
  
  event void Boot.booted() {
    call RadioControl.start();
#ifndef COOJA
    call ClockCalibControl.start();
#endif
  }
  
  event void RadioControl.startDone(error_t err) {
    if (err == SUCCESS) {
      radioOn=TRUE;
      call Leds.led1On();
      dbg("GroupProjectC", "Radio on, datarate is %u.\n", datarate);
      if(TOS_NODE_ID == SINK_ADDRESS) {
        dbg("GroupProjectC", "Emitting timesync packets.\n");
        call TimeSyncTimer.startPeriodic(5000);
      }
    }
    else {
      call RadioControl.start();
    }
  }
  
  event void RadioControl.stopDone(error_t err) {
    // do nothing
  }
      
  event void MilliTimer.fired() {
    error_t ret;
    
    // sink node prints out data on serial port
    if (TOS_NODE_ID == SINK_ADDRESS) {
      ret = call SerialSend.send(AM_BROADCAST_ADDR, call Queue.head(), sizeof(group_project_msg_t));
    }
    // other nodes forward data over radio
    else {
      ret = call RadioSend.send(AM_BROADCAST_ADDR, call Queue.head(), sizeof(group_project_msg_t));
    }
    if (ret != SUCCESS) {
      startForwardTimer(); // retry in a short while
    }
  }

  event message_t* RadioReceive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    if(len == sizeof(group_project_msg_t)) {
      return forward(bufPtr);
    }
    dbg("RadioReceive", "Received unknown packet in RadioReceive\n");
    return bufPtr;
  }
  
  event message_t* RadioTimeSyncReceive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    timesync_msg_t *tsm;
    uint32_t tnow;
    
    if(TOS_NODE_ID == SINK_ADDRESS) {
      return bufPtr;
    }
    
    if(len == sizeof(timesync_msg_t)) {
      tsm = (timesync_msg_t*)payload;
      if(call RadioTimeSyncPacket.isValid(bufPtr) == FALSE) {
        dbg("RadioTimeSyncReceive", "Invalid Timestamp. Help me! What should I do?\n");
      }
      
      // got a new timesync request?
      if(sync_tag != tsm->tag) {
        sync_tag = tsm->tag;
        sync_recvTime = call RadioTimeSyncPacket.eventTime(bufPtr);
        sync_remaining = tsm->remaining;
        
        tnow = call LocalTime.get();
        
        call TimeSyncLaunch.startOneShot(sync_remaining - (tnow - sync_recvTime));
        
        dbg("RadioTimeSyncReceive", "sync time: %lu, local time: %lu\n", sync_recvTime, tnow);
        
        if(IS_RELAY(TOS_NODE_ID)) {
          call TimeSyncTimer.startOneShot(TIMESYNC_DELAY_MS*TOS_NODE_ID);
          
          if(TIMESYNC_DELAY_MS*TOS_NODE_ID > sync_remaining) {
            dbg("RadioTimeSyncReceive", "Timing violation\n");
          }
        }

      }
      
      return bufPtr;
    }
    dbg("RadioTimeSyncReceive", "Received unknown packet in RadioTimeSyncReceive\n");
    return bufPtr;
  }
  
  event void TimeSyncTimer.fired() {
    timesync_msg_t *tsm;
    error_t ret;
    uint32_t tnow;
    
    if(TOS_NODE_ID == SINK_ADDRESS) {
      tsm = (timesync_msg_t*) call RadioTimeSyncSend.getPayload(&sync_packet, sizeof(timesync_msg_t));
      tsm->tag = ++sync_tag;
      sync_remaining = 1000;
      tsm->remaining = sync_remaining;
      
      call TimeSyncLaunch.startOneShot(sync_remaining);
      ret = call RadioTimeSyncSend.send(AM_BROADCAST_ADDR, &sync_packet, sizeof(timesync_msg_t), call LocalTime.get());
    } else {
      tnow = call LocalTime.get();
      
      tsm = (timesync_msg_t*) call RadioTimeSyncSend.getPayload(&sync_packet, sizeof(timesync_msg_t));
      tsm->tag = sync_tag;
      tsm->remaining = sync_remaining - (tnow - sync_recvTime);
      ret = call RadioTimeSyncSend.send(AM_BROADCAST_ADDR, &sync_packet, sizeof(timesync_msg_t), tnow);
    }
    
    if(ret != SUCCESS) {
      dbg("TimeSyncTimer", "Fail to send\n");
    }
  }
  
  event void TimeSyncLaunch.fired() {
    if(sync_tag & 1) {
      call Leds.led2On();
    } else {
      call Leds.led2Off();
    }
  }

  event void Notify.notify(group_project_msg_t datamsg) {
    /*message_t * m;
    group_project_msg_t* gpm;
    
    call Leds.led0Toggle();
    if (!radioOn) {
      dbg("GroupProjectC", "Notify: Radio not ready.\n");
      return; // radio not ready yet
    } 
    m = call Pool.get();
    if (m == NULL) {
      dbg("GroupProjectC", "Notify: No more message buffers.\n");
      return;
    }
    gpm = (group_project_msg_t*)call RadioPacket.getPayload(m, sizeof(group_project_msg_t));
    *gpm = datamsg;
    // enqueue packet
    enqueue(m);*/
  }
  
  event void RadioSend.sendDone(message_t* bufPtr, error_t error) {
    senddone(bufPtr, error);
  }
  
  event void RadioTimeSyncSend.sendDone(message_t* bufPtr, error_t error) {
    
  }
  
  event void SerialSend.sendDone(message_t* bufPtr, error_t error) {
    senddone(bufPtr, error);
  }
  
  error_t enqueue(message_t * m) {
    cache_entry_t c;
    // add message to queue
    if (call Queue.enqueue(m) == FAIL) {
      dbg("GroupProjectC", "drop(%u,%u).\n", c.source, c.seq_no);
      call Pool.put(m); // return buffer
      return FAIL;
    }
    
    // update cache
    message_to_cache_entry(m, &c);
    call Cache.insert(c);
    
    // if not sending, send first packet from queue
    if (!locked) {
      locked = TRUE;
      startForwardTimer();
    }
    
    dbg("GroupProjectC", "enqueued (%u,%u) p:%u q:%u\n", c.source, c.seq_no, call Pool.size(), call Queue.size());
    return SUCCESS;
  }
  
  message_t * forward(message_t * fm) {
    cache_entry_t c;
    // get spare message buffer
    message_t * m = call Pool.get();
    if (m == NULL) {
      dbg("GroupProjectC", "forward(): no more message buffers.\n");
      return fm; // no space available, return pointer to original message
    }
    
    // check if already forwarded
    message_to_cache_entry(fm, &c);
    if (call Cache.lookup(c)) {
      call Pool.put(m); // return buffer
      return fm;// already forwarded once
    }
    
    // enqueue for forwarding
    enqueue(fm);
    
    // return message buffer for next receive
    return m;
  }
  
  void message_to_cache_entry(message_t *m, cache_entry_t * c) {
    group_project_msg_t* gpm;
    gpm = (group_project_msg_t*)call RadioPacket.getPayload(m, sizeof(group_project_msg_t));
    c->source = gpm->source;
    c->seq_no = gpm->seq_no;
  }
  
  void senddone(message_t* bufPtr, error_t error) {
    if (call Queue.head() == bufPtr) {
      locked = FALSE;
      
      // remove from queue
      call Queue.dequeue();
      
      // return buffer
      call Pool.put(bufPtr);
      
      // send next waiting message
      if (!call Queue.empty() && !locked) {
        locked = TRUE;
        startForwardTimer();
      }
    }
  }
  
  void startForwardTimer() {
    uint16_t delay = call Random.rand16();
    call MilliTimer.startOneShot(1 + delay % (FORWARD_DELAY_MS - 1));
  }

}
