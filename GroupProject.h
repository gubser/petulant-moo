#ifndef GROUP_PROJECT_H
#define GROUP_PROJECT_H
#include <AM.h>

#define IS_RELAY(id) (id == 15 || id == 33 || id == 28)

#define BULK_SIZE 12

enum {
  MODE_INIT = 0,
  MODE_LISTEN_ON,
  MODE_LISTEN_ACK,
  MODE_LISTEN_OFF,
  MODE_SEND_ON,
  MODE_SEND_DONE,
  MODE_SEND_ACK,
  MODE_SEND_OFF
};

typedef nx_struct _schedule_t {
  nx_uint8_t device_id;
  nx_uint8_t sendto;
  nx_uint8_t listen;
  nx_uint8_t listen_ack;
  nx_uint8_t send;
  nx_uint8_t send_done;
  nx_uint8_t send_ack;
} schedule_t;



typedef nx_struct group_project_msg {
  nx_am_addr_t source;
  nx_uint8_t seq_no;
  nx_uint16_t data;
} group_project_msg_t;

typedef nx_struct group_bulk_msg {
  nx_am_addr_t source;
  nx_uint8_t seq_no;
  nx_uint16_t data[BULK_SIZE];
} group_bulk_msg_t;

typedef nx_struct timesync_msg {
  nx_uint16_t tag;
  nx_uint32_t remaining;
} timesync_msg_t;

enum {
  AM_GROUP_PROJECT_MSG = 6,
  AM_SYNC = 7
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
