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

// I think we're close but need to move to viewcontroller class
// Goes button -> check permissions -> call kit action -> provider? -> (TVO)CallDelegate

// temp
let accessToken = ""

class DialerTabViewController: NSObject, ObservableObject, CallDelegate, CXProviderDelegate {
        
    let callKitCallController = CXCallController()
    var callKitProvider: CXProvider?
    var audioDevice = DefaultAudioDevice()
    var activeCall: Call?
    var callKitCompletionCallback: ((Bool) -> Void)? = nil
    
    override init() {
        super.init()
        TwilioVoiceSDK.audioDevice = audioDevice
        let defaultLogger = TwilioVoiceSDK.logger
                if let params = LogParameters.init(module:TwilioVoiceSDK.LogModule.platform , logLevel: TwilioVoiceSDK.LogLevel.debug, message: "The default logger is used for app logs") {
                    defaultLogger.log(params: params)
                }
        let config = CXProviderConfiguration(localizedName: "Intercom")
        config.maximumCallGroups = 2
        config.maximumCallsPerCallGroup = 1
        callKitProvider = CXProvider(configuration: config)
        if let provider = callKitProvider {
            provider.setDelegate(self, queue: nil)
        }
    }
    
    deinit {
        if let provider = callKitProvider {
            provider.invalidate()
        }
    }
    
    
    @Published
    var number: String = ""
    
    // CXProviderDelegate
    
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
        
        if let call = activeCall {
            call.disconnect()
        } else {
            NSLog("Unknown UUID to perform end-call action with")
        }

        action.fulfill()
    }
    
    
    func providerDidReset(_ provider: CXProvider) {
        // todo twilio reauth
        NSLog("providerDidReset:")
    }
    
    // CallDelegate (Twilio)
    func callDidStartRinging(call: Call) {
        NSLog("callDidStartRinging:")
    }
    
    func callDidEnd(call: Call) {
        NSLog("callDidEnd:")
    
    }
    
    func callDidConnect(call: Call) {
        NSLog("callDidConnect:")
        if let callKitCompletionCallback = callKitCompletionCallback {
            callKitCompletionCallback(true)
        }
        // todo still need to propogate some sort of ui update, probably a new view
    }
    
    func callDidReconnect(call: Call) {
        
    }
    
    func callDidDisconnect(call: Call, error: (any Error)?) {
        
    }
    
    func callIsReconnecting(call: Call, error: any Error) {
        
    }
    
    func callDidFailToConnect(call: Call, error: any Error) {
        if let completion = callKitCompletionCallback {
            completion(false)
        }
        
        if let provider = callKitProvider {
            provider.reportCall(with: call.uuid!, endedAt: Date(), reason: .failed)
        }
    }
    
    func callDidReceiveQualityWarnings(call: Call, currentWarnings: Set<NSNumber>, previousWarnings: Set<NSNumber>) {
        
    }

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
    
    func performVoiceCall(uuid: UUID, completionHandler: @escaping (Bool) -> Void) {
        NSLog("performVoiceCall:")
        let connectOptions = ConnectOptions(accessToken: accessToken) { builder in
            builder.uuid = uuid
            builder.params = ["to": self.number]
        }
        
        let call = TwilioVoiceSDK.connect(options: connectOptions, delegate: self);
        
        NSLog("made call: \(call)", call)

        activeCall = call
        callKitCompletionCallback = completionHandler
        
    }
    
    func checkRecordPermission(_ completion: @escaping (_ permissionGranted: Bool) -> Void) {
        // todo fix deprecated avfoundation usage
        let permissionStatus = AVAudioSession.sharedInstance().recordPermission
        
        switch permissionStatus {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }

    func call() {
        print("calling \(number)")
        
        checkRecordPermission { permissionGranted in
            
            guard !permissionGranted else {
                let uuid = UUID()
                
                self.performStartCallAction(uuid: uuid, handle: "(name of remote shown)")
                return
            }
            
            
            // show microphone request - check latest docs seems to do auto with it in plist
        }
    }
}

// TODO extract MVVC oe
struct DialerTabView: View {
    
    @ObservedObject var viewController = DialerTabViewController()
    
    
    var body: some View {
        
        KeyPadView(number: $viewController.number, call: viewController.call)
    }
}


#Preview {
    DialerTabView()
}
