#include "SimpleRoutingTree.h"

module SRTreeC
{
	uses interface Boot;
	uses interface SplitControl as RadioControl;
#ifdef SERIAL_EN
	uses interface SplitControl as SerialControl;
#endif

	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	uses interface Packet as RoutingPacket;
	
	uses interface AMSend as NotifyAMSend;
	uses interface AMPacket as NotifyAMPacket;
	uses interface Packet as NotifyPacket;

#ifdef SERIAL_EN
	uses interface AMSend as SerialAMSend;
	uses interface AMPacket as SerialAMPacket;
	uses interface Packet as SerialPacket;
#endif
	uses interface Timer<TMilli> as EpochTimer;
	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as LostTaskTimer;
	//uses interface Timer<TMilli> as DelayTimer;
	
	uses interface Receive as RoutingReceive;
	uses interface Receive as NotifyReceive;
	uses interface Receive as SerialReceive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	uses interface PacketQueue as NotifySendQueue;
	uses interface PacketQueue as NotifyReceiveQueue;
}
implementation
{
	uint16_t  roundCounter;
	
	message_t radioRoutingSendPkt;
	message_t radioNotifySendPkt;
	
	
	message_t serialPkt;
	//message_t serialRecPkt;
	
	bool RoutingSendBusy=FALSE;
	bool NotifySendBusy=FALSE;

#ifdef SERIAL_EN
	bool serialBusy=FALSE;
#endif
	
	bool lostRoutingSendTask=FALSE;
	bool lostNotifySendTask=FALSE;
	bool lostRoutingRecTask=FALSE;
	bool lostNotifyRecTask=FALSE;
	
	uint8_t curdepth;
	uint8_t parentID;
	uint8_t children[1][MAX_NODES];
	uint8_t send_values[1];
	
	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();
	

/*_________________________________________________
				UTILITY FUNCTIONS
___________________________________________________*/
	
	void setLostRoutingSendTask(bool state)
	{
		atomic{lostRoutingSendTask=state;}
#ifdef DBG_MSG
		dbg("SRTreeC","-F- lostRoutingSendTask = %s\n", (state == TRUE)?"TRUE":"FALSE");
#endif
	}
	
	void setLostNotifySendTask(bool state)
	{
		atomic{lostNotifySendTask=state;}
#ifdef DBG_MSG
		dbg("SRTreeC","-F- lostNotifySendTask = %s\n", (state == TRUE)?"TRUE":"FALSE");
#endif
	}
	
	void setLostNotifyRecTask(bool state)
	{
		atomic{lostNotifyRecTask=state;}
#ifdef DBG_MSG
		dbg("SRTreeC","-F- lostNotifyRecTask = %s\n", (state == TRUE)?"TRUE":"FALSE");
#endif
	}
	
	void setLostRoutingRecTask(bool state)
	{
		atomic{lostRoutingRecTask=state;}
#ifdef DBG_MSG
		dbg("SRTreeC","-F- lostRoutingRecTask = %s\n", (state == TRUE)?"TRUE":"FALSE");
#endif
	}

//==========================
	void setRoutingSendBusy(bool state)
	{
		atomic{RoutingSendBusy=state;}
#ifdef DBG_MSG
		dbg("SRTreeC","-F- RoutingRadio is %s\n", (state == TRUE)?"Busy":"Free");
#endif
	}
	
	void setNotifySendBusy(bool state)
	{
		atomic{NotifySendBusy=state;}
#ifdef DBG_MSG
		dbg("SRTreeC","-F- NotifyRadio is %s\n", (state == TRUE)?"Busy":"Free");
#endif
	}
#ifdef SERIAL_EN
	void setSerialBusy(bool state)
	{
		serialBusy=state;
#ifdef DBG_MSG
		dbg("SRTreeC","-F- SerialRadio is %s\n", (state == TRUE)?"Busy":"Free");
#endif
	}
#endif

/*_________________________________________________
				EVENT HANDLERS
___________________________________________________*/
	
	event void Boot.booted()
	{
		//RADIO INIT
		call RadioControl.start();
		

		//SIGNALS INIT
		setRoutingSendBusy(FALSE);
		setNotifySendBusy(FALSE);
#ifdef SERIAL_EN
		setSerialBusy(FALSE);
#endif
		//EPOCH INIT
		roundCounter = 0;
		

		//SERIAL INIT
		if(TOS_NODE_ID==0)
		{
#ifdef SERIAL_EN
			call SerialControl.start();
#endif
			curdepth=0;
			parentID=0;
			send_values[COUNT] = 1;
#ifdef DBG_MSG
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d ,check_sum= %d\n", curdepth , parentID, send_values[COUNT]);
#endif
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			send_values[COUNT] = 1;
#ifdef DBG_MSG
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d ,check_sum= %d\n", curdepth , parentID, send_values[COUNT]);
#endif
		}
	}
	
	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
#ifdef DBG_MSG
			dbg("Radio" ,"-RadioE- Radio initialized successfully.\n");
#endif			
			//existing comments
			//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//call RoutingMsgTimer.startPeriodic(TIMER_PERIOD_MILLI);
			

			//Radio Init (200ms)
			if (TOS_NODE_ID==0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		}
		else
		{
#ifdef DBG_MSG
			dbg("Radio" , "-RadioE- Radio initialization failed! Retrying...\n");
#endif
			call RadioControl.start();
		}
	}
	
	event void RadioControl.stopDone(error_t err)
	{ 
#ifdef DBG_MSG
		dbg("Radio", "-RadioE- Radio stopped!\n");
#endif
	}

	event void SerialControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
