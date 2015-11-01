module DataGeneratorP {
 uses {
    interface Random;
    interface Timer<TMilli> as MilliTimer;
    interface Boot;
  }
  provides interface Notify<group_project_msg_t>;
}
implementation {

  enum {
    NUMPACKETS = 200,
  };
  
  group_project_msg_t msg;

  event void Boot.booted() {
    call MilliTimer.startOneShot(10 * 1024 + (TOS_NODE_ID * 111) % 500);
    msg.seq_no = 0;
    msg.source = TOS_NODE_ID;
  }
  
  event void MilliTimer.fired() {
    if (++msg.seq_no < NUMPACKETS)
      call MilliTimer.startOneShot(1024 / datarate);
    msg.data = call Random.rand16();
    signal Notify.notify(msg);
  }

  // not implemented
  command error_t Notify.disable() { return FAIL; }
  command error_t Notify.enable() { return FAIL; }
  
}