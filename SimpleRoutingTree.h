#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H

#include <stdlib.h>
#include <stdio.h>

enum{
	MIN = 0,
	MAX = 1,
	COUNT = 2,
	SUM = 3,
	AVG = 4,
	VAR = 5
};
enum{
	MIN1 = 100,
	MAX1 = 200
};
enum{
	MIN2 = 10,
	MAX2 = 20,
	COUNT2 = 30,
	SUM2 = 40,
	SC2 = 50
};
enum{
	TYPE_8 = 0,
	TYPE_16 = 1,
	TYPE_24 = 2,
	TYPE_32 = 3,
	TYPE_2X8 = 4
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
	//nx_uint8_t aggr;
} RoutingMsg;

typedef nx_struct NotifyParentMsg
{
	nx_uint16_t sum_value;
	nx_uint8_t count_value;
	nx_uint8_t max_value;
} NotifyParentMsg;

typedef nx_struct Msg_8
{
	nx_uint8_t var;
} Msg_8;
typedef nx_struct Msg_16
{
	nx_uint16_t var;
} Msg_16;
typedef nx_struct Msg_24
{
	nx_uint8_t var8;
	nx_uint16_t var16;
} Msg_24;
typedef nx_struct Msg_32
{
	nx_uint8_t var8_1;
	nx_uint8_t var8_2;
	nx_uint16_t var16;
} Msg_32;
typedef nx_struct Msg_2x8
{
	nx_uint8_t var8_1;
	nx_uint8_t var8_2;
} Msg_2x8;

#endif