#ifdef DBG_MSG
			dbg("Serial" , "-SerialE- Serial initialized successfully! \n");
#endif
		}
		else
		{
#ifdef DBG_MSG
			dbg("Serial" , "-SerialE- Serial initialization failed! Retrying... \n");
#endif
			call SerialControl.start();
		}
	}

	event void SerialControl.stopDone(error_t err)
	{
#ifdef DBG_MSG
		dbg("Serial", "-SerialE- Serial stopped! \n");
#endif
	}
	
	event void LostTaskTimer.fired()
	{
#ifdef DBG_MSG
		dbg("SRTreeC","_________________> LostTaskTimer fired!\n");
#endif
		if (lostRoutingSendTask)
		{
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}
		
		if (lostNotifySendTask)
		{
			post sendNotifyTask();
			setLostNotifySendTask(FALSE);
		}
		
		if (lostRoutingRecTask)
		{
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}
		
		if (lostNotifyRecTask)
		{
			post receiveNotifyTask();
			setLostNotifyRecTask(FALSE);
		}
	}
	
	

	event void EpochTimer.fired()
	{
		
		NotifyParentMsg* m;
		message_t tmp;
		uint8_t iter = 0;
		
		if(TOS_NODE_ID==0)
		{
			for(iter=0;iter<MAX_NODES;iter++)
				send_values[COUNT] += children[COUNT][iter];
			roundCounter += 1;
			dbg("SRTreeC", "\n_____________________EPOCH___%u_______chksum=%d__________\n\n", roundCounter,send_values[COUNT]);
		}
		else
		{
			m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
			m->send_values[COUNT]=send_values[COUNT];
			for(iter=0;iter<MAX_NODES;iter++)
				m->send_values[COUNT] += children[COUNT][iter];
			
#ifdef DBG_MSG
			dbg("SRTreeC" , "-EpochTimer.fired- Node: %d, check_sum: %d\n", TOS_NODE_ID,send_values[COUNT]);
#endif
			call NotifyAMPacket.setDestination(&tmp, parentID);
			call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
					
			if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
			{
				if (call NotifySendQueue.size() == 1)
				{	
					//dbg("SRTreeC", "-NotifySendE- SendNotifyTask() posted.\n");
					post sendNotifyTask();
				}
			}
		}
		send_values[COUNT] = 1;
		
	}


	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		
		//dbg("SRTreeC", "-TimerFiredE- RoutingMsgTimer fired!  RoutingRadio is %s \n",(RoutingSendBusy)?"Busy":"Free");
		
		if(call RoutingSendQueue.full())
		{
#ifdef DBG_MSG
			dbg("SRTreeC", "-TimerFiredE- RoutingSendQueue is full.\n");
#endif
			return;
		}
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-TimerFiredE- No valid payload.\n");
#endif
			return;
		}
		atomic{
			//mrpkt->senderID=TOS_NODE_ID;
			mrpkt->depth = curdepth;
		}
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		enqueueDone = call RoutingSendQueue.enqueue(tmp);
#ifdef DBG_MSG
		dbg("SRTreeC" , "-TimerFiredE- Broadcasting RoutingMsg\n");
