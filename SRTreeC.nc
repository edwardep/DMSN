#include "SimpleRoutingTree.h"

module SRTreeC
{
	uses interface Boot;
	uses interface SplitControl as RadioControl;

	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	uses interface Packet as RoutingPacket;
	
	uses interface AMSend as NotifyAMSend;
	uses interface AMPacket as NotifyAMPacket;
	uses interface Packet as NotifyPacket;

	uses interface Timer<TMilli> as EpochTimer;
	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as RandomTimer;
	
	uses interface Receive as RoutingReceive;
	uses interface Receive as NotifyReceive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	uses interface PacketQueue as NotifySendQueue;
	uses interface PacketQueue as NotifyReceiveQueue;

	uses interface Random;
	uses interface ParameterInit<uint16_t> as Seed;

}
implementation
{
	uint16_t  roundCounter;
	
	message_t radioRoutingSendPkt;
	message_t radioNotifySendPkt;
	
	bool RoutingSendBusy=FALSE;
	bool NotifySendBusy=FALSE;
	
	uint8_t curdepth;
	uint8_t parentID;

	// local aggr values [32]
	uint32_t children[5][MAX_NODES];
	uint32_t values[5];

	uint8_t aggr1;
	uint8_t aggr2;
	uint8_t packet_t;
	uint8_t num;
	uint8_t msg_type;
	uint8_t raw_data;
	
	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();
	
/*_________________________________________________
				UTILITY FUNCTIONS
___________________________________________________*/
	

	void setRoutingSendBusy(bool state)
	{
		atomic{RoutingSendBusy=state;}
		dbg("RoutingMsg","-F- RoutingRadio is %s\n", (state == TRUE)?"Busy":"Free");
	}
	
	void setNotifySendBusy(bool state)
	{
		atomic{NotifySendBusy=state;}
		dbg("NotifyMsg","-F- NotifyRadio is %s\n", (state == TRUE)?"Busy":"Free");
	}


/*_________________________________________________
				EVENT HANDLERS
___________________________________________________*/
	
	event void Boot.booted()
	{	
		uint8_t i;
		//RADIO INIT
		call RadioControl.start();
		call RandomTimer.startPeriodic(5000000);

		//SIGNALS INIT
		setRoutingSendBusy(FALSE);
		setNotifySendBusy(FALSE);

		//EPOCH INIT
		roundCounter = 0;
		if(TOS_NODE_ID==0)
		{
			curdepth=0;
			parentID=0;
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}	
		for(i=0;i<MAX_NODES;i++)
			children[0][i] = -1;
	}
/**
	@RADIO.START(DONE)
**/	
	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			dbg("Radio" ,"-RadioE- Radio initialized successfully.\n");
			//Radio Init (1 sec)
			if (TOS_NODE_ID==0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		}
		else
		{
			dbg("Radio" , "-RadioE- Radio initialization failed! Retrying...\n");
			call RadioControl.start();
		}
	}
/**
	@RADIO.STOP(DONE)
**/		
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "-RadioE- Radio stopped!\n");
	}
/**
	@TIMER used in Rand.Seed
**/		
	event void RandomTimer.fired()
	{
		dbg("SRTreeC", "RandomTimer fired!\n");
	}
