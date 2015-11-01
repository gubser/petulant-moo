#ifndef GROUP_PROJECT_H
#define GROUP_PROJECT_H
#include <AM.h>

typedef nx_struct group_project_msg {
  nx_am_addr_t source;
  nx_uint8_t seq_no;
  nx_uint16_t data;
} group_project_msg_t;

enum {
  AM_GROUP_PROJECT_MSG = 6,
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
