//
//  NavBlockModels.swift
//  Supporting types and models for NavStackedBlocksView
//

import SwiftUI

// MARK: - Search Models

struct SearchResult {
    let id: String
    let title: String
    let subtitle: String
    let type: SearchResultType
    let data: Any
}

enum SearchResultType {
    case year
    case album
}

// MARK: - Quick Action Model

struct QuickAction {
    let title: String
    let subtitle: String
    let icon: String
    let query: String
    let gradientColors: [Color]
}

// MARK: - Supporting Types

struct IdentifiableInt: Identifiable {
    let id = UUID()
    let value: Int
}