/**
	@DATA_SEND EVENT
**/	
	event void EpochTimer.fired()
	{
		message_t tmp;
		uint8_t iter = 0;
		uint8_t data_avg = 0;
		uint8_t data_var = 0;
		uint8_t var8_full;
		uint8_t msg_size;
		uint8_t temp;

		Msg_64* m;

		// Sense Data and store to local array
		// raw_data = random(1-50)
		call Seed.init((call RandomTimer.getNow())+TOS_NODE_ID);
		raw_data=(call Random.rand16())%50;
		
		temp = raw_data;
		values[0]=raw_data;
		values[1]=raw_data;
		values[2]=1;
		values[3]=raw_data;
		values[4]=raw_data*raw_data;


		// Aggregate subtree values
		// if RootNode  -> Print_Data 
		// else 		-> Forward Data to Parent
		if(TOS_NODE_ID==0)
		{

			if(aggr1 == MIN || aggr2 == MIN)
			{
				for(iter=0;iter<MAX_NODES;iter++)
					if(values[0] > children[0][iter]) 
						values[0] = children[0][iter];
			}
			if(aggr1 == MAX || aggr2 == MAX)
			{
				for(iter=0;iter<MAX_NODES;iter++)
					if(values[1] < children[1][iter]) 
						values[1] = children[1][iter];
			}
			if(aggr1 == COUNT || aggr2 == COUNT || aggr1 == AVG || aggr2 == AVG || aggr1 == VAR || aggr2 == VAR)
			{
				for(iter=0;iter<MAX_NODES;iter++)
					values[2] += children[2][iter];
			}	
			if(aggr1 == SUM || aggr2 == SUM || aggr1 == AVG || aggr2 == AVG || aggr1 == VAR || aggr2 == VAR)
			{
				for(iter=0;iter<MAX_NODES;iter++)
					values[3] += children[3][iter];
			}	
			if(aggr1 == AVG || aggr2 == AVG || aggr1 == VAR || aggr2 == VAR)
			{
				data_avg = values[3]/values[2];
			}
			if(aggr1 == VAR || aggr2 == VAR)
			{
				for(iter=0;iter<MAX_NODES;iter++)
					values[4] += children[4][iter];
				data_var = (values[4]/values[2])-(data_avg*data_avg);
			}
			
			roundCounter += 1;
			dbg("SRTreeC", "\n_________EPOCH___%u_______count=%d,sum=%d,max=%d,min=%d,avg=%d,var=%d_______\n\n", 
			 	roundCounter,values[2],values[3],values[1],values[0],data_avg,data_var);


		}
		else
		{
			aggr2 = msg_type/100;
			aggr1 = (msg_type%100)/10;
			packet_t = msg_type%10;
			var8_full = 0;

			m = (Msg_64*) (call NotifyPacket.getPayload(&tmp, sizeof(Msg_64))); 


			if(aggr1 == MIN || aggr2 == MIN)	//MIN
			{
				for(iter=0;iter<MAX_NODES;iter++)
					if(values[0] > children[0][iter]) 
						values[0] = children[0][iter];
				m->var8=values[0]; var8_full = 1;	
			}
			if(aggr1 == MAX || aggr2 == MAX)	//MAX
			{
				for(iter=0;iter<MAX_NODES;iter++)
					if(values[1] < children[1][iter]) 
						values[1] = children[1][iter];
				if(var8_full)
					m->var8_2=values[1];
				else
					m->var8 = values[1]; var8_full = 1;
			}
			if(aggr1 == COUNT || aggr2 == COUNT || aggr1 == AVG || aggr2 == AVG ) 	//COUNT
			{
				for(iter=0;iter<MAX_NODES;iter++)
					values[2] += children[2][iter];
				if(var8_full)
					m->var8_2=values[2];
				else 
					m->var8 = values[2]; var8_full = 1;
			}
			if(aggr1 == SUM || aggr2 == SUM || aggr1 == AVG || aggr2 == AVG)	//SUM
			{	
				for(iter=0;iter<MAX_NODES;iter++)
					values[3] += children[3][iter];
				m->var16=values[3];
			}
			if(packet_t == TYPE_56 || packet_t == TYPE_64)		//SUM2
			{	
				for(iter=0;iter<MAX_NODES;iter++)
					values[4] += (children[4][iter]*children[4][iter]);
				m->var32=values[4];
			}
			
			dbg("NotifyMsg" , "-EpochTimer.fired- Node: %d\n", TOS_NODE_ID);

			dbg("AggrFunc","In ET.fired: raw_data:%d\n",raw_data);
			dbg("AggrFunc","In ET.fired: var8:%d,var8_2:%d,var16:%d,var32:%d\n",m->var8,m->var8_2,m->var16,m->var32);

			call NotifyAMPacket.setDestination(&tmp, parentID);
			call NotifyPacket.setPayloadLength(&tmp, packet_t);
					
			if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
			{
				if (call NotifySendQueue.size() == 1)
				{	
					dbg("NotifyMsg", "-NotifySendE- SendNotifyTask() posted.\n");
					post sendNotifyTask();
				}
			}
		}
	}

