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
	uses interface Timer<TMilli> as DelayTimer;
	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as LostTaskTimer;
	
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
	uint16_t parentID;
	uint16_t check_sum;
	
	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();
	

/*_________________________________________________
				UTILITY FUNCTIONS
___________________________________________________*/
	
//=============================== YPOPSHFIA PROS APOXWRHSH	
	void setLostRoutingSendTask(bool state)
	{
		atomic{lostRoutingSendTask=state;}
		dbg("SRTreeC","-F- lostRoutingSendTask = %s\n", (state == TRUE)?"TRUE":"FALSE");
	}
	
	void setLostNotifySendTask(bool state)
	{
		atomic{lostNotifySendTask=state;}
		dbg("SRTreeC","-F- lostNotifySendTask = %s\n", (state == TRUE)?"TRUE":"FALSE");
	}
	
	void setLostNotifyRecTask(bool state)
	{
		atomic{lostNotifyRecTask=state;}
		dbg("SRTreeC","-F- lostNotifyRecTask = %s\n", (state == TRUE)?"TRUE":"FALSE");
	}
	
	void setLostRoutingRecTask(bool state)
	{
		atomic{lostRoutingRecTask=state;}
		dbg("SRTreeC","-F- lostRoutingRecTask = %s\n", (state == TRUE)?"TRUE":"FALSE");
	}

//==========================
	void setRoutingSendBusy(bool state)
	{
		atomic{RoutingSendBusy=state;}
		dbg("SRTreeC","-F- RoutingRadio is %s\n", (state == TRUE)?"Busy":"Free");
	}
	
	void setNotifySendBusy(bool state)
	{
		atomic{NotifySendBusy=state;}
		dbg("SRTreeC","-F- NotifyRadio is %s\n", (state == TRUE)?"Busy":"Free");
		
	}
