/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;
   //uses interface Hashmap<pack> as neighborNodes;
   uses interface List<pack> as visited_listNodesList;
   uses interface List<int> as neighborNodes;
   uses interface Hashmap<int> as routingTable;
   uses interface List<NeighborStruct> as LinkStateList;
   //uses interface List<int> as LinkStateList;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
   uses interface Random as randomNumber;

   uses interface Timer<TMilli> as Timer0; //Interface that was wired above.}
   uses interface Timer<TMilli> as Timer1; //Interface that was wired above.}
}

implementation{
    /*NeighborStruct TopoGraph[500];*/
    pack sendPackage;
    uint16_t sequence_number = 1;
    // Prototypes
    void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t * payload, uint8_t length);

    event void Boot.booted() {
       call AMControl.start();

       dbg(GENERAL_CHANNEL, "Booted\n");
    }

    event void AMControl.startDone(error_t err) {
       int n;
       int x;
       int y;
       if (err == SUCCESS) {
          dbg(GENERAL_CHANNEL, "Radio On\n");
          n = (call randomNumber.rand16())%1000;
          x = (call randomNumber.rand16())%100;
          y = (call randomNumber.rand16())%20;
         // dbg(GENERAL_CHANNEL, "node %d : %d\n", TOS_NODE_ID, n);
          call Timer0.startPeriodicAt(y, 500000 + n);
          call Timer1.startPeriodicAt(x + 500, 500000+ x);
       } else {
          //Retry until successful
          call AMControl.start();
       }
    }

    event void AMControl.stopDone(error_t err) {}
    bool checkMessageSeen(pack * myMsg) {
       /**
        * checks to see if this node has seen this package
        * @type {[type]}
        */
       pack seenPack;
       bool seen = FALSE;
       int i = 0;
       for (i; i < (call visited_listNodesList.size()); i++) {
          seenPack = call visited_listNodesList.get(i);
          if (seenPack.src == myMsg -> src && seenPack.seq == myMsg -> seq) {

             seen = TRUE;
          }
       }
       return seen;
    }
    void pingForward(pack * myMsg) {
       /**
        * just forwards the packet since its not at the destination yet
        */
       myMsg -> TTL--;
       call visited_listNodesList.pushfront( * myMsg);
       if(call routingTable.contains(myMsg -> dest)){
           dbg(NEIGHBOR_CHANNEL, "I know how to get to %d so I will send through %d    %s\n", myMsg -> dest, call routingTable.get(myMsg -> dest), myMsg->payload);
           call Sender.send( * myMsg, call routingTable.get(myMsg -> dest));
       }
       else{
           dbg(NEIGHBOR_CHANNEL, "I dont know how to get to %d so flooding\n", myMsg -> dest);
           call Sender.send( * myMsg, AM_BROADCAST_ADDR);
       }
    }
    void receivedAndReply(pack * myMsg) {
       /**
        * recieves an init ping and sends a ping reply back to sender
        */
       dbg(GENERAL_CHANNEL, "Message Received at node %d: %s, sending Ping reply to %d\n", TOS_NODE_ID, myMsg -> payload, myMsg -> src);
       call visited_listNodesList.pushfront( * myMsg);
       makePack( & sendPackage, TOS_NODE_ID, myMsg -> src, 50, 1, sequence_number, "Ping reply :)", PACKET_MAX_PAYLOAD_SIZE);

       if(call routingTable.contains(myMsg -> src)){
           dbg(NEIGHBOR_CHANNEL, "I know how to get to %d so I will send through %d     %s\n", myMsg -> src, call routingTable.get(myMsg -> src), myMsg->payload);
           call Sender.send(sendPackage, call routingTable.get(myMsg -> src));
       }
       else{
           dbg(NEIGHBOR_CHANNEL, "I dont know how to get to %d so flooding\n", myMsg -> src);
           call Sender.send(sendPackage, AM_BROADCAST_ADDR);
       }
       sequence_number += 1;
    }

    void receivePingReply(pack * myMsg) {
       /**
        * function to recieve a ping reply -
        * basically just stores the packet in the list and maybe says somthing
        */
       dbg(GENERAL_CHANNEL, "got Ping reply from %d: %s\n\n", myMsg -> src, myMsg -> payload);
       call visited_listNodesList.pushfront( * myMsg);
    }
    void receiveAndForwardNeighbors(pack * myMsg){

        int size = call LinkStateList.size();
        int i = 0;
        int j = 0;
        bool seen = FALSE;

        for(i; i<size; i++){
            NeighborStruct stuff = call LinkStateList.get(i);
            if(stuff.src == myMsg->src && stuff.neighborNode == myMsg->payload[0]){

                seen = TRUE;
            }
        }
        if(!seen){
            NeighborStruct stuff;
            stuff.src = myMsg->src;
            stuff.neighborNode = myMsg->payload[0];
             //dbg(GENERAL_CHANNEL, "TTL is 0 :%d\n", myMsg->payload[0]);
            call LinkStateList.pushfront(stuff);
        }
        call visited_listNodesList.pushfront( * myMsg);
        //dbg(GENERAL_CHANNEL, "received this this %d\n\n", myMsg->payload[0]);
        call Sender.send(*myMsg, AM_BROADCAST_ADDR);



        //sequence_number += 1;
    }
    void handleNeighbor(pack * myMsg){
        /**
         * handles neighborDiscovery
         */
        if (myMsg->protocol == 0){
            //protocol is 0 so this is a neighbor recieving a request...send back a pingR
            call visited_listNodesList.pushfront( * myMsg);
            makePack( & sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, 1, sequence_number, "neighborDiscovery ping reply", PACKET_MAX_PAYLOAD_SIZE);
            call Sender.send(sendPackage, myMsg->src);
            sequence_number += 1;
        } else {
            //protocol 1 so this is a printR back from neighbor add to list
            bool seen = FALSE;
            int i = 0;
            call visited_listNodesList.pushfront( * myMsg);

            for (i; i < (call neighborNodes.size()); i++) {
               int node;
               node = call neighborNodes.get(i);
               if(node == myMsg->src){
                   seen = TRUE;
               }
            }
            if (!seen){
                call neighborNodes.pushfront(myMsg->src);
            }
        }
    }
    int calcMax(){
        int size = call LinkStateList.size();
        int i =0;
        int j = 0;
        int max_node = 0;
        for(i; i<size;i++){
            NeighborStruct stuff = call LinkStateList.get(i);
            if (stuff.src > max_node){
                max_node = stuff.src;
            }

        }
        return max_node;
    }
    void doDijkAlgo(){
        int size = call LinkStateList.size();
        int i =0;
        int j = 0;
        int next_hop;
        int max_node = calcMax();
        int cost_matrix[max_node][max_node], distance_to_node[max_node], pred_list[max_node];
        int visited_list[max_node], node_count, min_distance_to_node_to_node, nextnode;
        int start_node = TOS_NODE_ID-1;
        bool adjMatrix[max_node][max_node];
        for(i=0;i<max_node;i++){
            for(j=0;j<max_node;j++){
                adjMatrix[i][j] = FALSE;
            }
        }
        for(i=0; i<size;i++){
            NeighborStruct stuff = call LinkStateList.get(i);
            adjMatrix[stuff.src-1][stuff.neighborNode-1] = TRUE;
        }
        for(i=0;i<max_node;i++){
            for(j=0;j<max_node;j++){
                if (adjMatrix[i][j] == 0)
                    cost_matrix[i][j] = 999999;
                else
                    cost_matrix[i][j] = adjMatrix[i][j];
            }
        }
        //djsdjsdjsd algorithm
        for (i = 0; i < max_node; i++) {
            distance_to_node[i] = cost_matrix[start_node][i];
            pred_list[i] = start_node;
            visited_list[i] = 0;
        }
        distance_to_node[start_node] = 0;
        visited_list[start_node] = 1;
        node_count = 1;
        while (node_count < max_node - 1) {
            min_distance_to_node_to_node = 999999;
            for (i = 0; i < max_node; i++){
                if (distance_to_node[i] < min_distance_to_node_to_node && !visited_list[i]) {
                    min_distance_to_node_to_node = distance_to_node[i];
                    nextnode = i;
                }
            }
            visited_list[nextnode] = 1;
            for (i = 0; i < max_node; i++){
                if (!visited_list[i]){
                    if (min_distance_to_node_to_node + cost_matrix[nextnode][i] < distance_to_node[i]) {
                        distance_to_node[i] = min_distance_to_node_to_node + cost_matrix[nextnode][i];
                        pred_list[i] = nextnode;
                    }
                }
            }
            node_count++;
        }

        for (i = 0; i < max_node; i++){
            next_hop = TOS_NODE_ID-1;
            if (i != start_node) {
                //dbg(GENERAL_CHANNEL, "distance_to_node of %d = %d \n", i + 1, distance_to_node[i]);
                //dbg(GENERAL_CHANNEL, "Path = %d \n", i + 1);
                j = i;
                do {
                    if (j!=start_node){
                        next_hop = j+1;
                    }
                    j = pred_list[j];
                    //dbg(GENERAL_CHANNEL, "<- %d \n", j + 1);

                } while (j != start_node);
            }
            else{
                next_hop = start_node+1;
            }
            call routingTable.insert(i+1, next_hop);
        }

    }
    event message_t * Receive.receive(message_t * msg, void * payload, uint8_t len) {
        /**
         * receives a message and decides what to do with it
         */
       //dbg(GENERAL_CHANNEL, "Packet Received, sequenceNum: %d\n", last_sequence);
       if (len == sizeof(pack)) {
          pack * myMsg = (pack * ) payload; //idk some bs code that does stuff
          if (myMsg -> TTL > 0) {
             if (!checkMessageSeen(myMsg)) {
                //msg has not been seen yet decide what to do with it
                if (myMsg -> dest == AM_BROADCAST_ADDR){
                    //this is neighbor discovery
                    handleNeighbor(myMsg);
                    return msg;
                } else {
                    if (myMsg -> protocol == 2){
                        receiveAndForwardNeighbors(myMsg);
                        return msg;
                    }
                    else if (myMsg -> dest == TOS_NODE_ID) {
                       //msg has reached destination decide if it was a ping or PR
                       if (myMsg -> protocol == 0) {
                          //was an init ping so receive it and reply back -> flood back
                          receivedAndReply(myMsg);
                       } else if (myMsg -> protocol == 1) {
                          //was a ping reply. Do nothing -> idk say something
                          receivePingReply(myMsg);
                       }
                       return msg;
                    } else {
                       //msg is not a destination yet and has not been seen
                       //so ping it forward -> keep flooding
                       pingForward(myMsg);
                       return msg;
                    }
                }
             } else {
                 //message has already been seen, throw away
                 //Do nothing
                 return msg;
             }
          } else {
              //TTL is 0 do nothing return message
             dbg(GENERAL_CHANNEL, "TTL is 0 :%d\n", myMsg -> TTL);
             return msg;
          }
       } else {
           //idk why this would be a thing yet but yeah...do nothing return msg
          dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
          return msg;
       }
    }

    event void CommandHandler.ping(uint16_t destination, uint8_t * payload) {
       // periodicTimer.startPeriodic(1);
       dbg(GENERAL_CHANNEL, "PING EVENT \n\n");
       makePack( & sendPackage, TOS_NODE_ID, destination, 50, 0, sequence_number, payload, PACKET_MAX_PAYLOAD_SIZE);

       //dbg(GENERAL_CHANNEL, "%d : %d\n\n", TOS_NODE_ID, sequence_number);
       if(call routingTable.contains(destination)){
           dbg(NEIGHBOR_CHANNEL, "I know how to get to %d so I will send through %d    %s\n", destination, call routingTable.get(destination), payload);
           call Sender.send(sendPackage, call routingTable.get(destination));
       }
       else{
           dbg(NEIGHBOR_CHANNEL, "I dont know how to get to %d so flooding\n", destination);
           call Sender.send(sendPackage, AM_BROADCAST_ADDR);
       }
       sequence_number += 1;
    }

    event void CommandHandler.printNeighbors() {
       int i = 0;
       int j = 0;
       for (i; i < (call neighborNodes.size()); i++) {
          int node;
          node = call neighborNodes.get(i);
          dbg(NEIGHBOR_CHANNEL, "Neighboor of %d is %d\n", TOS_NODE_ID, node);
       }
       dbg(NEIGHBOR_CHANNEL, "finished neighboor dump for %d\n\n", TOS_NODE_ID);
       /*dbg(NEIGHBOR_CHANNEL, "All nodes for %d\n\n", TOS_NODE_ID);
       for (j; j < (call LinkStateList.size()); j++) {
          NeighborStruct neighborS = (call LinkStateList.get(j));
          dbg(NEIGHBOR_CHANNEL, "Neighboor of %d is %d\n", neighborS.src, neighborS.neighborNode);
       }
        dbg(NEIGHBOR_CHANNEL, "finished thing for %d\n\n", TOS_NODE_ID);*/

    }

    event void Timer0.fired() { //Do necessary task
        //dbg(GENERAL_CHANNEL, "firring\n");
       //dbg(NEIGHBOR_CHANNEL, "Timer fired : %d \n", TOS_NODE_ID);
       //dbg(GENERAL_CHANNEL, "Neighboor event \n");
       while(!(call neighborNodes.isEmpty())){
           call neighborNodes.popfront();
       }
       //dbg(GENERAL_CHANNEL, "this one fired");
       makePack( & sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, 0, sequence_number, "neighborDiscovery", PACKET_MAX_PAYLOAD_SIZE);

       call Sender.send(sendPackage, AM_BROADCAST_ADDR);
       sequence_number += 1;
    }

    event void Timer1.fired() { //Do necessary task

       //dbg(NEIGHBOR_CHANNEL, "Timer fired : %d \n", TOS_NODE_ID);
       //dbg(GENERAL_CHANNEL, "Neighboor event \n");
       /*while(!(call neighborNodes.isEmpty())){
           call neighborNodes.popfront();
       }*/

      int i = 0;
      int size = call neighborNodes.size();
      //dbg(GENERAL_CHANNEL, "this fired\n\n");
      for(i; i<size; i++){
          int node_arr[1];
          int node = call neighborNodes.get(i);
          node_arr[0] = node;
        //dbg(NEIGHBOR_CHANNEL, "Starting this1 %d\n\n", node);

          makePack( & sendPackage, TOS_NODE_ID, -5, 50, 2, sequence_number, node_arr, PACKET_MAX_PAYLOAD_SIZE);
        //dbg(NEIGHBOR_CHANNEL, "Starting this2\n\n");
           call Sender.send(sendPackage, AM_BROADCAST_ADDR);


           sequence_number+=1;
       }
       if ((call neighborNodes.size()) >=1){
           dbg(HASHMAP_CHANNEL, "");
           doDijkAlgo();
       }


    }

    event void CommandHandler.printRouteTable() {
        int i = 0;
        doDijkAlgo();
        for(i=0; i<call routingTable.size();i++){
            dbg(GENERAL_CHANNEL, "To get to node %d go to %d first\n", i+1, call routingTable.get(i+1));
        }
    }

    event void CommandHandler.printLinkState() {
        int i =0;
        dbg(NEIGHBOR_CHANNEL, "There are %d links\n",call LinkStateList.size());
        for(i;i<call LinkStateList.size(); i++){
            NeighborStruct stuff = call LinkStateList.get(i);
            dbg(NEIGHBOR_CHANNEL, "neighbor of %d is %d\n", stuff.src, stuff.neighborNode);
        }
    }

    event void CommandHandler.printdistance_to_nodeVector() {}

    event void CommandHandler.setTestServer() {}

    event void CommandHandler.setTestClient() {}

    event void CommandHandler.setAppServer() {}

    event void CommandHandler.setAppClient() {}

    void makePack(pack * Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t * payload, uint8_t length) {
       Package -> src = src;
       Package -> dest = dest;
       Package -> TTL = TTL;
       Package -> seq = seq;
       Package -> protocol = protocol;
       memcpy(Package -> payload, payload, length);
    }
}
