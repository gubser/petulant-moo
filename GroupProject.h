#ifndef GROUP_PROJECT_H
#define GROUP_PROJECT_H
#include <AM.h>

typedef nx_struct schedule {
  nx_uint8_t device_id;
  nx_uint16_t period;          // period in ms
  nx_uint16_t slotsize;        // 
  nx_uint8_t recv_start;
  nx_uint8_t recv_stop;
  nx_uint8_t recv_ack_start;
  nx_uint8_t recv_ack_stop;
  nx_uint8_t send_start;
  nx_uint8_t send_stop;
  nx_uint8_t send_ack_start;
  nx_uint8_t send_ack_stop;
} schedule_t;



typedef nx_struct group_project_msg {
  nx_am_addr_t source;
  nx_uint8_t seq_no;
  nx_uint16_t data;
} group_project_msg_t;

typedef nx_struct timesync_msg {
  nx_uint8_t dummy;
} timesync_msg_t;

enum {
  AM_GROUP_PROJECT_MSG = 6,
  AM_SYNC = 0xA1
};

typedef struct cache_entry {
  am_addr_t source;
  uint8_t seq_no;
} cache_entry_t;

#ifndef DATARATE
#error no data rate specified. Example: use '-DDATARATE=10' to configure a rate of 10 packets per second.
#endif

uint16_t datarate = DATARATE; 

#endif