/**
	@BROADCASTING EVENT
**/
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		uint8_t num;
		RoutingMsg* mrpkt;

		dbg("RoutingMsg", "-TimerFiredE- RoutingMsgTimer fired!  RoutingRadio is %s \n",(RoutingSendBusy)?"Busy":"Free");
		
		if(call RoutingSendQueue.full())
		{
			dbg("RoutingMsg", "-TimerFiredE- RoutingSendQueue is full.\n");
			return;
		}
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			dbg("RoutingMsg","-TimerFiredE- No valid payload.\n");
			return;
		}

		/*NODE 0 - setup aggr func parameters*/
		if(TOS_NODE_ID == 0)
		{	
			num = 0;
			aggr1 = VAR;
			aggr2 = VAR;
			//call Seed.init((call RandomTimer.getNow()));
			if(!num)
			{
				//aggr1 = (call Random.rand16())%5;
				aggr2 = 0;
				if(aggr1 == MIN)
					msg_type = MIN2+TYPE_8;
				else if(aggr1 == MAX)
					msg_type = MAX2+TYPE_8;
				else if(aggr1 == COUNT)
					msg_type = COUNT2+TYPE_8;
				else if(aggr1 == SUM)
					msg_type = SUM2+TYPE_16;
				else if(aggr1 == AVG)
					msg_type = SC2+TYPE_24;
				else
					msg_type = SC2+TYPE_56;
			}
			else
			{
				//aggr1 = (call Random.rand16())%5;
				//aggr2 = (call Random.rand16())%5;
				
				if(aggr1 == SUM || aggr2 == SUM)
				{
					if(aggr1 == MIN || aggr2 == MIN)
						msg_type = MIN1+SUM2+TYPE_24;
					else if(aggr1 == MAX || aggr2 == MAX)
						msg_type = MAX1+SUM2+TYPE_24;
					else if(aggr1 == VAR || aggr2 == VAR)
						msg_type = SC2+TYPE_56;
					else 
						msg_type = SC2+TYPE_24;
				}
				else if(aggr1 == AVG || aggr2 == AVG)
				{
					if(aggr1 == MIN || aggr2 == MIN)
						msg_type = MIN1+SC2+TYPE_32;
					else if(aggr1 == MAX || aggr2 == MAX)
						msg_type = MAX1+SC2+TYPE_32;
					else if(aggr1 == VAR || aggr2 == VAR)
						msg_type = SC2+TYPE_56;
					else
						msg_type = SC2+TYPE_24;
				}
				else if(aggr1 == VAR || aggr2 == VAR)
				{
					if(aggr1 == MIN || aggr2 == MIN)
						msg_type = MIN1+SC2+TYPE_64;
					else if(aggr1 == MAX || aggr2 == MAX)
						msg_type = MAX1+SC2+TYPE_64;
					else
						msg_type = SC2+TYPE_56;
				}
				else if(aggr1 == COUNT || aggr2 == COUNT)
				{
					if(aggr1 == MIN || aggr2 == MIN)
						msg_type = MIN1+COUNT2+TYPE_16;
					else
						msg_type = MAX1+COUNT2+TYPE_16;
				}
				else
					msg_type = MIN1+MAX2+TYPE_16;
			}
		}
		atomic
		{
			mrpkt->depth = curdepth;
			mrpkt->aggr = msg_type;
		}

		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		enqueueDone = call RoutingSendQueue.enqueue(tmp);

		dbg("RoutingMsg" , "-TimerFiredE- Broadcasting RoutingMsg\n");

		if( enqueueDone==SUCCESS )
		{
			if (call RoutingSendQueue.size()==1)
			{
				dbg("RoutingMsg", "-TimerFiredE- SendRoutingTask() posted!\n");
				post sendRoutingTask();
			}
		}
		else
		{
			dbg("RoutingMsg","-TimerFiredE- Msg failed to be enqueued in RoutingSendQueue.");
		}		
	}
