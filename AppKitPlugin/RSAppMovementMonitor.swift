//
//  RSAppMovementMonitor.swift
//
//	https:://github.com/RedSweater/RSAppMovementMonitor
//
//  Created by Daniel Jalkut on 8/28/19.
//  Copyright © 2019 Red Sweater Software. All rights reserved.
//

import Cocoa

@MainActor
public class RSAppMovementMonitor: NSObject {

	// If provided, the handler will be consulted when the app is moved.
	// Return true to indicate that the default handler should be invoked.
	public var appMovementHandler: ((RSAppMovementMonitor) -> Bool)? = nil

	// DispatchSource offers a monitoring mechanism based on an open file descriptor
	var fileDescriptor: Int32 = -1
	var dispatchSource: DispatchSourceFileSystemObject? = nil

	// Save the original location of the app in a file reference URL, which will track its new location.
	// Note this is NSURL, not URL, because file reference URLs violate value-type assumptions of URL.
	// Casting shenanigans here are required to avoid the NSURL ever bridging to URL, and losing its
	// "magical" fileReferenceURL status.
	//
	// See: https://christiantietze.de/posts/2018/09/nsurl-filereferenceurl-swift/
	//
	let originalAppURL: URL?
	var appTrackingURL: NSURL?

	// We load these strings at launch time so that they can be localized. If we wait until
	// the application has been moved, the localization will fail.
	let alertMessageText: String
	let alertInformativeText: String
	let alertRelaunchButtonText: String

	override public init() {
		
		// Establish baseline URLs. Note  that simply asking for Bundle.main.bundleURL will return
		// the translocated location of an app when it is launched in quarantine state. This leads
		// to a permanent false-positive detection that the app has moved. To work around this, we
		// ask for the fileReferenceURL's absoluteURL at launch time, and compare to the absoluteURL
		// later to detect bona fide user-driven app movement.
		self.appTrackingURL = (Bundle.main.bundleURL as NSURL).fileReferenceURL() as NSURL?
		self.originalAppURL = appTrackingURL?.absoluteURL

		let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? NSLocalizedString("label.text.app-placeholder", bundle: .ext, comment: "'This app': Backup name if the app name cannot be deduced from the bundle")
		let informativeTextTemplate = NSLocalizedString("label.text.%@-moved-or-renamed", bundle: .ext, comment: "%@ was moved or renamed while open.")
		self.alertMessageText = String(format: informativeTextTemplate, arguments: [appName])
		self.alertInformativeText = NSLocalizedString("label.text.moving-application-informative", bundle: .ext, comment: "Infomative text: Moving an open application can cause unexpected behavior. Manually relaunch the application to continue.")
		self.alertRelaunchButtonText = NSLocalizedString("label.text.terminate", bundle: .ext, comment: "Terminate")

		super.init()

		// Monitor for direct changes to the app bundle's folder - this will catch the
		// majority of direct manipulations to the app's location on disk immediately,
		// right as it happens.
		if let originalAppPath = originalAppURL?.path {
			self.fileDescriptor = open(originalAppPath, O_EVTONLY)
			if self.fileDescriptor != -1 {
				Task { @MainActor in
					self.dispatchSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: self.fileDescriptor, eventMask: [.delete, .rename], queue: DispatchQueue.main)
					if let source = self.dispatchSource {
						source.setEventHandler {
							self.invokeEventHandler()
						}
						
						source.setCancelHandler {
							self.invalidate()
						}
						
						source.resume()
					}
				}
			}
			
			// Also install a notification to re-check the location of the app on disk
			// every time the app becomes active. This catches a good number of edge-case
			// changes to the app bundle's path, such as when a containing folder or the
			// volume name changes.
			NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { notification in
				// Removing observer in invalidate doesn't seem to prevent this getting called? Maybe
				// because it's on the same invocation of the runloop?
				Task { @MainActor in
					if self.isValid() && self.originalAppURL != self.appTrackingURL?.absoluteURL {
						self.invokeEventHandler()
					}
				}
			}
		}
	}

	func invokeEventHandler() {
		// Prevent re-entry when the app is activated while running handler
		self.invalidate()

		var useDefaultHandler = true
		if let customHandler = self.appMovementHandler {
			useDefaultHandler = customHandler(self)
		}

		if useDefaultHandler {
			self.defaultHandler()
		}
	}

	func isValid() -> Bool {
		return self.fileDescriptor != -1
	}

	func invalidate() {
		if let dispatchSource = self.dispatchSource {
			dispatchSource.cancel()
			self.dispatchSource = nil
		}

		if self.fileDescriptor != -1 {
			close(self.fileDescriptor)
			self.fileDescriptor = -1
		}

		NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)

		self.appMovementHandler = nil
	}

	func relaunchFromURL(_ appURL: URL) {
		// Relaunching is best achieved by requesting that the system launch the app
		// at the given URL with the "new instance" option to prevent it simply reactivating us.
		
//		let configuration = NSWorkspace.OpenConfiguration()
//		configuration.createsNewApplicationInstance = true
//		NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

//		let _ = try? NSWorkspace.shared.launchApplication(at: appURL, options: .newInstance, configuration: [:])
		NSApp.terminate(self)
	}

	func defaultHandler() {
		let quitAlert = NSAlert()
		quitAlert.alertStyle = .critical
		quitAlert.addButton(withTitle: self.alertRelaunchButtonText)

		quitAlert.messageText = self.alertMessageText
		quitAlert.informativeText = self.alertInformativeText

		let modalResponse = quitAlert.runModal()
		if modalResponse == .alertFirstButtonReturn {
			self.invalidate()

			if let movedAppURL = self.appTrackingURL as URL? {
				self.relaunchFromURL(movedAppURL)
			}
		}
	}

}
