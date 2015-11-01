#!/usr/bin/env python

import sys, os, getopt
from struct import *

def usage():
  print "Usage: flocklab2printf.py <serial-input>"

##############################################################################
#
# Main
#
##############################################################################
def main(argv):

  serialfile = None
  
  if len(argv)!=1:
    usage()
    sys.exit()

  serialfile = argv[0]
    
  inf = open(serialfile, "r")
  lines={}
  line = inf.readline()
  while line != '':
    if line[0]=='#':
      line = inf.readline()
      continue
    #print line
    (ts, obs, id, dir, pck) = line[0:-1].split(',', 5)
    pck = pck.decode("hex")
    #header
    #nx_uint16_t: H
    #nx_uint32_t: I
    #nx_uint8_t:  B
    header =  unpack('!BHHBBB', pck[0:8])
    if header[5]==100: # printf
      if obs in lines:
        lines[obs] = lines[obs] + pck[8:].rstrip("\0") 
      else:
         lines[obs] =  pck[8:].rstrip("\0")
      l = lines[obs].split("\n")
      for pl in l[0:-1]:
        print '%s,%s,%s,%s,%s' % (ts, obs, id, dir, pl)
      lines[obs]=l[-1]
    
    line = inf.readline()
  
  
if __name__ == "__main__":
  main(sys.argv[1:])
