//
//  DialerTabView.swift
//  intercom
//
//  Created by James Conway on 24/11/2024.
//
import SwiftUI
import TwilioVoice
import CallKit
import AVFoundation
import AVFAudio
import PushKit

// Goes button -> check permissions -> call kit action -> provider? -> (TVO)CallDelegate

// TODO impl INStartAudioCallIntent for history calling

let keyCachedDeviceToken = "CachedDeviceToken"
let keyCachedBindingDate = "CachedBindingDate"

class DialerTabViewController: NSObject, ObservableObject, CallDelegate, CXProviderDelegate, PKPushRegistryDelegate, NotificationDelegate {
        
    let callKitCallController = CXCallController()
    let auth: Auth = .shared
    var callKitProvider: CXProvider?
    var audioDevice = DefaultAudioDevice()
    var activeCall: Call?
    var activeCallInvites: [String: CallInvite]! = [:]
    var callKitCompletionCallback: ((Bool) -> Void)? = nil
    var voipRegistry: PKPushRegistry?
            
    override init() {
        super.init()

        TwilioVoiceSDK.audioDevice = audioDevice
        let defaultLogger = TwilioVoiceSDK.logger
                if let params = LogParameters.init(module:TwilioVoiceSDK.LogModule.platform , logLevel: TwilioVoiceSDK.LogLevel.debug, message: "The default logger is used for app logs") {
                    defaultLogger.log(params: params)
                }
        let config = CXProviderConfiguration()
        config.maximumCallGroups = 2
        config.maximumCallsPerCallGroup = 1
        callKitProvider = CXProvider(configuration: config)
        if let provider = callKitProvider {
            provider.setDelegate(self, queue: nil)
        }
        
        // Configure push notifications
        self.voipRegistry = PKPushRegistry(queue: nil)
        self.voipRegistry!.delegate = self
        self.voipRegistry!.desiredPushTypes = [.voIP]
    }
    
    deinit {
        if let provider = callKitProvider {
            provider.invalidate()
        }
    }
    
    
    @Published
    var destination: String = ""
    @Published
    var number: String = ""
    
    // MARK: PKPushRegistryDelegate
    
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        // Handle credentials update
        
        let cachedDeviceToken = pushCredentials.token

        guard registrationRequired() || UserDefaults.standard.data(forKey: keyCachedDeviceToken) != cachedDeviceToken else {
            // No need to register
            return
        }
        
