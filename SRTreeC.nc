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
		dbg("SRTreeC","-F- RoutingSendBusy = %s\n", (state == TRUE)?"TRUE":"FALSE");
	}
	
	void setNotifySendBusy(bool state)
	{
		atomic{NotifySendBusy=state;}
		dbg("SRTreeC","-F- NotifySendBusy = %s\n", (state == TRUE)?"TRUE":"FALSE");
		
	}
#ifdef SERIAL_EN
	void setSerialBusy(bool state)
	{
		serialBusy=state;
		dbg("SRTreeC","-F- SerialSendBusy = %s\n", (state == TRUE)?"TRUE":"FALSE");
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
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			dbg("Boot", "-BootE- curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
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
			//call LostTaskTimer.startPeriodic(SEND_CHECK_MILLIS);

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
		if (lostRoutingSendTask)
		{
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}
		
		if( lostNotifySendTask)
		{
			post sendNotifyTask();
			setLostNotifySendTask(FALSE);
		}
		
		if (lostRoutingRecTask)
		{
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}
		
		if ( lostNotifyRecTask)
		{
			post receiveNotifyTask();
			setLostNotifyRecTask(FALSE);
		}
	}
	
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		dbg("SRTreeC", "-RoutingSendE- RoutingMsgTimer fired!  RoutingRadio is %s \n",(RoutingSendBusy)?"Busy":"Free");
		
		if (TOS_NODE_ID==0)
		{
			roundCounter += 1;
		
			dbg("SRTreeC", "\n_____________________EPOCH___%u___________________\n\n", roundCounter);
			
			//Start Epoch Timer (60 sec ~ 61440ms)
			call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
		}
		


		if(call RoutingSendQueue.full())
		{
			dbg("SRTreeC", "-RoutingSendE- RoutingSendQueue is full.\n");
			return;
		}
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			dbg("SRTreeC","-RoutingSendE- No valid payload.\n");
			return;
		}
		atomic{
			mrpkt->senderID=TOS_NODE_ID;
			mrpkt->depth = curdepth;
		}
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		enqueueDone = call RoutingSendQueue.enqueue(tmp);
		
		dbg("SRTreeC" , "-RoutingSendE- Broadcasting RoutingMsg\n");
		if( enqueueDone==SUCCESS )
		{
			if (call RoutingSendQueue.size()==1)
			{
				dbg("SRTreeC", "-RoutingSendE- SendRoutingTask() posted!\n");
				post sendRoutingTask();
			}
		}
		else
		{
			dbg("SRTreeC","-RoutingSendE- Msg failed to be enqueued in RoutingSendQueue.");
		}		
	}