/**
	@RADIO.SEND(NOTIFY_MSG)
**/
	event void NotifyAMSend.sendDone(message_t *msg , error_t err)
	{
		setNotifySendBusy(FALSE);
		
		if(!(call NotifySendQueue.empty()))
		{
			dbg("NotifyMsg", "-NotifySendE- sendNotifyTask() posted!\n");
			post sendNotifyTask();
		}
	}
/**
	@RADIO.SEND(ROUTING_MSG)
**/
	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("RoutingMsg", "-RoutingSendE- A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");	
		setRoutingSendBusy(FALSE);

		if(!(call RoutingSendQueue.empty()))
		{
			dbg("RoutingMsg", "-RoutingSendE- sendRoutingTask() posted!\n");
			post sendRoutingTask();
		}

	}
/**
	@RADIO.RECEIVE(NOTIFY_MSG)
**/
	event message_t* NotifyReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource = call NotifyAMPacket.source(msg);

		//dbg("NotifyMsg", "-NotifyRecE- count: %u, Source: %u \n",((Msg_64*) payload)->count_value, msource);

		atomic{ memcpy(&tmp,msg,sizeof(message_t));}

		enqueueDone = call NotifyReceiveQueue.enqueue(tmp);

		dbg("NotifyMsg", "NotifyReceiveQueue Size: %d\n",call NotifyReceiveQueue.size());

		if( enqueueDone== SUCCESS)
		{
			dbg("NotifyMsg", "-NotifyRecE- receiveNotifyTask() posted!\n");
			post receiveNotifyTask();
		}
		else
		{
			dbg("NotifyMsg","-NotifyRecE- Msg failed to be enqueued in NotifyReceiveQueue.");	
		}
		return msg;
	}
/**
	@RADIO.RECEIVE(ROUTING_MSG)
**/
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);

		// Receive Routing Msg Top-Down
		if(curdepth > (((RoutingMsg*) payload)->depth))
		{
	
			atomic{ memcpy(&tmp,msg,sizeof(message_t));}

			enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
			if(enqueueDone == SUCCESS)
			{
				dbg("RoutingMsg", "-RoutingRecE- receiveRoutingTask() posted!\n");
				post receiveRoutingTask();
			}
			else
			{
				dbg("RoutingMsg","-RoutingRecE- Msg failed to be enqueued in RoutingReceiveQueue.");		
			}
		}
		return msg;
	}

/*_________________________________________________
				TASK IMPLEMENTATIONS
___________________________________________________*/

/**
	@SEND_ROUTING_TASK() | Send a Routing Msg over the Radio
**/
	task void sendRoutingTask()
	{
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		
		if (call RoutingSendQueue.empty())
		{
			dbg("RoutingMsg","-RoutingSendT- Queue is empty.\n");
			return;
		}
		if(RoutingSendBusy)
		{
			dbg("RoutingMsg","-RoutingSendT- RoutingRadio is Busy.\n");
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);

		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("RoutingMsg","-RoutingSendT- Unknown message. \n");
			return;
		}

		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("RoutingMsg","-RoutingSendT- Send was successfull\n");
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("RoutingMsg","-RoutingSendT- Send failed!\n");
		}

		if(TOS_NODE_ID==0)
		{
			call EpochTimer.startPeriodic(EPOCH_MILLI);
		}	
	}