        TwilioVoiceSDK.register(accessToken: auth.phoneClientAccessToken!, deviceToken: cachedDeviceToken) { error in
            if let error {
                NSLog("error registering for push notifications: \(error.localizedDescription)")
            } else {
                NSLog("registered for push notifications successfully")
                
                // Store
                UserDefaults.standard.set(cachedDeviceToken, forKey: keyCachedDeviceToken)
                UserDefaults.standard.set(Date(), forKey: keyCachedBindingDate)
            }
        }
    }
    
    // Helper for credentials update
    func registrationRequired() -> Bool {
        guard let lastBindingCreated = UserDefaults.standard.object(forKey: keyCachedBindingDate) else {
            return true // need to register
        }
        
        let date = Date()
        var components = DateComponents()
        components.setValue(365/2, for: .day) // TTL is 365 days
        let expirationDate = Calendar.current.date(byAdding: components, to: lastBindingCreated as! Date)!
        
        if expirationDate.compare(date) == ComparisonResult.orderedDescending {
            return false // dont re register
        }
        
        // fallback - need to register
        return true
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        // Unregister on invalid credentials
        
        guard let deviceToken = UserDefaults.standard.data(forKey: keyCachedDeviceToken) else {
            return
        }
        
        TwilioVoiceSDK.unregister(accessToken: auth.phoneClientAccessToken!, deviceToken: deviceToken) { error in
            if let error = error {
                NSLog("Error unregistering push: \(error.localizedDescription)")
            } else {
                NSLog("Successfully unregistered push")
            }
        }
        
        // Remove invalid credentials
        UserDefaults.standard.removeObject(forKey: keyCachedBindingDate)
        UserDefaults.standard.removeObject(forKey: keyCachedDeviceToken)
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        NSLog("didReceiveIncomingPushWith:")
        
        // Handle incoming notification - use TwilioVoiceSDK
        // Will use main queue
        TwilioVoiceSDK.handleNotification(payload.dictionaryPayload, delegate: self, delegateQueue: nil)
        
        // I think we ignore the completion
    }
    
    // MARK: TVONotificationDelegate
    
    func callInviteReceived(callInvite: CallInvite) {
        NSLog("callInviteReceived:")
        
        // TTL is reset on push notification
        UserDefaults.standard.set(Date(), forKey: keyCachedBindingDate)
        
        let callerInfo: TVOCallerInfo = callInvite.callerInfo
        if let verified: NSNumber = callerInfo.verified {
            if verified.boolValue {
                NSLog("Call invite is from verified number")
            }
        }
        
        activeCallInvites[callInvite.uuid.uuidString] = callInvite
        // Reported to CK on invite not answer
        reportIncomingCall(from: callInvite.from!, uuid: callInvite.uuid)
    }
    
    func cancelledCallInviteReceived(cancelledCallInvite: CancelledCallInvite, error: any Error) {
        NSLog("cancelledCallInviteReceived:error:, error: \(error.localizedDescription)")
        
        guard let activeCallInvites, !activeCallInvites.isEmpty else { return }
        
        let callInvite = activeCallInvites.values.first {invite in invite.callSid == cancelledCallInvite.callSid}
        
        if let callInvite {
            performEndCallAction(uuid: callInvite.uuid)
            self.activeCallInvites.removeValue(forKey: callInvite.uuid.uuidString)
        }
    }
    
    // MARK: CXProviderDelegate
    
    func providerDidBegin(_ provider: CXProvider) {
        NSLog("providerDidBegin")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        NSLog("provider:performStartCallAction:")
                    
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        
        self.performVoiceCall(uuid: action.callUUID) { success in
            if success {
                NSLog("performVoiceCall() successful")
                provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
            } else {
                NSLog("performVoiceCall() failed")
            }
        }
        
        action.fulfill()
    }

  
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        NSLog("provider:didActivateAudioSession:")
        audioDevice.isEnabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        NSLog("provider:didDeactivateAudioSession:")
        audioDevice.isEnabled = false
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        NSLog("provider:timedOutPerformingAction:")
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        NSLog("provider:performEndCallAction:")
        // TODO: if the id matches an invite, reject it
        // Note that it is intentional that this doesn't call the CallKit performEndCallAction func
        if let call = activeCall {
            call.disconnect()
        } else {
            NSLog("Unknown UUID to perform end-call action with")
        }

        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        NSLog("provider:performAnswerCallAction:")
        
        self.performAnswerVoiceCall(uuid: action.callUUID) { success in
            if success {
                NSLog("performAnswerVoiceCall succeeded")
            } else {
                NSLog("performAnswerVoiceCall failed")
            }
        }
        
        action.fulfill()
    }
    
    func providerDidReset(_ provider: CXProvider) {
        NSLog("providerDidReset:")
        audioDevice.isEnabled = false
    }
    
    // TODO: provider for hold and mute
    
    // MARK: CallDelegate (Twilio)
    
    func callDidStartRinging(call: Call) {
        NSLog("callDidStartRinging:")
    }
    
    func callDidEnd(call: Call) {
        NSLog("callDidEnd:")
        // TODO: some more impl here after incoming works
    }
    
    func callDidConnect(call: Call) {
        NSLog("callDidConnect:")
        if let callKitCompletionCallback = callKitCompletionCallback {
            callKitCompletionCallback(true)
        }
        // todo still need to propogate some sort of ui update, probably a new view
        // and consider all of the delegate's handlers
    }
    
    func callDidReconnect(call: Call) {
        
    }
    
    func callDidDisconnect(call: Call, error: (any Error)?) {
        NSLog("callDidDisconnect:")
    }
    
    func callIsReconnecting(call: Call, error: any Error) {
        
    }
    
    func callDidFailToConnect(call: Call, error: any Error) {
        NSLog("callDidFailToConnect: \(error.localizedDescription)")
        if let completion = callKitCompletionCallback {
            completion(false)
        }
        
        if let provider = callKitProvider {
            provider.reportCall(with: call.uuid!, endedAt: Date(), reason: .failed)
        }
    }
    
    func callDidReceiveQualityWarnings(call: Call, currentWarnings: Set<NSNumber>, previousWarnings: Set<NSNumber>) {
        
    }
    
    // MARK: CallKit Actions

    // Start and report outgoing call
    func performStartCallAction(uuid: UUID, handle: String) {
        NSLog("performing start call action: \(uuid)")
        guard let provider = callKitProvider else {
            NSLog("CallKit provider not available")
            return
        }
        
        let callHandle = CXHandle(type: .generic, value: handle)
        let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
        let transaction = CXTransaction(action: startCallAction)

        callKitCallController.request(transaction) { error in
            if let error = error {
                NSLog("StartCallAction transaction request failed: \(error.localizedDescription)")
                return
            }

            NSLog("StartCallAction transaction request successful")

            let callUpdate = CXCallUpdate()
            
            callUpdate.remoteHandle = callHandle
            callUpdate.supportsDTMF = true
            callUpdate.supportsHolding = true
            callUpdate.supportsGrouping = false
            callUpdate.supportsUngrouping = false
            callUpdate.hasVideo = false

            provider.reportCall(with: uuid, updated: callUpdate)
        }
    }
    
    func reportIncomingCall(from: String, uuid: UUID) {
        NSLog("reporting incoming call: \(uuid)")
        guard let provider = callKitProvider else {
            NSLog("CallKit provider not available")
            return
        }
        
        let callHandle = CXHandle(type: .phoneNumber, value: from)
        let callUpdate = CXCallUpdate()
        
        callUpdate.remoteHandle = callHandle
        callUpdate.supportsDTMF = true
        callUpdate.supportsHolding = true
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = false
        
        provider.reportNewIncomingCall(with: uuid, update: callUpdate) { error in
            if let error {
                NSLog("Error reporting incoming call: \(error.localizedDescription)")
            } else {
                NSLog("Incoming call reported successfully")
            }
        }
    }
    
    func performEndCallAction(uuid: UUID) {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        callKitCallController.request(transaction) { error in
            if let error {
                NSLog("Error performing end call action: \(error.localizedDescription)")
            } else {
                NSLog("End call action performed successfully")
            }
        }
    }
        
    func performVoiceCall(uuid: UUID, completionHandler: @escaping (Bool) -> Void) {
        NSLog("performVoiceCall:")
        let connectOptions = ConnectOptions(accessToken: auth.phoneClientAccessToken!) { builder in
            builder.uuid = uuid
            builder.params = [
                "destination": self.destination,
                "number": self.number
            ]
        }
        
        let call = TwilioVoiceSDK.connect(options: connectOptions, delegate: self);
        
        NSLog("made call: \(call)", call)

        activeCall = call
        callKitCompletionCallback = completionHandler
        
    }
    
    func performAnswerVoiceCall(uuid: UUID, completionHandler: @escaping (Bool) -> Void) {
        // Check we have an invite
        guard let callInvite = activeCallInvites[uuid.uuidString] else {
            NSLog("Tried to accept non-existent call invite")
            return
        }
        
        let acceptOptions = AcceptOptions(callInvite: callInvite) { builder in
            builder.uuid = callInvite.uuid
        }
        
        let call = callInvite.accept(options: acceptOptions, delegate: self)
        activeCall = call
        callKitCompletionCallback = completionHandler
        activeCallInvites.removeValue(forKey: uuid.uuidString)
    }
    
    func checkRecordPermission(_ completion: @escaping (_ permissionGranted: Bool) -> Void) {
        AVAudioApplication.requestRecordPermission() { granted in
            completion(granted)
        }
    }

    func call() {
        print("calling \(destination)")

        // To save duplicated, and potentially conflicting logic, the rest of the number validation occurs on the backend
        if number == "" {
            NSLog("identity is empty")
            return
        }
        
        if destination == "" {
            NSLog("number is empty")
            return
        }
        
        checkRecordPermission { permissionGranted in
            guard !permissionGranted else {
                let uuid = UUID()
                
                self.performStartCallAction(uuid: uuid, handle: self.destination)
                return
            }
        }
    }
}

// TODO extract MVVC oe
struct DialerTabView: View {
    
    @ObservedObject var viewController = DialerTabViewController()
    
    var body: some View {
        KeyPadView(destination: $viewController.destination, number: $viewController.number, call: viewController.call)
    }
}


#Preview {
    DialerTabView()
}
