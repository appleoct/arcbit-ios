//
//  AppDelegate.swift
//  ArcBit
//
//  Created by Timothy Lee on 3/14/15.
//  Copyright (c) 2015 Timothy Lee <stequald01@gmail.com>
//
//   This library is free software; you can redistribute it and/or
//   modify it under the terms of the GNU Lesser General Public
//   License as published by the Free Software Foundation; either
//   version 2.1 of the License, or (at your option) any later version.
//
//   This library is distributed in the hope that it will be useful,
//   but WITHOUT ANY WARRANTY; without even the implied warranty of
//   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
//   Lesser General Public License for more details.
//
//   You should have received a copy of the GNU Lesser General Public
//   License along with this library; if not, write to the Free Software
//   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
//   MA 02110-1301  USA

import Foundation
import UIKit
import AVFoundation
import Fabric
import Crashlytics

@UIApplicationMain
@objc(AppDelegate) class AppDelegate: UIResponder, UIApplicationDelegate, LTHPasscodeViewControllerDelegate {
    
    let MAX_CONSECUTIVE_FAILED_STEALTH_CHALLENGE_COUNT = 8
    let SAVE_WALLET_PAYLOAD_DELAY = 2.0
    let DEFAULT_BLOCKEXPLORER_API = TLBlockExplorer.blockchain
    let RESPOND_TO_STEALTH_PAYMENT_GET_TX_TRIES_MAX_TRIES = 3

    var window:UIWindow?
    fileprivate var storyboard:UIStoryboard?
    fileprivate var modalDelegate:AnyObject?
    lazy var appWallet = TLWallet(walletName: "App Wallet", walletConfig: TLWalletConfig(isTestnet: false))
    var bitcoinURIOptionsDict:NSDictionary?
    var justSetupHDWallet = false
    var giveExitAppNoticeForBlockExplorerAPIToTakeEffect = false
    var saveWalletJSONEnabled = true
    var consecutiveFailedStealthChallengeCount = 0
    fileprivate var savedPasscodeViewDefaultBackgroundColor: UIColor?
    fileprivate var savedPasscodeViewDefaultLabelTextColor: UIColor?
    fileprivate var savedPasscodeViewDefaultPasscodeTextColor: UIColor?
    fileprivate var hasFinishLaunching = false
    fileprivate var respondToStealthPaymentGetTxTries = 0
    var scannedEncryptedPrivateKey:String? = nil
    var scannedAddressBookAddress:String? = nil
    let pendingOperations = PendingOperations()
    lazy var webSocketNotifiedTxHashSet:NSMutableSet = NSMutableSet()
    var pendingSelfStealthPaymentTxid: String? = nil
    lazy var txFeeAPI = TLTxFeeAPI();

    class func instance() -> AppDelegate {
        return UIApplication.shared.delegate as! (AppDelegate)
    }
    
    func showLockViewForEnteringPasscode(_ notification: Notification) {
        if !hasFinishLaunching && LTHPasscodeViewController.doesPasscodeExist() {
            //LTHPasscodeViewController.sharedUser().maxNumberOfAllowedFailedAttempts = 0
            UIApplication.shared.isStatusBarHidden = true
            LTHPasscodeViewController.sharedUser().delegate = self
            LTHPasscodeViewController.sharedUser().showLockScreen(withAnimation: false,
                withLogout:false                                                         ,
                andLogoutTitle:nil)
        }
        
        hasFinishLaunching = true
    }
    
    func recoverHDWallet(_ mnemonic: String, shouldRefreshApp: Bool = true) {
        if shouldRefreshApp {
            refreshApp(mnemonic)
        } else {
            let masterHex = TLHDWalletWrapper.getMasterHex(mnemonic)
            appWallet.createInitialWalletPayload(mnemonic, masterHex:masterHex)
            TLCoinWalletsManager.instance().setupCoinWallets(self.appWallet)
        }
        TLCoinWalletsManager.instance().recoverHDWallet()
    }
    
    // work around to show SendView
    func checkToShowSendViewWithURL(_ notification: Notification) {
        if bitcoinURIOptionsDict != nil {
            assert(window?.rootViewController is ECSlidingViewController, "rootViewController != ECSlidingViewController")
            let vc = window?.rootViewController as! ECSlidingViewController
            vc.topViewController.showSendView()
        }
    }
    
