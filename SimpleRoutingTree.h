#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H

#include <stdlib.h>
#include <stdio.h>
#include <time.h>

enum{
	MIN = 1,
	MAX = 2,
	COUNT = 3,
	AVG = 4,
	SUM = 5,
	VAR = 6
};
enum{
	MIN1 = 100,
	MAX1 = 200
};
enum{
	MIN2 = 10,
	MAX2 = 20,
	COUNT2 = 30,
	SC2 = 40,
	SUM2 = 50
};
enum{
	TYPE_8 = 1,
	TYPE_16 = 2,
	TYPE_24 = 3,
	TYPE_32 = 4,
	TYPE_56 = 7,
	TYPE_64 = 8,
	TINA_8 = 5,
	TINA_16 = 6
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
	MAX_NODES=32,
	TCT = 10
};

typedef nx_struct RoutingMsg
{
	nx_uint8_t depth;
	nx_uint8_t aggr;
} RoutingMsg;

typedef nx_struct Msg_64
{
	nx_uint8_t var8;
	nx_uint8_t var8_2;
	nx_uint16_t var16;
	nx_uint32_t var32;
} Msg_64;

#endif
