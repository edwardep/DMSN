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
	uint16_t children[3][MAX_NODES];

	uint16_t sum_value;
	uint8_t count_value;
	uint8_t max_value;
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
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d ,check_sum= %d\n", curdepth , parentID, count_value);
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d ,check_sum= %d\n", curdepth , parentID, count_value);
		}
	 	sum_value=0;
		count_value=1;
		max_value=0;
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
		
		NotifyParentMsg* m;
		message_t tmp;
		uint8_t iter = 0;
		uint16_t data_avg = 0;
		
		// Sense Data and store to local array
		// raw_data = random(1-50)
		call Seed.init((call RandomTimer.getNow())+TOS_NODE_ID);
		raw_data=(call Random.rand16())%50;
		
		sum_value=raw_data;
		count_value=1;
		max_value=raw_data;

		// Aggregate subtree values
		// if RootNode  -> Print_Data 
		// else 		-> Forward Data to Parent
		if(TOS_NODE_ID==0)
		{
			for(iter=0;iter<MAX_NODES;iter++)
			{
				count_value += children[COUNT][iter];
				sum_value+= children[SUM][iter];
				if(max_value<children[MAX][iter]) 
					max_value = children[MAX][iter];

			}
			data_avg= sum_value/count_value;
			
			roundCounter += 1;
			 dbg("SRTreeC", "\n_________EPOCH___%u_______count=%d,sum=%d,avg=%d,max=%d_______\n\n", 
			 	roundCounter,count_value,sum_value,data_avg,max_value);

		}
		else
		{
			m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
			m->count_value=count_value;
			m->sum_value=sum_value;

			for(iter=0;iter<MAX_NODES;iter++)
			{
				m->count_value += children[COUNT][iter];
				m->sum_value+= children[SUM][iter];
				if(max_value<children[MAX][iter]) 
					max_value = children[MAX][iter];
			}
			m->max_value = max_value;
			
			dbg("NotifyMsg" , "-EpochTimer.fired- Node: %d, count: %d\n", TOS_NODE_ID,count_value);

			call NotifyAMPacket.setDestination(&tmp, parentID);
			call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
					
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

		atomic{mrpkt->depth = curdepth;}

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

		dbg("NotifyMsg", "-NotifyRecE- count: %u, Source: %u \n",((NotifyParentMsg*) payload)->count_value, msource);

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
		NotifyParentMsg* mpayload;

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
		
		if(mlen!= sizeof(NotifyParentMsg))
		{
			dbg("NotifyMsg", "-NotifySendT- Unknown message.\n");
			return;
		}
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
		uint8_t childID;

		radioNotifyRecPkt= call NotifyReceiveQueue.dequeue();

		len= call NotifyPacket.payloadLength(&radioNotifyRecPkt);
		
		if(len == sizeof(NotifyParentMsg))
		{		
			NotifyParentMsg* mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
			
			childID = call NotifyAMPacket.source(&radioNotifyRecPkt);
			children[COUNT][childID] = mr->count_value;
			children[SUM][childID] = mr->sum_value;
			children[MAX][childID] = mr->max_value; 
		}
		else
		{
			dbg("NotifyMsg","-NotifyRecT- Not a NotifyMsg.\n");
			return;
		}
	}
}