    func setSettingsPasscodeViewColors() {
        LTHPasscodeViewController.sharedUser().view.backgroundColor = savedPasscodeViewDefaultBackgroundColor
        
        LTHPasscodeViewController.sharedUser().failedAttemptLabel.textColor = savedPasscodeViewDefaultLabelTextColor
        LTHPasscodeViewController.sharedUser().enterPasscodeLabel.textColor = savedPasscodeViewDefaultLabelTextColor
        LTHPasscodeViewController.sharedUser().okButton.setTitleColor(savedPasscodeViewDefaultLabelTextColor, for:UIControlState())
        
        LTHPasscodeViewController.sharedUser().firstDigitTextField.textColor = savedPasscodeViewDefaultPasscodeTextColor
        LTHPasscodeViewController.sharedUser().secondDigitTextField.textColor = savedPasscodeViewDefaultPasscodeTextColor
        LTHPasscodeViewController.sharedUser().thirdDigitTextField.textColor = savedPasscodeViewDefaultPasscodeTextColor
        LTHPasscodeViewController.sharedUser().fourthDigitTextField.textColor = savedPasscodeViewDefaultPasscodeTextColor
    }
    
    fileprivate func setupPasscodeViewColors() {
        savedPasscodeViewDefaultBackgroundColor = LTHPasscodeViewController.sharedUser().backgroundColor
        savedPasscodeViewDefaultLabelTextColor = LTHPasscodeViewController.sharedUser().labelTextColor
        savedPasscodeViewDefaultPasscodeTextColor = LTHPasscodeViewController.sharedUser().passcodeTextColor
        
        LTHPasscodeViewController.sharedUser().backgroundColor = TLColors.mainAppColor()
        LTHPasscodeViewController.sharedUser().labelTextColor = TLColors.mainAppOppositeColor()
        LTHPasscodeViewController.sharedUser().passcodeTextColor = TLColors.mainAppOppositeColor()
        
        LTHPasscodeViewController.sharedUser().navigationBarTintColor = TLColors.mainAppColor()
        LTHPasscodeViewController.sharedUser().navigationTintColor = TLColors.mainAppOppositeColor()
        LTHPasscodeViewController.sharedUser().navigationTitleColor = TLColors.mainAppOppositeColor()
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        Fabric.with([Crashlytics.self])
        
        AFNetworkActivityIndicatorManager.shared().isEnabled = true

        window?.backgroundColor = TLColors.mainAppColor()
        application.statusBarStyle = UIStatusBarStyle.lightContent
        
        justSetupHDWallet = false
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
        if TLPreferences.getInstallDate() == nil {
            
            // before version 1.4.0, install date was not getting set properly, this fixes things
            if TLPreferences.getAppVersion() == "0" {
                TLPreferences.setHasSetupHDWallet(false)
                TLPreferences.setInstallDate()
                DLog("set InstallDate \(TLPreferences.getInstallDate())")
                TLPreferences.setAppVersion(appVersion)
            } else {
                TLPreferences.setInstallDate()
                DLog("set fake InstallDate \(TLPreferences.getInstallDate())")
                if appVersion != TLPreferences.getAppVersion() {
                    TLUpdateAppData.instance().beforeUpdatedAppVersion = TLPreferences.getAppVersion()
                    DLog("set new appVersion \(appVersion)")
                    TLPreferences.setAppVersion(appVersion)
                    TLPreferences.setDisabledPromptRateApp(false)
                }
            }
            
        } else if appVersion != TLPreferences.getAppVersion() {
            TLUpdateAppData.instance().beforeUpdatedAppVersion = TLPreferences.getAppVersion()
            DLog("set new appVersion \(appVersion)")
            TLPreferences.setAppVersion(appVersion)
            TLPreferences.setDisabledPromptRateApp(false)
        }
        
        self.setupPasscodeViewColors()
        
        if (TLPreferences.hasSetupHDWallet() && UIApplication.instancesRespond(to: "registerUserNotificationSettings"))
        {
            application.registerUserNotificationSettings(UIUserNotificationSettings(types: [.alert, .badge, .sound], categories:nil))
        }
        
        NotificationCenter.default.addObserver(self, selector:#selector(AppDelegate.checkToShowSendViewWithURL(_:)), name:NSNotification.Name.UIApplicationDidBecomeActive, object:nil)
        
        // condition is used so that I dont prompt user to setup notifactions when just installed app
        if (TLPreferences.hasSetupHDWallet()) {
            //setUpLocalNotification()
        }
        
        hasFinishLaunching = false
        
        NotificationCenter.default.addObserver(self, selector:#selector(AppDelegate.showLockViewForEnteringPasscode(_:)), name:NSNotification.Name(rawValue: TLNotificationEvents.EVENT_SEND_SCREEN_LOADING()), object:nil)
        
        return true
    }
    
    func refreshApp(_ passphrase: String, clearWalletInMemory: Bool = true) {
        if (TLPreferences.getCloudBackupWalletFileName() == nil) {
            TLPreferences.setCloudBackupWalletFileName()
        }

        TLPreferences.deleteWalletPassphrase()
        TLPreferences.deleteEncryptedWalletJSONPassphrase()
        
        TLPreferences.setWalletPassphrase(passphrase, useKeychain: true)
        TLPreferences.setEncryptedWalletJSONPassphrase(passphrase, useKeychain: true)
        TLPreferences.clearEncryptedWalletPassphraseKey()

        TLPreferences.setCanRestoreDeletedApp(true)
        TLPreferences.setInAppSettingsCanRestoreDeletedApp(true)
        
        TLPreferences.setEnableBackupWithiCloud(false)
        TLPreferences.setInAppSettingsKitEnableBackupWithiCloud(false)
        
        TLPreferences.setInAppSettingsKitEnabledDynamicFee(true)
        TLPreferences.setInAppSettingsKitDynamicFeeSettingIdx(TLDynamicFeeSetting.FastestFee);
        TLPreferences.setInAppSettingsKitTransactionFee(TLWalletUtils.DEFAULT_FEE_AMOUNT_IN_BITCOINS())
        TLPreferences.setEnablePINCode(false)
        TLSuggestions.instance().enabledAllSuggestions()
        TLPreferences.resetBlockExplorerAPIURL()
        
        TLPreferences.setBlockExplorerAPI(String(format:"%ld", DEFAULT_BLOCKEXPLORER_API.rawValue))
        TLPreferences.setInAppSettingsKitBlockExplorerAPI(String(format:"%ld", DEFAULT_BLOCKEXPLORER_API.rawValue))
        
        TLPreferences.resetStealthExplorerAPIURL()
        TLPreferences.resetStealthServerPort()
        TLPreferences.resetStealthWebSocketPort()

        LTHPasscodeViewController.deletePasscode()
        
        let DEFAULT_CURRENCY_IDX = "20"
        TLPreferences.setCurrency(DEFAULT_CURRENCY_IDX)
        TLPreferences.setInAppSettingsKitCurrency(DEFAULT_CURRENCY_IDX)
        
        TLPreferences.setSendFromCoinType(TLWalletUtils.DEFAULT_COIN_TYPE())
        TLPreferences.setSendFromType(.hdWallet)
        TLPreferences.setSendFromIndex(0)
        
        if clearWalletInMemory {
            let masterHex = TLHDWalletWrapper.getMasterHex(passphrase)
            self.appWallet.createInitialWalletPayload(passphrase, masterHex:masterHex)
            TLCoinWalletsManager.instance().setupCoinWallets(self.appWallet)
        }
        
        TLCoinWalletsManager.instance().receiveSelectedObject = TLSelectedObject()
        TLCoinWalletsManager.instance().historySelectedObject = TLSelectedObject()
        
        //self.appWallet.addAddressBookEntry("vJmwhHhMNevDQh188gSeHd2xxxYGBQmnVuMY2yG2MmVTC31UWN5s3vaM3xsM2Q1bUremdK1W7eNVgPg1BnvbTyQuDtMKAYJanahvse", label: "ArcBit Donation")
    }
    
    func respondToStealthChallegeNotification(_ note: Notification) {
        let responseDict = note.object as! NSDictionary
        let challenge = responseDict.object(forKey: "challenge") as! String
        let lock = NSLock()
        lock.lock()
        TLStealthWebSocket.instance().challenge = challenge
        lock.unlock()
        TLCoinWalletsManager.instance().respondToStealthChallege(challenge)
    }
    
    func respondToStealthAddressSubscription(_ note: Notification) {
        let responseDict = note.object as! NSDictionary
        let stealthAddress = responseDict.object(forKey: "addr") as! String
        let subscriptionSuccess = responseDict.object(forKey: "success") as! String
        if subscriptionSuccess == "False" && consecutiveFailedStealthChallengeCount < MAX_CONSECUTIVE_FAILED_STEALTH_CHALLENGE_COUNT {
            consecutiveFailedStealthChallengeCount += 1
            TLStealthWebSocket.instance().sendMessageGetChallenge()
            return
        }
        consecutiveFailedStealthChallengeCount = 0
        TLCoinWalletsManager.instance().respondToStealthAddressSubscription(stealthAddress)
    }
    
    func respondToStealthPayment(_ note: Notification) {
        let responseDict = note.object as! NSDictionary
        let stealthAddress = responseDict.object(forKey: "stealth_addr") as! String
        let txid = responseDict.object(forKey: "txid") as! String
        let paymentAddress = responseDict.object(forKey: "addr") as! String
        let txTime = UInt64((responseDict.object(forKey: "time") as! NSNumber).uint64Value)
        DLog("respondToStealthPayment stealthAddress: \(stealthAddress)")
        DLog("respondToStealthPayment respondToStealthPaymentGetTxTries: \(self.respondToStealthPaymentGetTxTries)")

        if self.respondToStealthPaymentGetTxTries < self.RESPOND_TO_STEALTH_PAYMENT_GET_TX_TRIES_MAX_TRIES {
            TLBlockExplorerAPI.instance().getTx(txid, success: { (jsonData:AnyObject?) -> () in
                if jsonData == nil {
                    return;
                }
                let txObject = TLTxObject(dict:jsonData as! NSDictionary)
                TLCoinWalletsManager.instance().handleGetTxSuccessForRespondToStealthPayment(stealthAddress,
                    paymentAddress: paymentAddress, txid: txid, txTime: txTime, txObject: txObject)
                
                    self.respondToStealthPaymentGetTxTries = 0
                }, failure: { (code, status) -> () in
                    DLog("respondToStealthPayment getTx fail \(txid)")
                    self.respondToStealthPayment(note)
                    self.respondToStealthPaymentGetTxTries += 1
            })
        }
    }
    
    func listenToIncomingTransactionForGeneratedAddress(_ note: Notification) {
        let address: AnyObject? = note.object as AnyObject?
        
        TLTransactionListener.instance().listenToIncomingTransactionForAddress(address as! String)
    }
    
    func updateModelWithNewTransaction(_ note: Notification) {
        let txDict = note.object as! NSDictionary
        DLog("updateModelWithNewTransaction txDict: \(txDict.debugDescription)")
        
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.background).async {
            let txObject = TLTxObject(dict:txDict)
            if self.pendingSelfStealthPaymentTxid != nil {
                // Special case where receiving stealth payment from same sending account. 
                // Let stealth websocket handle it
                // Need this cause, must generate private key and add address to account so that the bitcoins can be accounted for.
                if txObject.getHash() as? String == self.pendingSelfStealthPaymentTxid {
                    //self.pendingSelfStealthPaymentTxid = nil
                    return
                }
            }
            TLCoinWalletsManager.instance().updateModelWithNewTransaction(txObject)
        }
    }
    
    func updateUIForNewTx(_ txHash: String, receivedAmount: TLCoin?, receivedTo: String) {
        DispatchQueue.main.async {
            DLog("updateUIForNewTx txHash \(txHash)")
            self.webSocketNotifiedTxHashSet.add(txHash)
            NotificationCenter.default.post(name: Notification.Name(rawValue: TLNotificationEvents.EVENT_MODEL_UPDATED_NEW_UNCONFIRMED_TRANSACTION()), object: txHash, userInfo:nil)
            if let receivedAmount = receivedAmount {
                NotificationCenter.default.post(name: Notification.Name(rawValue: TLNotificationEvents.EVENT_RECEIVE_PAYMENT()), object:nil, userInfo:nil)
                self.promptReceivedPayment(receivedTo, receivedAmount: receivedAmount)
            }
        }
    }
    
    func promptReceivedPayment(_ receivedTo:String, receivedAmount:TLCoin) {
        let delayTime = DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: delayTime) {
            let msg = "\(receivedTo) received \(TLCurrencyFormat.getProperAmount(receivedAmount))"
            TLPrompts.promptSuccessMessage(msg, message: "")
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        }
    }
    
