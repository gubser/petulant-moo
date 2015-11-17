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
    interface Timer<TMilli> as TimeSyncSlots;
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
  uint8_t nextState;
  uint8_t currentState;
  
  uint8_t seq_no = 0;
  
  group_bulk_msg_t bulk_current;
  int bulk_index = 0;
  
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

  schedule_t mySchedule;
  
  void get_schedule() {
    switch(TOS_NODE_ID) {
      case 6: { mySchedule.device_id =   6; mySchedule.sendto =   6; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   0; mySchedule.send_ack =   4; } break;
      case 16: { mySchedule.device_id =  16; mySchedule.sendto =  16; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   1; mySchedule.send_ack =   4; } break;
      case 22: { mySchedule.device_id =  22; mySchedule.sendto =  22; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   2; mySchedule.send_ack =   4; } break;
      case 18: { mySchedule.device_id =  18; mySchedule.sendto =  18; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   3; mySchedule.send_ack =   4; } break;
      case 28: { mySchedule.device_id =  28; mySchedule.sendto =  28; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   4; mySchedule.send =   5; mySchedule.send_ack =   9; } break;
      case 3: { mySchedule.device_id =   3; mySchedule.sendto =   3; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   6; mySchedule.send_ack =   9; } break;
      case 32: { mySchedule.device_id =  32; mySchedule.sendto =  32; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   7; mySchedule.send_ack =   9; } break;
      case 31: { mySchedule.device_id =  31; mySchedule.sendto =  31; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   8; mySchedule.send_ack =   9; } break;
      case 33: { mySchedule.device_id =  33; mySchedule.sendto =  33; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   5; mySchedule.listen_ack =   9; mySchedule.send =  10; mySchedule.send_ack =  15; } break;
      case 2: { mySchedule.device_id =   2; mySchedule.sendto =   2; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =  11; mySchedule.send_ack =  15; } break;
      case 4: { mySchedule.device_id =   4; mySchedule.sendto =   4; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =  12; mySchedule.send_ack =  15; } break;
      case 8: { mySchedule.device_id =   8; mySchedule.sendto =   8; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =  13; mySchedule.send_ack =  15; } break;
      case 15: { mySchedule.device_id =  15; mySchedule.sendto =  15; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =  14; mySchedule.send_ack =  15; } break;
      case 1: { mySchedule.device_id =   1; mySchedule.sendto =   1; mySchedule.period =  1000; mySchedule.slotsize =  10; mySchedule.listen =  10; mySchedule.listen_ack =  15; mySchedule.send =   0; mySchedule.send_ack =   0; } break;
    }
  }
  
  event void Boot.booted() {
    int i;

    call RadioControl.start();
#ifndef COOJA
    call ClockCalibControl.start();
#endif
    get_schedule();
  }
  
  event void RadioControl.startDone(error_t err) {
    if (err == SUCCESS) {
      radioOn=TRUE;
      call Leds.led1On();
      dbg("GroupProjectC", "Radio on, datarate is %u.\n", datarate);
      if(TOS_NODE_ID == SINK_ADDRESS) {
        dbg("GroupProjectC", "Emitting timesync packets.\n");
        //call TimeSyncTimer.startPeriodic(5000);
        call TimeSyncTimer.startOneShot(5000);
      }
    }
    else {
      call RadioControl.start();
    }
  }
  
  event void RadioControl.stopDone(error_t err) {
    // do nothing
  }
  
  void sendPacket() {
    error_t ret;
    
    if(call Queue.empty()) {
      dbg("GroupProjectC", "sendPacket: no packets to send.");
      return;
    }
    
    if(currentState != MODE_SEND_ON) {
      dbg("GroupProjectC", "sendPacket: wrong state %d", currentState);
      return;
    }
    
    // sink node prints out data on serial port
    if (TOS_NODE_ID == SINK_ADDRESS) {
      ret = call SerialSend.send(AM_BROADCAST_ADDR, call Queue.head(), sizeof(group_bulk_msg_t));
    }
    // other nodes forward data over radio
    else {
      ret = call RadioSend.send(mySchedule.sendto, call Queue.head(), sizeof(group_bulk_msg_t));
    }
    if (ret != SUCCESS) {
      dbg("GroupProjectC", "sendPacket: fail to send");
      call MilliTimer.startOneShot(1);
    }
  }
  
  event void MilliTimer.fired() {
    sendPacket();
  }
  
  event void RadioSend.sendDone(message_t* bufPtr, error_t error) {
    if (call Queue.head() == bufPtr) {
      locked = FALSE;
      
      // remove from queue
      call Queue.dequeue();
      
      // return buffer
      call Pool.put(bufPtr);
      
      // send next waiting message
      if (!locked) {
        locked = TRUE;
        sendPacket();
      }
    }
  }

  event message_t* RadioReceive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    if(len == sizeof(group_bulk_msg_t)) {
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
  




  uint32_t slotScheduler() {
    uint32_t dt = 0;

    currentState = nextState;
    
    switch (currentState) {
        case MODE_INIT: {
          dbg("GroupProjectC", "MODE_INIT\n");
          if (mySchedule.listen == mySchedule.listen_ack) {
            nextState = MODE_SEND_ON;
            dt = mySchedule.send;
          } 
          else {
            nextState = MODE_LISTEN_ON;
            dt = mySchedule.listen;
          }          
          break;
        }

        case MODE_LISTEN_ON: {
          dbg("GroupProjectC", "MODE_LISTEN_ON\n");
          call Leds.led2On();    
          call RadioControl.start();
          nextState = MODE_LISTEN_ACK;
          dt = mySchedule.listen_ack - mySchedule.listen;
          break;
        }


        case MODE_LISTEN_ACK: {
          dbg("GroupProjectC", "MODE_LISTEN_ACK\n");
          nextState = MODE_LISTEN_OFF;
          dt = 1;
          break;
        }

        case MODE_LISTEN_OFF: {
          dbg("GroupProjectC", "MODE_LISTEN_OFF\n");
          call Leds.led2Off();    
          call RadioControl.stop();
          nextState = MODE_SEND_ON;
          dt = mySchedule.send - (1 + mySchedule.listen_ack);
          break;
        }

        case MODE_SEND_ON: {
          dbg("GroupProjectC", "MODE_SEND_ON\n");
          call Leds.led2On();    
          call RadioControl.start();
          
          call MilliTimer.startOneShot(5);
          nextState = MODE_SEND_ACK;
          dt = mySchedule.send_ack - (1 + mySchedule.send);
          break;
        }

        case MODE_SEND_ACK: {
          dbg("GroupProjectC", "MODE_SEND_ACK\n");
          nextState = MODE_SEND_OFF;
          dt = 1;
          break;
        }

        case  MODE_SEND_OFF: {
          dbg("GroupProjectC", "MODE_SEND_OFF\n");
          call Leds.led2Off();    
          call RadioControl.stop();
          nextState = MODE_INIT;
          dt = mySchedule.period - (1 + mySchedule.send_ack);
          break;
        }
      }
      

      dbg("GroupProjectC", "%lu \n", dt);
      dt = dt * mySchedule.slotsize;

      return dt;      
  }



  event void TimeSyncSlots.fired() {
    uint32_t dt;
    uint32_t t1;
    t1 = call TimeSyncSlots.gett0() + call TimeSyncSlots.getdt();

    dt = slotScheduler();

    call TimeSyncSlots.startOneShotAt(t1, dt);
  }


  event void TimeSyncLaunch.fired() {
    uint8_t dt;
    
    if(TOS_NODE_ID == SINK_ADDRESS) {
      // sink node always on, no scheduling because no energy optimization
    } else {
      nextState = MODE_INIT;
      dt = slotScheduler();
      call TimeSyncSlots.startOneShot(dt);
    }
    dbg("GroupProjectC", "TimeSyncLaunch called\n");
  }



  
  
  event void Notify.notify(group_project_msg_t datamsg) {
    if(bulk_index == 0) {
      bulk_current.source = datamsg.source;
      bulk_current.seq_no = datamsg.seq_no;
    }
    
    bulk_current.data[bulk_index] = datamsg.data;
    
    if(bulk_index == BULK_SIZE-1) {
      message_t * m;
      group_bulk_msg_t* gbm;
      
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
      gbm = (group_bulk_msg_t*)call RadioPacket.getPayload(m, sizeof(group_bulk_msg_t));
      *gbm = bulk_current;
      
      // enqueue packet
      enqueue(m);
      
      // reset bulk buffer
      bulk_index = 0;
    } else {
      bulk_index++;
    }
  }
  
  event void RadioTimeSyncSend.sendDone(message_t* bufPtr, error_t error) {
    
  }
  
  event void SerialSend.sendDone(message_t* bufPtr, error_t error) {
    //senddone(bufPtr, error);
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
    group_bulk_msg_t* gpm;
    gpm = (group_bulk_msg_t*)call RadioPacket.getPayload(m, sizeof(group_bulk_msg_t));
    c->source = gpm->source;
    c->seq_no = gpm->seq_no;
  }

}
