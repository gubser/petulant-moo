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
    interface Leds;
    interface Boot;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as MilliTimer;
    interface SplitControl as AMControl;
    interface Packet;
    interface Notify<group_project_msg_t>;
    interface Cache<cache_entry_t>;
    interface Pool<message_t>;
    interface Queue<message_t *>;
    interface AMSend as SerialSend;
#ifndef COOJA
    interface StdControl as ClockCalibControl;
#endif
    interface Random;
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

  bool locked;
  bool radioOn;
  uint8_t seq_no = 0;
  
  // function prototypes
  error_t enqueue(message_t * m);
  message_t * forward(message_t * fm);
  void message_to_cache_entry(message_t *m, cache_entry_t * c);
  void senddone(message_t* bufPtr, error_t error);
  void startForwardTimer();
  
  enum {
    FORWARD_DELAY_MS = 3, // max wait time between two forwarded packets
  };
  
  event void Boot.booted() {
    call AMControl.start();
#ifndef COOJA
    call ClockCalibControl.start();
#endif
  }
  
  event void AMControl.startDone(error_t err) {
    if (err == SUCCESS) {
      radioOn=TRUE;
      call Leds.led1On();
      dbg("GroupProjectC", "Radio on, datarate is %u.\n", datarate);
    }
    else {
      call AMControl.start();
    }
  }
  
  event void AMControl.stopDone(error_t err) {
    // do nothing
  }
      
  event void MilliTimer.fired() {
    error_t ret;
    // sink node prints out data on serial port
    if (TOS_NODE_ID == SINK_ADDRESS) {
       ret = call SerialSend.send(AM_BROADCAST_ADDR, call Queue.head(), sizeof(group_project_msg_t));
       dbg("GroupProjectC", "wuut?");
    }
    // other nodes forward data over radio
    else {
      ret = call AMSend.send(AM_BROADCAST_ADDR, call Queue.head(), sizeof(group_project_msg_t));
    }
    if (ret != SUCCESS) {
      startForwardTimer(); // retry in a short while
    }
  }

  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    if (len != sizeof(group_project_msg_t)) {return bufPtr;}
    else {
      return forward(bufPtr);
    }
  }

  event void Notify.notify(group_project_msg_t datamsg) {
    message_t * m;
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
    gpm = (group_project_msg_t*)call Packet.getPayload(m, sizeof(group_project_msg_t));
    *gpm = datamsg;
    // enqueue packet
    enqueue(m);
  }
  
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    senddone(bufPtr, error);
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
    
    dbg("GroupProjectC", "enq(%u,%u) p:%u q:%u\n", c.source, c.seq_no, call Pool.size(), call Queue.size());
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
    gpm = (group_project_msg_t*)call Packet.getPayload(m, sizeof(group_project_msg_t));
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