    func updateModelWithNewBlock(_ note: Notification) {
        let jsonData = note.object as! NSDictionary
        let blockHeight = jsonData.object(forKey: "height") as! NSNumber
        DLog("updateModelWithNewBlock: \(blockHeight)")
        TLBlockchainStatus.instance().blockHeight = blockHeight.uint64Value
        
        NotificationCenter.default.post(name: Notification.Name(rawValue: TLNotificationEvents.EVENT_MODEL_UPDATED_NEW_BLOCK()), object:nil, userInfo:nil)
        
    }
    
    func initializeWalletAppAndShowInitialScreen(_ recoverHDWalletIfNewlyInstalledApp:(Bool), walletPayload:(NSDictionary?)) {
        TLAnalytics.instance()
        
        NotificationCenter.default.addObserver(self
            ,selector:#selector(AppDelegate.saveWalletPayloadDelay(_:)),
            name:NSNotification.Name(rawValue: TLNotificationEvents.EVENT_WALLET_PAYLOAD_UPDATED()), object:nil)
        NotificationCenter.default.addObserver(self
            ,selector:#selector(AppDelegate.updateModelWithNewTransaction(_:)),
            name:NSNotification.Name(rawValue: TLNotificationEvents.EVENT_NEW_UNCONFIRMED_TRANSACTION()), object:nil)
        NotificationCenter.default.addObserver(self
            ,selector:#selector(AppDelegate.updateModelWithNewBlock(_:)),
            name:NSNotification.Name(rawValue: TLNotificationEvents.EVENT_NEW_BLOCK()), object:nil)
        NotificationCenter.default.addObserver(self
            ,selector:#selector(AppDelegate.listenToIncomingTransactionForGeneratedAddress(_:)),
            name:NSNotification.Name(rawValue: TLNotificationEvents.EVENT_NEW_ADDRESS_GENERATED()), object:nil)
        NotificationCenter.default.addObserver(self
            ,selector:#selector(AppDelegate.respondToStealthChallegeNotification(_:)),
            name:NSNotification.Name(rawValue: TLNotificationEvents.EVENT_RECEIVED_STEALTH_CHALLENGE()), object:nil)
        NotificationCenter.default.addObserver(self
            ,selector:#selector(AppDelegate.respondToStealthAddressSubscription(_:)),
            name:NSNotification.Name(rawValue: TLNotificationEvents.EVENT_RECEIVED_STEALTH_ADDRESS_SUBSCRIPTION()), object:nil)
        NotificationCenter.default.addObserver(self
            ,selector:#selector(AppDelegate.respondToStealthPayment(_:)),
            name:NSNotification.Name(rawValue: TLNotificationEvents.EVENT_RECEIVED_STEALTH_PAYMENT()), object:nil)
    
        TLCoinWalletsManager.instance()
        var passphrase = TLWalletPassphrase.getDecryptedWalletPassphrase()

        if !TLPreferences.hasSetupHDWallet() {
            if (recoverHDWalletIfNewlyInstalledApp) {
                self.recoverHDWallet(passphrase!)
            } else {
                passphrase = TLHDWalletWrapper.generateMnemonicPassphrase()
                self.refreshApp(passphrase!)
                
                TLCoinWalletsManager.instance().createFirstAccount()
                
                TLCoinWalletsManager.instance().updateGodSend(TLPreferences.getSendFromCoinType(), sendFromType: TLSendFromType.hdWallet, sendFromIndex:0)
                TLCoinWalletsManager.instance().updateReceiveSelectedObject(TLPreferences.getSendFromCoinType(), sendFromType: TLSendFromType.hdWallet, sendFromIndex:0)
                TLCoinWalletsManager.instance().updateHistorySelectedObject(TLPreferences.getSendFromCoinType(), sendFromType: TLSendFromType.hdWallet, sendFromIndex:0)
            }
            justSetupHDWallet = true
            guard let password = TLWalletJson.getDecryptedEncryptedWalletJSONPassphrase(),
                let walletsJson = appWallet.getWalletsJson() else { return }
            let encryptedWalletJson = TLWalletJson.getEncryptedWalletJsonContainer(walletsJson,
                password: password)
            let success = saveWalletJson(encryptedWalletJson as NSString, date:Date())
            if success {
                TLPreferences.setHasSetupHDWallet(true)
            } else {
                NSException(name: NSExceptionName(rawValue: "Error"), reason: "Error saving wallet JSON file", userInfo: nil).raise()
            }
        } else {
            let masterHex = TLHDWalletWrapper.getMasterHex(passphrase ?? "")

            if let walletPayload = walletPayload {
                appWallet.loadWalletPayload(walletPayload, masterHex:masterHex)
            } else {
                TLPrompts.promptErrorMessage(TLDisplayStrings.ERROR_STRING(), message:TLDisplayStrings.ERROR_LOADING_WALLET_JSON_FILE_STRING())
                NSException(name: NSExceptionName(rawValue: "Error"), reason: "Error loading wallet JSON file", userInfo: nil).raise()
            }
        }
        
        // Update wallet json to v3
        if self.appWallet.getWalletJsonVersion() == TLWalletJSONKeys.STATIC_MEMBERS.WALLET_PAYLOAD_VERSION_TWO {
            self.appWallet.updateWalletJSONToV3()
            TLCoinWalletsManager.instance().createFirstBitcoinCashAccount()
            printOutWalletJSON()
            self.saveWalletJsonCloud()
        }
        
        TLCoinWalletsManager.instance().setupCoinWallets(self.appWallet)
        
        TLCoinWalletsManager.instance().godSend = TLSpaghettiGodSend(appWallet: appWallet)
        TLCoinWalletsManager.instance().receiveSelectedObject = TLSelectedObject()
        TLCoinWalletsManager.instance().historySelectedObject = TLSelectedObject()
        TLCoinWalletsManager.instance().updateGodSend()
        let selectObjected: AnyObject? = TLCoinWalletsManager.instance().godSend?.getSelectedSendObject()
        if let receiveSelectedObject = TLCoinWalletsManager.instance().receiveSelectedObject,
            let historySelectedObject = TLCoinWalletsManager.instance().historySelectedObject {
            if selectObjected is TLAccountObject {
                receiveSelectedObject.setSelectedAccount(selectObjected as! TLAccountObject)
                historySelectedObject.setSelectedAccount(selectObjected as! TLAccountObject)
            } else if (selectObjected is TLImportedAddress) {
                receiveSelectedObject.setSelectedAddress(selectObjected as! TLImportedAddress)
                historySelectedObject.setSelectedAddress(selectObjected as! TLImportedAddress)
            }
        }
        
        TLBlockExplorerAPI.instance()
        TLExchangeRate.instance()
        TLAchievements.instance()
        
        guard let blockExplorerURL = TLPreferences.getBlockExplorerURL(TLPreferences.getBlockExplorerAPI()),
            let baseURL = URL(string: blockExplorerURL) else { return }
        
        TLNetworking.isReachable(baseURL, reachable:{(reachable: TLDOMAINREACHABLE) in
            if reachable == TLDOMAINREACHABLE.notreachable {
                TLPrompts.promptErrorMessage(TLDisplayStrings.NETWORK_ERROR_STRING(),
                    message:String(format:TLDisplayStrings.X_SERVERS_NOT_REACHABLE_STRING(), blockExplorerURL))
            }
        })
        
        TLBlockExplorerAPI.instance().getBlockHeight({(jsonData: AnyObject!) in
            let blockHeight = (jsonData.object(forKey: "height") as! NSNumber).uint64Value
            DLog("setBlockHeight: \((jsonData.object(forKey: "height") as! NSNumber))")
            TLBlockchainStatus.instance().blockHeight = blockHeight
            }, failure:{(code, status) in
                DLog("Error getting block height.")
//                TLPrompts.promptErrorMessage(TLDisplayStrings.NETWORK_ERROR_STRING(),
//                    message:String(format:TLDisplayStrings.ERROR_GETTING_BLOCK_HEIGHT_STRING()))
        })
    }
    
