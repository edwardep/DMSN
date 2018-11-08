#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H

#define MAX_NODES 32
//#define DBG_MSG

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
	TIMER_FAST_PERIOD=500
};
/*uint16_t AM_ROUTINGMSG=AM_SIMPLEROUTINGTREEMSG;
uint16_t AM_NOTIFYPARENTMSG=AM_SIMPLEROUTINGTREEMSG;
*/
typedef nx_struct RoutingMsg
{
	nx_uint8_t depth;
	//aggr func
} RoutingMsg;

typedef nx_struct NotifyParentMsg
{
	nx_uint8_t send_values[1];
} NotifyParentMsg;

#endif
