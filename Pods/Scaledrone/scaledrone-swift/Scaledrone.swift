import Starscream

public protocol ScaledroneDelegate: class {
    func scaledroneDidConnect(scaledrone: Scaledrone, error: NSError?)
    func scaledroneDidReceiveError(scaledrone: Scaledrone, error: NSError?)
    func scaledroneDidDisconnect(scaledrone: Scaledrone, error: NSError?)
}

public protocol ScaledroneAuthenticateDelegate: class {
    func scaledroneDidAuthenticate(scaledrone: Scaledrone, error: NSError?)
}

public protocol ScaledroneRoomDelegate: class {
    func scaledroneRoomDidConnect(room: ScaledroneRoom, error: NSError?)
    func scaledroneRoomDidReceiveMessage(room: ScaledroneRoom, message: Any, member: ScaledroneMember?)
}

public protocol ScaledroneObservableRoomDelegate: class {
    func scaledroneObservableRoomDidConnect(room: ScaledroneRoom, members: [ScaledroneMember])
    func scaledroneObservableRoomMemberDidJoin(room: ScaledroneRoom, member: ScaledroneMember)
    func scaledroneObservableRoomMemberDidLeave(room: ScaledroneRoom, member: ScaledroneMember)
}

public class Scaledrone: WebSocketDelegate {
    
    private typealias Callback = ([String:Any]) -> Void
    
    private let socket:WebSocket
    private var callbacks:[Int:Callback] = [:]
    private var callbackId:Int = 0
    private var rooms:[String:ScaledroneRoom] = [:]
    private let channelID:String
    private var data:Any?
    public var clientID:String = ""
    
    public weak var delegate: ScaledroneDelegate?
    public weak var authenticateDelegate: ScaledroneAuthenticateDelegate?
    
    public init(channelID: String, url: String? = "wss://api.scaledrone.com/v3/websocket", data: Any?) {
        self.channelID = channelID
        self.data = data
        socket = WebSocket(url: URL(string: url!)!)
    }
    
    private func createCallback(fn: @escaping Callback) -> Int {
        callbackId += 1
        callbacks[callbackId] = fn
        return callbackId
    }
    
    public func connect() {
        socket.delegate = self
        socket.connect()
    }
    
    public func authenticate(jwt: String) {
        let msg = [
            "type": "authenticate",
            "token": jwt,
            "callback": createCallback(fn: { data in
                self.authenticateDelegate?.scaledroneDidAuthenticate(scaledrone: self, error: data["error"] as? NSError)
            })
            ] as [String : Any]
        self.send(msg)
    }
    
    public func publish(message: Any, room: String) {
        let msg = [
            "type": "publish",
            "room": room,
            "message": message,
            ] as [String : Any]
        self.send(msg)
    }
    
    // MARK: Websocket Delegate Methods.
    
    public func websocketDidConnect(socket: WebSocket) {
        var msg = [
            "type": "handshake",
            "channel": self.channelID,
            "callback": createCallback(fn: { data in
                self.clientID = data["client_id"] as! String
                self.delegate?.scaledroneDidConnect(scaledrone: self, error: data["error"] as? NSError)
            })
        ] as [String : Any]
        if (self.data != nil) {
            msg["client_data"] = self.data
        }
        self.send(msg)
    }
    