// DATA Packets Handling

	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");	
		setRoutingSendBusy(FALSE);
		
		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();
		}

	}
	
	event void NotifyAMSend.sendDone(message_t *msg , error_t err)
	{
		dbg("SRTreeC", "A Notify package sent... %s \n",(err==SUCCESS)?"True":"False");	
		setNotifySendBusy(FALSE);
		
		if(!(call NotifySendQueue.empty()))
		{
			post sendNotifyTask();
		}
	}
	
	event void SerialAMSend.sendDone(message_t* msg , error_t err)
	{
		if ( &serialPkt == msg)
		{
			dbg("Serial" , "Serial Package sent %s \n", (err==SUCCESS)?"True":"False");
			setSerialBusy(FALSE);
		}
	}
	


	event message_t* NotifyReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource = call NotifyAMPacket.source(msg);
		
		dbg("SRTreeC", "-NotifyRecE- Sender: %u, Source: %u \n",((NotifyParentMsg*) payload)->senderID, msource);

		//existing comments
		//if(len!=sizeof(NotifyParentMsg))
		//{
			//dbg("SRTreeC","\t\tUnknown message received!!!\n");
			//return msg;
		//}
	
		atomic
		{
			memcpy(&tmp,msg,sizeof(message_t)); //tmp = *(message_t*)msg;
		}
		enqueueDone = call NotifyReceiveQueue.enqueue(tmp);
		
		if( enqueueDone== SUCCESS)
		{
			dbg("SRTreeC", "-NotifyRecE- receiveNotifyTask() posted!\n");
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
		
		dbg("SRTreeC", "-RoutingRecE- Sender: %u, Source: %u\n",((RoutingMsg*) payload)->senderID ,  msource);

		//if(len!=sizeof(RoutingMsg))
		//{
			//dbg("SRTreeC","\t\tUnknown message received!!!\n");
			//return msg;
		//}
		
		atomic{
			memcpy(&tmp,msg,sizeof(message_t)); //tmp=*(message_t*)msg;
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			dbg("SRTreeC", "-RoutingRecE- receiveRoutingTask() posted!\n");
			post receiveRoutingTask();
		}
		else
		{
			dbg("SRTreeC","-RoutingRecE- Msg failed to be enqueued in RoutingReceiveQueue.");				
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
			dbg("SRTreeC","-RoutingSendT- RoutingRadio is Busy.\n");
			setLostRoutingSendTask(TRUE);
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
			dbg("SRTreeC","-RoutingSendT- Send was successfull\n");
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","-RoutingSendT- Send failed!\n");
		}
	}

	task void sendNotifyTask()
	{
		//skip!!!!!
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
			dbg("SRTreeC","-NotifySendT- NotifyRadio is Busy.\n");
			setLostNotifySendTask(TRUE);
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
		message_t tmp;
		uint8_t len;
		message_t radioRoutingRecPkt;
		
		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);
		// processing of radioRecPkt
		
		// pos tha xexorizo ta 2 diaforetika minimata???
				
		if(len == sizeof(RoutingMsg))
		{
			NotifyParentMsg* m;
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			
			//if(TOS_NODE_ID >0)
			//{
				//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//}
			//
			
			dbg("SRTreeC" , "receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);
			if ( (parentID<0)||(parentID>=65535))
			{
				// tote den exei akoma patera
				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q
				curdepth= mpkt->depth + 1;

				// tha stelnei kai ena minima NotifyParentMsg ston patera
				
				m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				m->senderID=TOS_NODE_ID;
				m->depth = curdepth;
				m->parentID = parentID;
				dbg("SRTreeC" , "receiveRoutingTask():NotifyParentMsg sending to node= %d... \n", parentID);
				call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
				
				if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
				{
					dbg("SRTreeC", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!");

					if (call NotifySendQueue.size() == 1)
					{
						post sendNotifyTask();
					}
				}
				if (TOS_NODE_ID!=0)
				{
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				}
			}
			else //if node has valid parent
			{
				
				if (( curdepth > mpkt->depth +1) || (mpkt->senderID==parentID))
				{
					uint16_t oldparentID = parentID;
					
				
					parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;
					curdepth = mpkt->depth + 1;
									
									
					
					dbg("SRTreeC" , "NotifyParentMsg sending to node= %d... \n", oldparentID);
					if ( (oldparentID<65535) || (oldparentID>0) || (oldparentID==parentID))
					{
						m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
						m->senderID=TOS_NODE_ID;
						m->depth = curdepth;
						m->parentID = parentID;
						
						call NotifyAMPacket.setDestination(&tmp,oldparentID);
						//call NotifyAMPacket.setType(&tmp,AM_NOTIFYPARENTMSG);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
								
						if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
						{
							dbg("SRTreeC", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");

							if (call NotifySendQueue.size() == 1)
							{
								post sendNotifyTask();
							}
						}
					}
					if (TOS_NODE_ID!=0)
					{
						call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
					}
					// tha stelnei kai ena minima NotifyParentMsg 
					// ston kainourio patera kai ston palio patera.
					
					if (oldparentID!=parentID)
					{
						m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
						m->senderID=TOS_NODE_ID;
						m->depth = curdepth;
						m->parentID = parentID;
						dbg("SRTreeC" , "receiveRoutingTask():NotifyParentMsg sending to node= %d... \n", parentID);
						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
						
						if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
						{
							dbg("SRTreeC", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!! \n");

							if (call NotifySendQueue.size() == 1)
							{
								post sendNotifyTask();
							}
						}
					}
				}
				
				
			}
		}
		else //not routing message
		{
			dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");

			setLostRoutingRecTask(TRUE);
			return;
		}
		
	}

	 
	task void receiveNotifyTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioNotifyRecPkt;
		
		radioNotifyRecPkt= call NotifyReceiveQueue.dequeue();
		
		len= call NotifyPacket.payloadLength(&radioNotifyRecPkt);
		
		dbg("SRTreeC","ReceiveNotifyTask(): len=%u \n",len);

		if(len == sizeof(NotifyParentMsg))
		{
			// an to parentID== TOS_NODE_ID tote
			// tha proothei to minima pros tin riza xoris broadcast
			// kai tha ananeonei ton tyxon pinaka paidion..
			// allios tha diagrafei to paidi apo ton pinaka paidion
			
			NotifyParentMsg* mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
			
			dbg("SRTreeC" , "NotifyParentMsg received from %d !!! \n", mr->senderID);

			if ( mr->parentID == TOS_NODE_ID)
			{
				// tote prosthiki stin lista ton paidion.
				
			}
			else
			{
				// apla diagrafei ton komvo apo paidi tou..
				
			}
			if ( TOS_NODE_ID==0)
			{
#ifdef SERIAL_EN
				if (!serialBusy)
				{ // mipos mporei na mpei san task?
					NotifyParentMsg * m = (NotifyParentMsg *) (call SerialPacket.getPayload(&serialPkt, sizeof(NotifyParentMsg)));
					m->senderID=mr->senderID;
					m->depth = mr->depth;
					m->parentID = mr->parentID;
					dbg("Serial", "Sending NotifyParentMsg to PC... \n");
					if (call SerialAMSend.send(parentID, &serialPkt, sizeof(NotifyParentMsg))==SUCCESS)
					{
						setSerialBusy(TRUE);
					}
				}
#endif
			}
			else
			{
				NotifyParentMsg* m;
				memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
				
				m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				//m->senderID=mr->senderID;
				//m->depth = mr->depth;
				//m->parentID = mr->parentID;
				
				dbg("SRTreeC" , "Forwarding NotifyParentMsg from senderID= %d  to parentID=%d \n" , m->senderID, parentID);

				call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
				
				if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
				{
					dbg("SRTreeC", "receiveNotifyTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");
					if (call NotifySendQueue.size() == 1)
					{
						post sendNotifyTask();
					}
				}

				
			}
			
		}
		else
		{
			dbg("SRTreeC","receiveNotifyTask():Empty message!!! \n");
			setLostNotifyRecTask(TRUE);
			return;
		}
		
	}
	
}