/**
	@RECEIVE_ROUTING_TASK() | Updates PID-Depth, starts Periodic Timer and re-broadcasts
**/
	task void receiveRoutingTask()
	{
		uint8_t len;
		uint16_t time_window;
		uint16_t random_interval;
		message_t radioRoutingRecPkt;
		
		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		//if received msg is RoutingMsg		
		if(len == sizeof(RoutingMsg))
		{
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			
			// set Parent and Depth
			parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);
			curdepth= mpkt->depth + 1;
			msg_type= mpkt->aggr;
			dbg("SRTreeC","msg_type:%d\n",msg_type);
			// generate random number for conflict avoidance
			call Seed.init((call RandomTimer.getNow())+TOS_NODE_ID);
			random_interval = ((call Random.rand16())%MAX_NODES)*10;

			// calculate TAG-like fixed time-window
			time_window  = (EPOCH_MILLI/MAX_DEPTH)*curdepth;

			call EpochTimer.startPeriodicAt(-time_window-random_interval,EPOCH_MILLI);

			// broadcast to posible children
			call RoutingMsgTimer.startOneShot(INSTANT);
		}
		else // received msg is not RoutingMsg
		{
			dbg("RoutingMsg","-RoutingRecT- Not a RoutingMsg.\n");
			return;
		}
	}
/**
	@SEND_NOTIFY_TASK() | Sends a packet over the Radio
**/
	task void sendNotifyTask()
	{
		uint8_t mlen;
		error_t sendDone;
		uint16_t mdest;
		Msg_64* mpayload;

		if (call NotifySendQueue.empty())
		{
			dbg("NotifyMsg","-NotifySendT- Queue is empty.\n");
			return;
		}
		
		if(NotifySendBusy==TRUE)
		{
			dbg("NotifyMsg","-NotifySendT- NotifyRadio is Busy.\n");
			return;
		}
		
		radioNotifySendPkt = call NotifySendQueue.dequeue();
		mlen=call NotifyPacket.payloadLength(&radioNotifySendPkt);
		mpayload= call NotifyPacket.getPayload(&radioNotifySendPkt,mlen);
		
		// if(mlen!= 16)
		// {
		// 	dbg("NotifyMsg", "-NotifySendT- Unknown message.\n");
		// 	return;
		// }
		// Unicast to Parent
		mdest= call NotifyAMPacket.destination(&radioNotifySendPkt);
		// Send Packet over Radio
		sendDone=call NotifyAMSend.send(mdest,&radioNotifySendPkt, mlen);
		
		if (sendDone== SUCCESS)
		{
			dbg("NotifyMsg","-NotifySendT- Send was successfull.\n");
			setNotifySendBusy(TRUE);
		}
		else
		{
			dbg("NotifyMsg","-NotifySendT- Send failed.\n");
		}
	}
/**
	@RECEIVE_NOTIFY_TASK() | Receives packets from children-Nodes and stores their values
**/
	task void receiveNotifyTask()
	{
		uint8_t len;
		message_t radioNotifyRecPkt;
		Msg_64* mr;
		uint8_t var8_full = 0;
		uint8_t childID;

		radioNotifyRecPkt= call NotifyReceiveQueue.dequeue();

		len= call NotifyPacket.payloadLength(&radioNotifyRecPkt);
		
		dbg("SRTreeC","NotifyReceive..length=%d bits\n",len*8);
		

			
		mr = (Msg_64*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
		dbg("AggrFunc","In NotifRec: var8:%d,var8_2:%d,var16:%d,var32:%d\n",mr->var8,mr->var8_2,mr->var16,mr->var32);			
			
		childID = call NotifyAMPacket.source(&radioNotifyRecPkt);
		
		if(aggr1 == MIN || aggr2 == MIN)	//MIN
		{
			children[0][childID] = mr->var8;
			var8_full = 1; 
		}
		if(aggr1 == MAX || aggr2 == MAX)	//MAX
		{
			if(var8_full)
				children[1][childID] = mr->var8_2;
			else
				children[1][childID] = mr->var8; var8_full = 1;
		}
		if(aggr1 == COUNT || aggr2 == COUNT || aggr1 == AVG || aggr2 == AVG)	//COUNT
		{
			if(var8_full)
				children[2][childID] = mr->var8_2;
			else
				children[2][childID] = mr->var8; var8_full = 1;
		}
		if(aggr1 == SUM || aggr2 == SUM || aggr1 == AVG || aggr2 == AVG)	//SUM
		{	
			children[3][childID] = mr->var16; 
		}
		if(packet_t == TYPE_56 || packet_t == TYPE_64)		//SUM2
		{	
			children[4][childID] = mr->var32;
		}
	}
}
