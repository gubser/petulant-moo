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
    interface Boot;
#ifndef COOJA
    interface StdControl as ClockCalibControl;
#endif
    interface Leds;
    interface Random;
    
    // Interfaces for radio communication
    interface Receive as RadioReceive;
    interface Receive as RadioAckReceive;
    interface Receive as RadioTimeSyncReceive;
    interface AMSend as RadioSend;
    interface AMSend as RadioAckSend;
    interface SplitControl as RadioControl;
    interface Packet as RadioPacket;
    interface AMPacket as RadioPacketInfo;
    interface TimeSyncPacket<TMilli, uint32_t> as RadioTimeSyncPacket;
    interface TimeSyncAMSend<TMilli, uint32_t> as RadioTimeSyncSend;
    
    // Timer
    interface Timer<TMilli> as TimerSend;
    interface Timer<TMilli> as TimerSendAck;
    interface Timer<TMilli> as TimerSerial;
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

#undef debug_printf
#ifdef debug_printf
#warning debug printf enabled
#undef dbg
#define dbg(component, fmt, ...) do {\
  printf(fmt, ##__VA_ARGS__);\
  } while(0);
#else
#warning debug printf not enabled
#endif

  bool radioOn;
  uint8_t nextState;
  uint8_t currentState;
  
  uint8_t seq_no = 0;
  
  group_bulk_msg_t bulk_current;
  int bulk_index = 0;
  int bulks_sent_count = 0;
  
  message_t bulks_ack_msg;
  uint16_t bulks_recv_map;
  
  group_bulk_msg_t serial_bulk;
  int serial_next = BULK_SIZE;
  message_t serial_packet;
  bool serial_sent = TRUE;
  bool serial_sending = FALSE;
  
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
  void serialSendPacket();
  bool serialDissectBulk();
  
  enum {
    FORWARD_DELAY_MS = 3, // max wait time between two forwarded packets
    TIMESYNC_DELAY_MS = 5, // delay multiplied by id for TDMA-like flooding
    TIMESYNC_DELAY_WAIT = 200
  };

  schedule_t mySchedule;
  
  uint16_t schedule_period;
  uint16_t schedule_slotsize;
  
  void get_schedule() {
    if(datarate < 5) {              // optimized for datarate == 1
        schedule_period = 400;
        schedule_slotsize = 20;
    } else if(datarate < 20) {      // datarate == 10
        schedule_period = 150;
        schedule_slotsize = 20;
    } else {                        // datarate == 50
        schedule_period = 50;
        schedule_slotsize = 20;
    }
    switch(TOS_NODE_ID) {
      case  2: { mySchedule.device_id =   2; mySchedule.sendto =   1; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =  19; mySchedule.send_done =  20; mySchedule.send_ack =  31; } break;
      case 33: { mySchedule.device_id =  33; mySchedule.sendto =   8; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   9; mySchedule.send_done =  10; mySchedule.send_ack =  15; } break;
      case 16: { mySchedule.device_id =  16; mySchedule.sendto =   6; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   1; mySchedule.send_done =   2; mySchedule.send_ack =   3; } break;
      case 22: { mySchedule.device_id =  22; mySchedule.sendto =   6; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   2; mySchedule.send_done =   3; mySchedule.send_ack =   3; } break;
      case  6: { mySchedule.device_id =   6; mySchedule.sendto =   3; mySchedule.listen =   1; mySchedule.listen_ack =   3; mySchedule.send =   4; mySchedule.send_done =   7; mySchedule.send_ack =   8; } break;
      case 28: { mySchedule.device_id =  28; mySchedule.sendto =   3; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =   7; mySchedule.send_done =   8; mySchedule.send_ack =   8; } break;
      case  3: { mySchedule.device_id =   3; mySchedule.sendto =   8; mySchedule.listen =   4; mySchedule.listen_ack =   8; mySchedule.send =  10; mySchedule.send_done =  15; mySchedule.send_ack =  15; } break;
      case  8: { mySchedule.device_id =   8; mySchedule.sendto =   1; mySchedule.listen =   9; mySchedule.listen_ack =  15; mySchedule.send =  20; mySchedule.send_done =  27; mySchedule.send_ack =  31; } break;
      case 31: { mySchedule.device_id =  31; mySchedule.sendto =  15; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =  16; mySchedule.send_done =  17; mySchedule.send_ack =  18; } break;
      case 32: { mySchedule.device_id =  32; mySchedule.sendto =  15; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =  17; mySchedule.send_done =  18; mySchedule.send_ack =  18; } break;
      case 15: { mySchedule.device_id =  15; mySchedule.sendto =   1; mySchedule.listen =  16; mySchedule.listen_ack =  18; mySchedule.send =  27; mySchedule.send_done =  30; mySchedule.send_ack =  31; } break;
      case  4: { mySchedule.device_id =   4; mySchedule.sendto =   1; mySchedule.listen =   0; mySchedule.listen_ack =   0; mySchedule.send =  30; mySchedule.send_done =  31; mySchedule.send_ack =  31; } break;
      case  1: { mySchedule.device_id =   1; mySchedule.sendto =   1; mySchedule.listen =  19; mySchedule.listen_ack =  31; mySchedule.send =   0; mySchedule.send_done =   0; mySchedule.send_ack =   0; } break;
    }
  }
  
  event void Boot.booted() {
    call RadioControl.start();
#ifndef COOJA
    call ClockCalibControl.start();
#endif
    get_schedule();
    if(TOS_NODE_ID == SINK_ADDRESS) {
      serialSendPacket();
    }
  }
  
  event void RadioControl.startDone(error_t err) {
    if (err == SUCCESS) {
      radioOn=TRUE;
      dbg("GroupProjectC", "Radio on, datarate is %u.\n", datarate);
      if(TOS_NODE_ID == SINK_ADDRESS) {
        dbg("GroupProjectC", "Emitting timesync packets.\n");
        call TimeSyncTimer.startOneShot(2000);
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
    
    if(call Queue.size() <= bulks_sent_count) {
      dbg("GroupProjectC", "sendPacket: no packets to send.\n");
      return;
    }
    
    if(currentState != MODE_SEND_ON) {
      dbg("GroupProjectC", "sendPacket: wrong state %d\n", currentState);
      return;
    }
    
    // sink node prints out data on serial port
    // other nodes forward data over radio
    ret = call RadioSend.send(mySchedule.sendto, call Queue.element(bulks_sent_count), sizeof(group_bulk_msg_t));
    if (ret != SUCCESS) {
      dbg("GroupProjectC", "sendPacket: fail to send\n");
      call TimerSend.startOneShot(1);
    }
  }
  
  event void TimerSend.fired() {
    sendPacket();
  }
  
  event void RadioSend.sendDone(message_t* bufPtr, error_t error) {
    if (call Queue.element(bulks_sent_count) == bufPtr) {
      // account for sent messages
      bulks_sent_count++;
      
      // send next waiting message
      sendPacket();
    }
  }
  
  int id2idx(int id) {
    switch(id) {
      case  2: return 1;
      case  3: return 2;
      case  4: return 3;
      case  6: return 4;
      case  8: return 5;
      case 15: return 6;
      case 16: return 7;
      case 22: return 8;
      case 28: return 9;
      case 31: return 10;
      case 32: return 11;
      case 33: return 12;
      default: return 0;
    }
  }
  
  event message_t* RadioAckReceive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    int i;
    group_bulk_ack_t *gba;
    if(len == sizeof(group_bulk_ack_t)) {
      gba = (group_bulk_ack_t*)payload;
      if(gba->nodes & (1 << id2idx(TOS_NODE_ID)) && call RadioPacketInfo.source(bufPtr) == mySchedule.sendto) {
        dbg("GroupProjectC", "Received ack from my relay. %u bulks\n", bulks_sent_count);
        
        for(i = 0;i < bulks_sent_count;i++) {
          // remove from queue
          message_t *buf = call Queue.dequeue();
          
          // return buffer
          call Pool.put(buf);
        }
        
        bulks_sent_count = 0;
      }
    }
    return bufPtr;
  }
  
  event void RadioAckSend.sendDone(message_t* bufPtr, error_t error) {
  }
  
  event void TimerSendAck.fired() {
    group_bulk_ack_t *gba;
    error_t ret;
    
    if(currentState != MODE_LISTEN_ACK || bulks_recv_map == 0) {
        return;
    }
    
    gba = (group_bulk_ack_t*)call RadioPacket.getPayload(&bulks_ack_msg, sizeof(group_bulk_ack_t));
    gba->nodes = bulks_recv_map;
    ret = call RadioAckSend.send(AM_BROADCAST_ADDR, &bulks_ack_msg, sizeof(group_bulk_ack_t));
    if (ret != SUCCESS) {
      dbg("GroupProjectC", "send ack packet: fail to send %d\n", ret);
    } else {
      dbg("GroupProjectC", "send ack packet: send ok\n");
    }
    
    call TimerSendAck.startOneShot(10);
  }

  event message_t* RadioReceive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    if(len == sizeof(group_bulk_msg_t)) {
      bulks_recv_map |= 1 << id2idx(call RadioPacketInfo.source(bufPtr));
      
      return forward(bufPtr);
    }
    dbg("RadioReceive", "Received unknown packet in RadioReceive\n");
    return bufPtr;
  }
  
  void serialSendPacket() {
    error_t ret;
    serial_sending = TRUE;
    
    if(TOS_NODE_ID != SINK_ADDRESS) {
      dbg("GroupProjectC", "sendSerialPacket: source code bug, only sink should call this.\n");
      return;
    }
    
    if(serialDissectBulk() == FALSE) {
      // nothing to do
      serial_sending = FALSE;
      return;
    }
    
    // sink node prints out data on serial port
    ret = call SerialSend.send(AM_BROADCAST_ADDR, &serial_packet, sizeof(group_project_msg_t));
    if (ret != SUCCESS) {
      dbg("GroupProjectC", "sendSerialPacket: fail to send\n");
      call TimerSerial.startOneShot(1);
    }
  }
  
  bool serialDissectBulk() {
    message_t *m;
    group_project_msg_t *gpm;
    
    if(serial_sent == FALSE) {
      // our current packet hasn't been sent yet.
      return TRUE;
    }
    
    if(serial_next == BULK_SIZE) {
      // get a new bulk message
      if(call Queue.empty()) {
        return FALSE;
      }
      
      m = call Queue.head();
      // copy payload
      serial_bulk = *((group_bulk_msg_t*)call RadioPacket.getPayload(m, sizeof(group_bulk_msg_t)));
      serial_next = 0;
      
      // remove from queue
      call Queue.dequeue();
      call Pool.put(m);
    }
    
    gpm = (group_project_msg_t*)call RadioPacket.getPayload(&serial_packet, sizeof(group_project_msg_t));
    
    gpm->source = serial_bulk.source;
    gpm->seq_no = serial_bulk.seq_no+serial_next;
    gpm->data = serial_bulk.data[serial_next];
    
    serial_next++;
    
    // new packet has not been sent yet
    serial_sent = FALSE;
    
    return TRUE;
  }
  
  event void SerialSend.sendDone(message_t* bufPtr, error_t error) {
    serial_sent = TRUE;
    serialSendPacket();
  }
  
  void serialWakeUp() {
    if(serial_sending == FALSE) {
      serialSendPacket();
    }
  }
  
  event void TimerSerial.fired() {
    serialSendPacket();
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
        return bufPtr;
      }
      
      // got a new timesync request?
      if(sync_tag != tsm->tag) {
        sync_tag = tsm->tag;
        sync_recvTime = call RadioTimeSyncPacket.eventTime(bufPtr);
        sync_remaining = tsm->remaining;
        
        tnow = call LocalTime.get();
        
        call TimeSyncLaunch.startOneShot(sync_remaining - (tnow - sync_recvTime));
        
        dbg("RadioTimeSyncReceive", "sync time: %lu, local time: %lu\n", sync_recvTime, tnow);
        
        //if(IS_RELAY(TOS_NODE_ID)) {
          call TimeSyncTimer.startOneShot(TIMESYNC_DELAY_WAIT + TIMESYNC_DELAY_MS*TOS_NODE_ID);
          
          if(TIMESYNC_DELAY_MS*TOS_NODE_ID > sync_remaining) {
            dbg("RadioTimeSyncReceive", "Timing violation\n");
          }
        //}

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
#ifdef COOJA
          call Leds.led1On();
#endif
          call RadioControl.start();
          nextState = MODE_LISTEN_ACK;
          dt = mySchedule.listen_ack - mySchedule.listen;
          break;
        }


        case MODE_LISTEN_ACK: {
          dbg("GroupProjectC", "MODE_LISTEN_ACK\n");
#ifdef COOJA
          call Leds.led1Off();
          call Leds.led2On();
#endif
          call TimerSendAck.startOneShot(0);
          nextState = MODE_LISTEN_OFF;
          dt = 1;
          break;
        }

        case MODE_LISTEN_OFF: {
          dbg("GroupProjectC", "MODE_LISTEN_OFF\n");
          dt = mySchedule.send - (1 + mySchedule.listen_ack);
          
#ifdef COOJA
          call Leds.led2Off();
#endif
          if(dt > 1) {
            call RadioControl.stop();
          }
          call TimerSendAck.stop();
          
          bulks_recv_map = 0;
          
          nextState = MODE_SEND_ON;
          break;
        }

        case MODE_SEND_ON: {
          dbg("GroupProjectC", "MODE_SEND_ON\n");
#ifdef COOJA
          call Leds.led2On();
#endif
          if(call Queue.empty() == FALSE) {
            call RadioControl.start();
          }
          
          call TimerSend.startOneShot(5);
          nextState = MODE_SEND_DONE;
          dt = mySchedule.send_done - mySchedule.send;
          break;
        }
        
        case MODE_SEND_DONE: {
          dbg("GroupProjectC", "MODE_SEND_DONE\n");
          nextState = MODE_SEND_ACK;
#ifdef COOJA
          call Leds.led2Off();
#endif
          dt = mySchedule.send_ack - mySchedule.send_done;
          if(dt > 1) {
            call RadioControl.stop();
          }
          break;
        }

        case MODE_SEND_ACK: {
          dbg("GroupProjectC", "MODE_SEND_ACK\n");
#ifdef COOJA
          call Leds.led0On();
#endif
          if(bulks_sent_count > 0) {
            call RadioControl.start();
          }
          nextState = MODE_SEND_OFF;
          dt = 1;
          break;
        }

        case  MODE_SEND_OFF: {
          dbg("GroupProjectC", "MODE_SEND_OFF\n");
#ifdef COOJA
          call Leds.led0Off();
#endif
          call RadioControl.stop();
          nextState = MODE_INIT;
          dt = schedule_period - (1 + mySchedule.send_ack);
          
          // reset bulks counter
          bulks_sent_count = 0;
          break;
        }
      }
      

      dbg("GroupProjectC", "%lu \n", dt);
      dt = dt * schedule_slotsize;

      return dt;      
  }
  
  uint32_t slotSchedulerSink() {
    uint32_t dt = 0;

    currentState = nextState;
    
    switch (currentState) {
        case MODE_INIT: {
          dt = mySchedule.listen_ack;
          nextState = MODE_LISTEN_ACK;
          break;
        }

        case MODE_LISTEN_ACK: {
          dbg("GroupProjectC", "MODE_LISTEN_ACK\n");
#ifdef COOJA
          call Leds.led2On();
#endif
          call TimerSendAck.startOneShot(0);
          nextState = MODE_LISTEN_OFF;
          dt = 1;
          break;
        }

        case MODE_LISTEN_OFF: {
          dbg("GroupProjectC", "MODE_LISTEN_OFF\n");
#ifdef COOJA
          call Leds.led2Off();
#endif
          bulks_recv_map = 0;
          
          dt = schedule_period - (1+mySchedule.listen_ack);
          nextState = MODE_INIT;
          break;
        }
      }
      

      dbg("GroupProjectC", "%lu \n", dt);
      dt = dt * schedule_slotsize;

      return dt;      
  }

  event void TimeSyncSlots.fired() {
    uint32_t dt;
    uint32_t t1;
    t1 = call TimeSyncSlots.gett0() + call TimeSyncSlots.getdt();
    
    if(TOS_NODE_ID == SINK_ADDRESS) {
      dt = slotSchedulerSink();
    } else {
      dt = slotScheduler();
    }

    call TimeSyncSlots.startOneShotAt(t1, dt);
  }

  event void TimeSyncLaunch.fired() {
    uint32_t dt;
    
    if(TOS_NODE_ID == SINK_ADDRESS) {
      nextState = MODE_INIT;
      dt = slotSchedulerSink();
    } else {
      nextState = MODE_INIT;
      dt = slotScheduler();
    }
    call TimeSyncSlots.startOneShot(dt);
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
    
    if(TOS_NODE_ID == SINK_ADDRESS) {
      // wake up serial if idle
      serialWakeUp();
    }
    
    return SUCCESS;
  }
  
  message_t * forward(message_t * fm) {
    cache_entry_t c;
    // get spare message buffer
    message_t * m = call Pool.get();
    if (m == NULL) {
      dbg("GroupProjectC", "forward(): no more message buffers.\n");
      if(TOS_NODE_ID == SINK_ADDRESS) {
        call Leds.led1On();
      }
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
