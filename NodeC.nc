/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node, RandomC;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    components new TimerMilliC() as Timer0; //create a new timer with alias “myTimerC”
    components new TimerMilliC() as Timer1; //create a new timer with alias “myTimerC”

    Node -> MainC.Boot;


    //Node.Boot ->MainC.Boot;
    Node.Timer0 -> Timer0; //Wire the interface to the component
    Node.Timer1 -> Timer1; //Wire the interface to the component
    Node.randomNumber -> RandomC;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    /*components new HashmapC(pack, 300) as HashmapC;
    Node.neighborNodes -> HashmapC;*/

    components new ListC(pack, 300) as ListC;
    Node.visitedNodesList -> ListC;

    components new ListC(NeighborStruct, 300) as ListC_3;
    Node.LinkStateList -> ListC_3;

    components new ListC(int, 300) as ListC_2;
    Node.neighborNodes -> ListC_2;

    components new HashmapC(int, 300) as HashmapC_1;
    Node.routingTable -> HashmapC_1;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

}
