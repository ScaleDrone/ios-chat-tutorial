//
//  ChatService.swift
//  ScaledroneChatTest
//
//  Created by Marin Benčević on 08/09/2018.
//  Copyright © 2018 Scaledrone. All rights reserved.
//

import Foundation
import Scaledrone

class ChatService {
  
  private let scaledrone: Scaledrone
  private let messageCallback: (Message)-> Void
  
  private var room: ScaledroneRoom?
  
  init(member: Member, onRecievedMessage: @escaping (Message)-> Void) {
    self.messageCallback = onRecievedMessage
//    #error("Make sure to input your channel ID and delete this line.")
    self.scaledrone = Scaledrone(
      channelID: "YOUR-CHANNEL-ID",
      data: member.toJSON)
    scaledrone.delegate = self
  }
  
  func connect() {
    scaledrone.connect()
  }
  
  func sendMessage(_ message: String) {
    room?.publish(message: message)
  }
  
}

extension ChatService: ScaledroneDelegate {
  
  func scaledroneDidConnect(scaledrone: Scaledrone, error: NSError?) {
    print("Connected to Scaledrone")
    room = scaledrone.subscribe(roomName: "observable-room")
    room?.delegate = self
  }
  
  func scaledroneDidReceiveError(scaledrone: Scaledrone, error: NSError?) {
    print("Scaledrone error", error ?? "")
  }
  
  func scaledroneDidDisconnect(scaledrone: Scaledrone, error: NSError?) {
    print("Scaledrone disconnected", error ?? "")
  }
  
}

extension ChatService: ScaledroneRoomDelegate {
  
  func scaledroneRoomDidConnect(room: ScaledroneRoom, error: NSError?) {
    print("Connected to room!")
  }
  
  func scaledroneRoomDidReceiveMessage(
    room: ScaledroneRoom,
    message: Any,
    member: ScaledroneMember?) {
    
    guard
      let text = message as? String,
      let memberData = member?.clientData,
      let member = Member(fromJSON: memberData)
      else {
        print("Could not parse data.")
        return
    }
    
    let message = Message(
      member: member,
      text: text,
      messageId: UUID().uuidString)
    messageCallback(message)
  }
}

