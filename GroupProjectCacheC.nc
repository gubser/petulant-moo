#include "GroupProject.h"

generic module GroupProjectCacheC(uint8_t cachesize)
{
  provides interface Cache<cache_entry_t>;
}
implementation {
  
  cache_entry_t cachetable[cachesize];
  uint8_t numentries;
  uint8_t latest;
  
  command void Cache.flush(){
    numentries = 0;
    latest = 0;
  }
  
  command void Cache.insert(cache_entry_t item){
    if (numentries < cachesize) {
      latest = numentries;
      cachetable[numentries++] = item;
    }
    else {
      // override oldest
      latest = latest+1;
      if (latest == cachesize) {
        latest = 0;
      }
      cachetable[latest] = item;
    }
  }
  
  command bool Cache.lookup(cache_entry_t item){
    uint8_t i;
    for (i=0;i<numentries;i++) {
      if (cachetable[i].source == item.source && cachetable[i].seq_no == item.seq_no) {
        return TRUE;
      }
    }
    return FALSE;
  }
  
}