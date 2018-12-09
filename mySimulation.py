#!/usr/bin/python
from TOSSIM import *
import sys ,os
import random
t=Tossim([])
f=sys.stdout #open('./logfile.txt','w')
SIM_END_TIME= 400 * t.ticksPerSecond()
print "TicksPerSecond : ", t.ticksPerSecond(),"\n"
#t.addChannel("Boot",f)
#t.addChannel("RoutingMsg",f)
#t.addChannel("NotifyMsg",f)
#t.addChannel("Radio",f)
#t.addChannel("AggrFunc",f)
t.addChannel("SRTreeC",f)

#_____________________
total_nodes = 49
#_____________________

for i in range(0,total_nodes):
	m=t.getNode(i)
	m.bootAtTime(10*t.ticksPerSecond() + i)
topo = open("topology.txt", "r")
if topo is None:
	print "Topology file not opened!!! \n"

r=t.radio()
lines = topo.readlines()
for line in lines:
  s = line.split()
  if (len(s) > 0):
    print " ", s[0], " ", s[1], " ", s[2];
    r.add(int(s[0]), int(s[1]), float(s[2]))
mTosdir = os.getenv("TINYOS_ROOT_DIR")
noiseF=open(mTosdir+"/tos/lib/tossim/noise/meyer-heavy.txt","r")
lines= noiseF.readlines()
for line in  lines:
	str1=line.strip()
	if str1:
		val=int(str1)
		for i in range(0,total_nodes):
			t.getNode(i).addNoiseTraceReading(val)
noiseF.close()
for i in range(0,total_nodes):
	t.getNode(i).createNoiseModel()
	
ok=False
#if(t.getNode(0).isOn()==True):
#	ok=True
h=True
while(h):
	try:
		h=t.runNextEvent()
		#print h
	except:
		print sys.exc_info()
#		e.print_stack_trace()
	if (t.time()>= SIM_END_TIME):
		h=False
	if(h<=0):
		ok=False