    fileprivate func setUpLocalNotification() {
        if (TLUtils.getiOSVersion() >= 8) {
            let types: UIUserNotificationType = [UIUserNotificationType.badge, UIUserNotificationType.sound, UIUserNotificationType.alert]
            let mySettings =
            UIUserNotificationSettings(types: types, categories:nil)
            UIApplication.shared.registerUserNotificationSettings(mySettings)
        }
    }
    
    func application(_ applcation: UIApplication, didReceive notification: UILocalNotification) {
        if let alertBody = notification.alertBody {
            DLog("didReceiveLocalNotification: \(alertBody)")
            let av = UIAlertView(title: alertBody,
                             message:"",
                delegate:nil,
                cancelButtonTitle:nil,
                otherButtonTitles:TLDisplayStrings.OK_STRING())
        
            av.show()
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        }
        
    }
    
    fileprivate func showLocalNotification(_ message: String) {
        DLog("showLocalNotification: \(message)")
        let localNotification = UILocalNotification()
        localNotification.soundName = UILocalNotificationDefaultSoundName
        localNotification.fireDate = Date(timeIntervalSinceNow:1)
        localNotification.alertBody = message
        localNotification.timeZone = TimeZone.current
        UIApplication.shared.scheduleLocalNotification(localNotification)
    }
    