    public func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        delegate?.scaledroneDidDisconnect(scaledrone: self, error: error)
    }
    
    public func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        var dic = convertJSONMessageToDictionary(text: text)
        
        if let error = dic["error"] as? String {
            dic["error"] = NSError(domain: "scaledrone.com", code: 0, userInfo: ["error": error])
        }
        
        if let cb = dic["callback"] as? Int {
            if let fn = callbacks[cb] as Callback! {
                fn(dic)
            }
            return
        }
        
        if let error = dic["error"] as? NSError {
            delegate?.scaledroneDidReceiveError(scaledrone: self, error: error)
            return
        }
        
        
        if let type = dic["type"] as? String {
            if let roomName = dic["room"] as? String {
                if let room = rooms[roomName] as ScaledroneRoom? {
                    switch type {
                    case "publish":
                        var member:ScaledroneMember?
                        if let clientID = dic["client_id"] as? String {
                            member = room.members.first(where: {$0.id == clientID})
                        }
                        room.delegate?.scaledroneRoomDidReceiveMessage(room: room, message: dic["message"] as Any, member: member)
                    case "observable_members":
                        let members = convertAnyToMembers(any: dic["data"])
                        room.members = members
                        room.observableDelegate?.scaledroneObservableRoomDidConnect(room: room, members: members)
                    case "observable_member_join":
                        let member = convertAnyToMember(any: dic["data"])
                        room.members.append(member)
                        room.observableDelegate?.scaledroneObservableRoomMemberDidJoin(room: room, member: member)
                    case "observable_member_leave":
                        let member = convertAnyToMember(any: dic["data"])
                        room.members = room.members.filter { $0.id != member.id }
                        room.observableDelegate?.scaledroneObservableRoomMemberDidLeave(room: room, member: member)
                    default: break
                        
                    }
                }
            }
        }
    }
    
    public func websocketDidReceiveData(socket: WebSocket, data: Data) {
        print("Should not have received any data: \(data.count)")
    }
    
    private func send(_ value: Any) {
        guard JSONSerialization.isValidJSONObject(value) else {
            print("[WEBSOCKET] Value is not a valid JSON object.\n \(value)")
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [])
            socket.write(data: data)
        } catch let error {
            print("[WEBSOCKET] Error serializing JSON:\n\(error)")
        }
    }
    
    public func subscribe(roomName: String) -> ScaledroneRoom {
        let room = ScaledroneRoom(name: roomName, scaledrone: self)
        rooms[roomName] = room
        
        let msg = [
            "type": "subscribe",
            "room": roomName,
            "callback": createCallback(fn: { data in
                room.delegate?.scaledroneRoomDidConnect(room: room, error: nil)
            })
            ] as [String : Any]
        self.send(msg)
        
        return room
    }
    
    public func disconnect() {
        socket.disconnect()
    }
    
}

public class ScaledroneRoom {
    
    public let name:String
    public let scaledrone:Scaledrone
    public var members: [ScaledroneMember]
    
    public weak var delegate: ScaledroneRoomDelegate?
    public weak var observableDelegate: ScaledroneObservableRoomDelegate?
    
    init(name: String, scaledrone: Scaledrone) {
        self.name = name
        self.scaledrone = scaledrone
        self.members = []
    }
    
    public func publish(message: Any) {
        scaledrone.publish(message: message, room: self.name)
    }
    
}

public class ScaledroneMember {
    public let id:String
    public let authData:Any?
    public let clientData:Any?
    
    init(id: String, authData: Any?, clientData: Any?) {
        self.id = id
        self.authData = authData
        self.clientData = clientData
    }
    
    public var description: String {
        return "Member: \(id) authData: \(authData) clientData: \(clientData)"
    }
}

func convertJSONMessageToDictionary(text: String) -> [String: Any] {
    if let message = text.data(using: .utf8) {
        do {
            var json = try JSONSerialization.jsonObject(with: message, options: []) as! [String: Any]
            if let data = json["data"] as? [[String: Any]] {
                json["data"] = data
            }
            return json
        } catch {
            print(error.localizedDescription)
        }
    }
    return [:]
}

func convertAnyToMember(any: Any?) -> ScaledroneMember {
    let dic = any as! [String : Any]
    return ScaledroneMember(id: dic["id"] as! String, authData: dic["authData"], clientData: dic["clientData"])
}

func convertAnyToMembers(any: Any?) -> [ScaledroneMember] {
    let list = any as! [Any]
    return list.map({
        (value: Any) -> ScaledroneMember in return convertAnyToMember(any: value)
    })
}
