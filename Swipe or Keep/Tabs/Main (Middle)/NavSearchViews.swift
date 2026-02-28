//
//  NavSearchViews.swift
//  Search-related views for NavStackedBlocksView
//
//  Simplified search interface with:
//  - Clean search bar with real-time search
//  - Quick filter actions for common time periods
//  - Streamlined search results display
//

import SwiftUI

// MARK: - Search View Extension

extension NavStackedBlocksView {
    
    // MARK: - Search Bar View
    
    @ViewBuilder
    func searchBarView() -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.6))
                .font(.system(size: 16))
            
            if #available(iOS 17.0, *) {
                TextField("Search dates, albums, categories...", text: $searchText)
                    .foregroundColor(.white)
                    .font(.custom(AppFont.regular, size: 16))
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchText) { _, newValue in
                        performSearch(query: newValue)
                    }
            } else {
                TextField("Search dates, albums, categories...", text: $searchText)
                    .foregroundColor(.white)
                    .font(.custom(AppFont.regular, size: 16))
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchText) { newValue in
                        performSearch(query: newValue)
                    }
            }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchResults = []
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingSearchResults = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 16))
                }
            }
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isSearching = false
                    showingSearchResults = false
                    searchText = ""
                    searchResults = []
                }
            }) {
                Text("Cancel")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.custom(AppFont.regular, size: 16))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.2))
        )
    }
    
    // MARK: - Quick Actions View
    
    @ViewBuilder
    func quickActionsView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Filters")
                .foregroundColor(.white.opacity(0.7))
                .font(.custom(AppFont.regular, size: 14))
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(getQuickActions(), id: \.title) { action in
                    Button(action: {
                        searchText = action.query
                        performSearch(query: action.query)
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: action.icon)
                                .foregroundColor(.white)
                                .font(.system(size: 20, weight: .medium))
                            
                            Text(action.title)
                                .foregroundColor(.white)
                                .font(.custom(AppFont.regular, size: 14))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Search Results View
    
    @ViewBuilder
    func searchResultsView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                .foregroundColor(.white.opacity(0.6))
                .font(.custom(AppFont.regular, size: 14))
                .padding(.horizontal, 4)
            
            if searchResults.isEmpty && !searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.3))
                        .font(.system(size: 40))
                    Text("No results found")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.custom(AppFont.regular, size: 16))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(searchResults, id: \.id) { result in
                    Button(action: {
                        selectSearchResult(result)
                    }) {
                        searchResultRow(result: result)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Search Result Row
    
    @ViewBuilder
    func searchResultRow(result: SearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: {
                switch result.type {
                case .year:             return "calendar"
                case .album:            return "rectangle.stack"
                case .category(let i):
                    switch i {
                    case 0:  return "clock.arrow.circlepath"   // Recents
                    case 1:  return "camera.viewfinder"         // Screenshots
                    case 2:  return "heart"                     // Favorites
                    default: return "folder"
                    }
                }
            }())
            .foregroundColor(.white.opacity(0.7))
            .font(.system(size: 18))
            .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .foregroundColor(.white)
                    .font(.custom(AppFont.regular, size: 16))
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .foregroundColor(.white.opacity(0.6))
                        .font(.custom(AppFont.regular, size: 14))
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
    }
}