#ifdef SERIAL_EN
	void setSerialBusy(bool state)
	{
		serialBusy=state;
		dbg("SRTreeC","-F- SerialRadio is %s\n", (state == TRUE)?"Busy":"Free");
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
			check_sum = 1;
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d ,check_sum= %d\n", curdepth , parentID, check_sum);
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			check_sum = 1;
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d ,check_sum= %d\n", curdepth , parentID, check_sum);
		}
	}
	
	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			dbg("Radio" ,"-RadioE- Radio initialized successfully.\n");
			
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
			dbg("Radio" , "-RadioE- Radio initialization failed! Retrying...\n");
			call RadioControl.start();
		}
	}
	
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "-RadioE- Radio stopped!\n");
	}

	event void SerialControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			dbg("Serial" , "-SerialE- Serial initialized successfully! \n");
		}
		else
		{
			dbg("Serial" , "-SerialE- Serial initialization failed! Retrying... \n");
			call SerialControl.start();
		}
	}

	event void SerialControl.stopDone(error_t err)
	{
		dbg("Serial", "-SerialE- Serial stopped! \n");
	}
	
	event void LostTaskTimer.fired()
	{
		dbg("SRTreeC","_________________> LostTaskTimer fired! task: ");
		if (lostRoutingSendTask)
		{
			dbg("SRTreeC","sendRouting\n");
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}
		
		if (lostNotifySendTask)
		{
			dbg("SRTreeC","sendNotify\n");
			post sendNotifyTask();
			setLostNotifySendTask(FALSE);
		}
		
		if (lostRoutingRecTask)
		{
			dbg("SRTreeC","receiveRouting\n");
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}
		
		if (lostNotifyRecTask)
		{
			dbg("SRTreeC","receiveNotify\n");
			post receiveNotifyTask();
			setLostNotifyRecTask(FALSE);
		}
	}
	
	event void DelayTimer.fired()
	{
		call EpochTimer.startPeriodic(EPOCH_MILLI);
	}

	event void EpochTimer.fired()
	{

		

		NotifyParentMsg* m;
		message_t tmp;
		
		

		m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
		m->check_sum = check_sum;
		dbg("SRTreeC" , "-EpochTimer.fired- Node: %d, check_sum: %d\n", TOS_NODE_ID,check_sum);
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

		check_sum = 1;
		
	}


	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		
		//dbg("SRTreeC", "-TimerFiredE- RoutingMsgTimer fired!  RoutingRadio is %s \n",(RoutingSendBusy)?"Busy":"Free");
		
		if(call RoutingSendQueue.full())
		{
			dbg("SRTreeC", "-TimerFiredE- RoutingSendQueue is full.\n");
			return;
		}
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			dbg("SRTreeC","-TimerFiredE- No valid payload.\n");
			return;
		}
		atomic{
			mrpkt->senderID=TOS_NODE_ID;
			mrpkt->depth = curdepth;
		}
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		enqueueDone = call RoutingSendQueue.enqueue(tmp);
		
		dbg("SRTreeC" , "-TimerFiredE- Broadcasting RoutingMsg\n");
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
			dbg("SRTreeC","-TimerFiredE- Msg failed to be enqueued in RoutingSendQueue.");
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
		
		dbg("SRTreeC", "-NotifyRecE- check_sum: %u, Source: %u \n",((NotifyParentMsg*) payload)->check_sum, msource);

		atomic
		{
			memcpy(&tmp,msg,sizeof(message_t)); //tmp = *(message_t*)msg;
		}
		enqueueDone = call NotifyReceiveQueue.enqueue(tmp);
		
		dbg("SRTreeC", "NotifyReceiveQueue Size: %d\n",call NotifyReceiveQueue.size());
		if( enqueueDone== SUCCESS)
		{
			//dbg("SRTreeC", "-NotifyRecE- receiveNotifyTask() posted!\n");
			post receiveNotifyTask();
		}
		else
		{
			dbg("SRTreeC","-NotifyRecE- Msg failed to be enqueued in NotifyReceiveQueue.");		
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
				dbg("SRTreeC","-RoutingRecE- Msg failed to be enqueued in RoutingReceiveQueue.");				
			}

		}
		return msg;

	}
	
	event message_t* SerialReceive.receive(message_t* msg , void* payload , uint8_t len)
	{
		// when receiving from serial port
		dbg("Serial","Received msg from serial port \n");
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
			dbg("SRTreeC","-RoutingSendT- Queue is empty.\n");
			return;
		}
		if(RoutingSendBusy)
		{
			dbg("SRTreeC","_--------------------------------------------1\n");
			dbg("SRTreeC","-RoutingSendT- RoutingRadio is Busy.\n");
			setLostRoutingSendTask(TRUE);
			call LostTaskTimer.startOneShot(SEND_CHECK_MILLIS);
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);

		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("SRTreeC","-RoutingSendT- Unknown message. \n");
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
			dbg("SRTreeC","-RoutingSendT- Send failed!\n");
		}

		call DelayTimer.startOneShot(EPOCH_MILLI/(curdepth+1));
		dbg("SRTreeC","DelayTimer Started for NODE: %d, time: %d\n",TOS_NODE_ID,(EPOCH_MILLI/(curdepth+1)));
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
			dbg("SRTreeC","-NotifySendT- Queue is empty.\n");
			return;
		}
		
		if(NotifySendBusy==TRUE)
		{
			dbg("SRTreeC","_-------------------------------------------2\n");
			dbg("SRTreeC","-NotifySendT- NotifyRadio is Busy.\n");
			setLostNotifySendTask(TRUE);
			call LostTaskTimer.startOneShot(SEND_CHECK_MILLIS);
			return;
		}
		
		radioNotifySendPkt = call NotifySendQueue.dequeue();
		mlen=call NotifyPacket.payloadLength(&radioNotifySendPkt);
		mpayload= call NotifyPacket.getPayload(&radioNotifySendPkt,mlen);
		
		if(mlen!= sizeof(NotifyParentMsg))
		{
			dbg("SRTreeC", "-NotifySendT- Unknown message.\n");
			return;
		}
		
		mdest= call NotifyAMPacket.destination(&radioNotifySendPkt);
		
		sendDone=call NotifyAMSend.send(mdest,&radioNotifySendPkt, mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","-NotifySendT- Send was successfull.\n");
			setNotifySendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","-NotifySendT- Send failed.\n");
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

			//call DelayTimer.startOneShot(EPOCH_MILLI/(curdepth+1));

			//boradcasting to posible children
			call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
		}
		else // received msg is not RoutingMsg
		{
			dbg("SRTreeC","_-------------------------------------------3\n");
			dbg("SRTreeC","-RoutingRecT- Not a RoutingMsg.\n");
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
		



		radioNotifyRecPkt= call NotifyReceiveQueue.dequeue();

		len= call NotifyPacket.payloadLength(&radioNotifyRecPkt);
		
		if(len == sizeof(NotifyParentMsg))
		{		
			NotifyParentMsg* mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
			
			//dbg("SRTreeC" , "-NotifyRecT- check_sum: %d.\n", mr->check_sum);

			

			//if ( TOS_NODE_ID==0)
			//{
#ifdef SERIAL_EN
				/*if (!serialBusy)
				{ // mipos mporei na mpei san task?
					NotifyParentMsg * m = (NotifyParentMsg *) (call SerialPacket.getPayload(&serialPkt, sizeof(NotifyParentMsg)));
					m->senderID=mr->senderID;
					m->depth = mr->depth;
					m->parentID = mr->parentID;
					dbg("Serial", "-NotifyRecT- Serial Sending to PC... \n");
					if (call SerialAMSend.send(parentID, &serialPkt, sizeof(NotifyParentMsg))==SUCCESS)
					{
						setSerialBusy(TRUE);
					}
				}*/
#endif
			//}
			//else
			//{
				//NotifyParentMsg* m;
				//memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
				
				//m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				dbg("SRTreeC" , "___________________________________________________\n");
				dbg("SRTreeC" , "-NotifyRecT- Forwarding Msg from %d to %d\n" , TOS_NODE_ID, parentID);
				dbg("SRTreeC" , "old_sum: %d\n",check_sum);
				dbg("SRTreeC" , "+%d \n", mr->check_sum);
				check_sum = check_sum +mr->check_sum;
				dbg("SRTreeC" , "new_sum: %d\n" , check_sum);
				dbg("SRTreeC" , "___________________________________________________\n");

				/*call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
				
				if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
				{
					if (call NotifySendQueue.size() == 1)
					{
						//dbg("SRTreeC", "-NotifyRecT- SendNotifyTask() posted.\n");
						//post sendNotifyTask();
					}
				}*/
			//}
		}
		else
		{
			dbg("SRTreeC","_--------------------------------------------4\n");
			dbg("SRTreeC","-NotifyRecT- Not a NotifyMsg.\n");
			setLostNotifyRecTask(TRUE);
			call LostTaskTimer.startOneShot(SEND_CHECK_MILLIS);
			return;
		}

		if(TOS_NODE_ID==0)
		{
			roundCounter += 1;
			dbg("SRTreeC", "\n_____________________EPOCH___%u_______chksum=%d__________\n\n", roundCounter,check_sum);
		}
		
	}
	
}
