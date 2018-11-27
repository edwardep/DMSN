#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H

#include <stdlib.h>
#include <stdio.h>

#define MAX_NODES 32
#define DBG_MSG

enum{
	COUNT=0,
	SUM=1,
	MAX=2
};

enum{
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3,
	AM_SIMPLEROUTINGTREEMSG=22,
	AM_ROUTINGMSG=22,
	AM_NOTIFYPARENTMSG=12,
	SEND_CHECK_MILLIS=3000,
	EPOCH_MILLI= 61440,
	TIMER_FAST_PERIOD=1024,
	INSTANT = 0
};

typedef nx_struct RoutingMsg
{
	nx_uint8_t depth;
	//aggr func
} RoutingMsg;

typedef nx_struct NotifyParentMsg
{
	nx_uint16_t send_values[3];
} NotifyParentMsg;

#endif