#endif
		if( enqueueDone==SUCCESS )
		{
			//edw exei ena 8ema h eftichia
			if (call RoutingSendQueue.size()==1)
			{
				//dbg("SRTreeC", "-TimerFiredE- SendRoutingTask() posted!\n");
				post sendRoutingTask();
			}
		}
		else
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-TimerFiredE- Msg failed to be enqueued in RoutingSendQueue.");
#endif
		}		
	}


// DATA Packets Handling

	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		//dbg("SRTreeC", "-RoutingSendE- A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");	
		setRoutingSendBusy(FALSE);

		if(!(call RoutingSendQueue.empty()))
		{
			//dbg("SRTreeC", "-RoutingSendE- sendRoutingTask() posted!\n");
			post sendRoutingTask();
		}

	}
	
	event void NotifyAMSend.sendDone(message_t *msg , error_t err)
	{
		setNotifySendBusy(FALSE);
		
		if(!(call NotifySendQueue.empty()))
		{
			//dbg("SRTreeC", "-NotifySendE- sendNotifyTask() posted!\n");
			post sendNotifyTask();
		}
	}
	
	event void SerialAMSend.sendDone(message_t* msg , error_t err)
	{
		if ( &serialPkt == msg)
		{
			//dbg("Serial" , "Serial Package sent %s \n", (err==SUCCESS)?"True":"False");
			setSerialBusy(FALSE);
		}
	}
	


	event message_t* NotifyReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource = call NotifyAMPacket.source(msg);
#ifdef DBG_MSG
		dbg("SRTreeC", "-NotifyRecE- check_sum: %u, Source: %u \n",((NotifyParentMsg*) payload)->send_values[COUNT], msource);
#endif
		atomic
		{
			memcpy(&tmp,msg,sizeof(message_t)); //tmp = *(message_t*)msg;
		}
		enqueueDone = call NotifyReceiveQueue.enqueue(tmp);
#ifdef DBG_MSG
		dbg("SRTreeC", "NotifyReceiveQueue Size: %d\n",call NotifyReceiveQueue.size());
#endif
		if( enqueueDone== SUCCESS)
		{
			//dbg("SRTreeC", "-NotifyRecE- receiveNotifyTask() posted!\n");
			post receiveNotifyTask();
		}
		else
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-NotifyRecE- Msg failed to be enqueued in NotifyReceiveQueue.");	
#endif	
		}
		return msg;
	}


	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);

		if(curdepth > (((RoutingMsg*) payload)->depth))
		{
			//dbg("SRTreeC", "-RoutingRecE- SenderID: %u, Source: %u\n",((RoutingMsg*) payload)->senderID ,  msource);

			atomic{
				memcpy(&tmp,msg,sizeof(message_t)); //tmp=*(message_t*)msg;
			}
			enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
			if(enqueueDone == SUCCESS)
			{
				//dbg("SRTreeC", "-RoutingRecE- receiveRoutingTask() posted!\n");
				post receiveRoutingTask();
			}
			else
			{
#ifdef DBG_MSG
				dbg("SRTreeC","-RoutingRecE- Msg failed to be enqueued in RoutingReceiveQueue.");		
#endif		
			}

		}
		return msg;

	}
	
	event message_t* SerialReceive.receive(message_t* msg , void* payload , uint8_t len)
	{
#ifdef DBG_MSG
		// when receiving from serial port
		dbg("Serial","Received msg from serial port \n");
#endif
		return msg;
	}
	

