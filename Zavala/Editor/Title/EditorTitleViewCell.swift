//
//  EditorTitleViewCell.swift
//  Zavala
//
//  Created by Maurice Parker on 12/7/20.
//

import UIKit
import VinOutlineKit

@MainActor
protocol EditorTitleViewCellDelegate: AnyObject {
	var editorTitleUndoManager: UndoManager? { get }
	func editorTitleTextFieldDidBecomeActive()
	func editorTitleDidUpdate(title: String)
	func editorTitleMoveToTagInput()
}

class EditorTitleViewCell: UICollectionViewListCell {

	weak var outline: Outline? {
		didSet {
			setNeedsUpdateConfiguration()
		}
	}
	
	var textViewText: String? {
		guard let textView = (contentView as? EditorTitleContentView)?.textView else { return nil }
		return textView.text
	}
	
	weak var delegate: EditorTitleViewCellDelegate? {
		didSet {
			setNeedsUpdateConfiguration()
		}
	}
	
	override func updateConfiguration(using state: UICellConfigurationState) {
		super.updateConfiguration(using: state)
		
		layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

		var content = EditorTitleContentConfiguration(outline: outline).updated(for: state)
		content.delegate = delegate
		contentConfiguration = content
	}

	func takeCursor() {
		guard let textView = (contentView as? EditorTitleContentView)?.textView else { return }
		textView.becomeFirstResponder()
		let endPosition = textView.endOfDocument
		textView.selectedTextRange = textView.textRange(from: endPosition, to: endPosition)
	}
	
}
