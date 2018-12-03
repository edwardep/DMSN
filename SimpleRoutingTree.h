#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H

#include <stdlib.h>
#include <stdio.h>

enum{
	COUNT=0,
	SUM=1,
	MAX=2
};

enum{
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3,
	AM_ROUTINGMSG=22,
	AM_NOTIFYPARENTMSG=12,
	EPOCH_MILLI= 61440,
	TIMER_FAST_PERIOD=1024,
	INSTANT = 0,
	MAX_DEPTH=32,
	MAX_NODES=32
};

typedef nx_struct RoutingMsg
{
	nx_uint8_t depth;
} RoutingMsg;

typedef nx_struct NotifyParentMsg
{
	nx_uint16_t sum_value;
	nx_uint8_t count_value;
	nx_uint8_t max_value;
} NotifyParentMsg;

#endif
