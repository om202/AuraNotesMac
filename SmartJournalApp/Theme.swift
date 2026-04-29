//
//  Theme.swift
//  SmartJournalApp
//

import SwiftUI

enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Size {
        static let editorMaxWidth: CGFloat = 720
        static let sidebarMin: CGFloat = 240
        static let sidebarIdeal: CGFloat = 280
        static let rowMinHeight: CGFloat = 44
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
    }

    enum FontSize {
        static let body: CGFloat = 18
        static let title: CGFloat = 34
        static let heading: CGFloat = 26
        static let subheading: CGFloat = 21
        static let bodyLineHeightMultiple: CGFloat = 1.5
    }
}