/*_________________________________________________
				TASK IMPLEMENTATIONS
___________________________________________________*/
	
	task void sendRoutingTask()
	{
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		//message_t radioRoutingSendPkt;
		
		if (call RoutingSendQueue.empty())
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-RoutingSendT- Queue is empty.\n");
#endif
			return;
		}
		if(RoutingSendBusy)
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-RoutingSendT- RoutingRadio is Busy.\n");
#endif
			setLostRoutingSendTask(TRUE);
			call LostTaskTimer.startOneShot(SEND_CHECK_MILLIS);
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);

		if(mlen!=sizeof(RoutingMsg))
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-RoutingSendT- Unknown message. \n");
#endif
			return;
		}

		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			//dbg("SRTreeC","-RoutingSendT- Send was successfull\n");
			setRoutingSendBusy(TRUE);
		}
		else
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-RoutingSendT- Send failed!\n");
#endif
		}

		if(TOS_NODE_ID==0)
		{
			call EpochTimer.startPeriodicAt(EPOCH_MILLI/(curdepth+1),EPOCH_MILLI);
		}	
	}

	task void sendNotifyTask()
	{
		uint8_t mlen;
		error_t sendDone;
		uint16_t mdest;
		NotifyParentMsg* mpayload;
		//message_t radioNotifySendPkt;

		if (call NotifySendQueue.empty())
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-NotifySendT- Queue is empty.\n");
#endif
			return;
		}
		
		if(NotifySendBusy==TRUE)
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-NotifySendT- NotifyRadio is Busy.\n");
#endif
			setLostNotifySendTask(TRUE);
			call LostTaskTimer.startOneShot(SEND_CHECK_MILLIS);
			return;
		}
		
		radioNotifySendPkt = call NotifySendQueue.dequeue();
		mlen=call NotifyPacket.payloadLength(&radioNotifySendPkt);
		mpayload= call NotifyPacket.getPayload(&radioNotifySendPkt,mlen);
		
		if(mlen!= sizeof(NotifyParentMsg))
		{
#ifdef DBG_MSG
			dbg("SRTreeC", "-NotifySendT- Unknown message.\n");
#endif
			return;
		}
		
		mdest= call NotifyAMPacket.destination(&radioNotifySendPkt);
		
		sendDone=call NotifyAMSend.send(mdest,&radioNotifySendPkt, mlen);
		
		if ( sendDone== SUCCESS)
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-NotifySendT- Send was successfull.\n");
#endif
			setNotifySendBusy(TRUE);
		}
		else
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-NotifySendT- Send failed.\n");
#endif
		}
	}
	


	task void receiveRoutingTask()
	{
		//message_t tmp;
		uint8_t len;
		message_t radioRoutingRecPkt;
		
		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		
		//if received msg is RoutingMsg		
		if(len == sizeof(RoutingMsg))
		{
			//NotifyParentMsg* m;
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			
			//dbg("SRTreeC" , "-RoutingRecT- senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);
			
			// set Parent and depth
			parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);
			curdepth= mpkt->depth + 1;

			call EpochTimer.startPeriodicAt((EPOCH_MILLI/(curdepth+1))-TOS_NODE_ID*20,EPOCH_MILLI);

			//boradcasting to posible children
			call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
		}
		else // received msg is not RoutingMsg
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-RoutingRecT- Not a RoutingMsg.\n");
#endif
			setLostRoutingRecTask(TRUE);
			call LostTaskTimer.startOneShot(SEND_CHECK_MILLIS);
			return;
		}
		
	}

	task void receiveNotifyTask()
	{
		//message_t tmp;
		uint8_t len;
		message_t radioNotifyRecPkt;
		uint8_t childID;



		radioNotifyRecPkt= call NotifyReceiveQueue.dequeue();

		len= call NotifyPacket.payloadLength(&radioNotifyRecPkt);
		
		if(len == sizeof(NotifyParentMsg))
		{		
			NotifyParentMsg* mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
			
			childID = call NotifyAMPacket.source(&radioNotifyRecPkt);
			children[COUNT][childID] = mr->send_values[COUNT];

#ifdef DBG_MSG
				dbg("SRTreeC" , "___________________________________________________\n");
				dbg("SRTreeC" , "old_sum: %d\n",send_values[COUNT]);
				dbg("SRTreeC" , "+%d \n", mr->send_values[COUNT]);
#endif				
				//send_values[COUNT] = mr->send_values[COUNT];
#ifdef DBG_MSG
				dbg("SRTreeC" , "new_sum: %d\n" , send_values[COUNT]);
				dbg("SRTreeC" , "___________________________________________________\n");
#endif
				
		}
		else
		{
#ifdef DBG_MSG
			dbg("SRTreeC","-NotifyRecT- Not a NotifyMsg.\n");
#endif
			setLostNotifyRecTask(TRUE);
			call LostTaskTimer.startOneShot(SEND_CHECK_MILLIS);
			return;
		}
		
	}
	
}