    fileprivate func isCameraAllowed() -> Bool {
        return AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) != AVAuthorizationStatus.denied
    }
    
    fileprivate func promptAppNotAllowedCamera() {
        let displayName = TLUtils.defaultAppName()
        
        let av = UIAlertView(title: String(format:TLDisplayStrings.X_NOT_ALLOWED_TO_ACCESS_THE_CAMERA_STRING(), displayName),
            message: String(format:TLDisplayStrings.ALLOW_CAMERA_ACCESS_IN_STRING(), displayName),
            delegate:nil      ,
            cancelButtonTitle:TLDisplayStrings.OK_STRING())
        
        av.show()
    }
    
    
    func showPrivateKeyReaderController(_ viewController: UIViewController, success: @escaping TLWalletUtils.SuccessWithDictionary, error: @escaping TLWalletUtils.ErrorWithString) {
        if !isCameraAllowed() {
            self.promptAppNotAllowedCamera()
            return
        }
        
        let reader = TLQRCodeScannerViewController(success:{(data: String?) in
            
            if let data = data, TLCoreBitcoinWrapper.isBIP38EncryptedKey(data, isTestnet: self.appWallet.walletConfig.isTestnet) {
                self.scannedEncryptedPrivateKey = data
            }
            else {
                guard let data = data else {
                    error("No Data")
                    return
                }
                success(["privateKey": data])
            }
            
            }, error:{(e: String?) in
                error(e)
        })
        
        viewController.present(reader, animated:true, completion:nil)
    }
    
    func showAddressReaderControllerFromViewController(_ viewController: (UIViewController), success: @escaping (TLWalletUtils.SuccessWithString), error: @escaping (TLWalletUtils.ErrorWithString)) {
        if (!isCameraAllowed()) {
            promptAppNotAllowedCamera()
            return
        }
        
        let reader = TLQRCodeScannerViewController(success:{(data: String?) in
            success(data)
            }, error:{(e: String?) in
                error(e)
        })
        
        viewController.present(reader, animated:true, completion:nil)
    }
    
    func showExtendedPrivateKeyReaderController(_ viewController: (UIViewController), success: @escaping (TLWalletUtils.SuccessWithString), error: @escaping (TLWalletUtils.ErrorWithString)) {
        if (!isCameraAllowed()) {
            promptAppNotAllowedCamera()
            return
        }
        
        let reader = TLQRCodeScannerViewController(success:{(data: String?) in
            success(data)
            }, error:{(e: String?) in
                error(e)
        })
        
        viewController.present(reader, animated:true, completion:nil)
    }
    
    func showExtendedPublicKeyReaderController(_ viewController: (UIViewController), success: @escaping (TLWalletUtils.SuccessWithString), error: @escaping (TLWalletUtils.ErrorWithString)) {
        if (!isCameraAllowed()) {
            promptAppNotAllowedCamera()
            return
        }
        
        let reader = TLQRCodeScannerViewController(success:{(data: String?) in
            success(data)
            }, error:{(e: String?) in
                error(e)
        })
        
        viewController.present(reader, animated:true, completion:nil)
    }
    
    func showColdWalletSpendReaderControllerFromViewController(_ viewController: (UIViewController), success: @escaping (TLWalletUtils.SuccessWithString), error: @escaping (TLWalletUtils.ErrorWithString)) {
        if (!isCameraAllowed()) {
            promptAppNotAllowedCamera()
            return
        }
        
        let reader = TLQRCodeScannerViewController(success:{(data: String?) in
            success(data)
            }, error:{(e: String?) in
                error(e)
        })
        
        viewController.present(reader, animated:true, completion:nil)
    }
    
    func application(_ application: (UIApplication), open url: URL, sourceApplication: (String)?, annotation:Any) -> Bool {
        self.bitcoinURIOptionsDict = TLWalletUtils.parseBitcoinURI(url.absoluteString)        
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        TLExchangeRate.instance().updateExchangeRate()
    }   
    
    func applicationDidBecomeActive(_ application: UIApplication) {
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        saveWalletJsonCloud()
    }
    
    func saveWalletPayloadDelay(_ notification: Notification) {
        DispatchQueue.main.async {
            if self.saveWalletJSONEnabled == false {
                return
            }
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector:#selector(AppDelegate.saveWalletJsonCloudBackground), object:nil)
            Timer.scheduledTimer(timeInterval: self.SAVE_WALLET_PAYLOAD_DELAY, target: self,
                selector: #selector(AppDelegate.saveWalletJsonCloudBackground), userInfo: nil, repeats: false)
        }
    }
    
    func saveWalletJsonCloudBackground() {
        DLog("saveWalletJsonCloudBackground starting...")
        let queue = DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.background)
        queue.async {
            self.saveWalletJsonCloud()
        }
    }
    
    func printOutWalletJSON() {
        func JSONStringify(value: AnyObject, prettyPrinted: Bool = true) -> String {
            let options = prettyPrinted ? JSONSerialization.WritingOptions.prettyPrinted : nil
            if JSONSerialization.isValidJSONObject(value) {
                do {
                    let data = try JSONSerialization.data(withJSONObject: value, options: options!)
                    if let string = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
                        return string as String
                    }
                } catch let error as NSError {
                    // If the encryption key was not accepted, the error will state that the database was invalid
                    fatalError("Error opening Realm: \(error)")
                }
            }
            return ""
        }
        guard let walletJson = appWallet.getWalletsJson() else { return }
        let jsonString = JSONStringify(value: walletJson)
        //set breakpoint and in console do "po jsonString as NSString"
        DLog("printOutWalletJSON:\n\(jsonString)")
//        DLog("printOutWalletJSON:\n\(walletJson)")
    }
    
    func saveWalletJsonCloud() -> Bool {
        if saveWalletJSONEnabled == false {
            DLog("saveWalletJSONEnabled disabled")
            return false
        }
        printOutWalletJSON()
        DLog("saveFileToCloud starting...")
        guard let walletJson = appWallet.getWalletsJson(),
            let password = TLWalletJson.getDecryptedEncryptedWalletJSONPassphrase() else { return false }
        let encryptedWalletJson = TLWalletJson.getEncryptedWalletJsonContainer(walletJson,
            password: password)
        saveWalletJson(encryptedWalletJson as (NSString), date:Date())
        DLog("saveFileToCloud local done")
        return true
    }
    
    fileprivate func saveWalletJson(_ encryptedWalletJson: (NSString), date: (Date)) -> Bool {
        let success = TLWalletJson.saveWalletJson(encryptedWalletJson as String, date:date)
        
        if (!success) {
            DispatchQueue.main.async {
                TLPrompts.promptErrorMessage(TLDisplayStrings.LOCAL_BACK_UP_TO_WALLET_FAILED_STRING(), message:TLDisplayStrings.LOCAL_BACK_UP_TO_WALLET_FAILED_STRING())
            }
        }
        
        return success
    }
    
    func getLocalWalletJsonDict() -> NSDictionary? {
        return TLWalletJson.getWalletJsonDict(TLWalletJson.getLocalWalletJSONFile(),
            password:TLWalletJson.getDecryptedEncryptedWalletJSONPassphrase())
    }
    
    fileprivate func menuShownHideStatusBar() {
        UIApplication.shared.isStatusBarHidden = true
    }
    
    fileprivate func menuHiddenShowStatusBar() {
        UIApplication.shared.isStatusBarHidden = false
    }
    
    
    func passcodeViewControllerWillClose() {
        UIApplication.shared.isStatusBarHidden = false
    }
    
    func maxNumberOfFailedAttemptsReached() {
    }
    
    func passcodeWasEnteredSuccessfully() {
        UIApplication.shared.isStatusBarHidden = false
    }
    
    func logoutButtonWasPressed() {
        UIApplication.shared.isStatusBarHidden = false
    }
}

