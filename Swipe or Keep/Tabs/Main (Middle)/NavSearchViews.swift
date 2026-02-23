//
//  NavSearchViews.swift
//  Search-related views for NavStackedBlocksView
//

import SwiftUI

// MARK: - Search View Extension

extension NavStackedBlocksView {
    
    // MARK: - Search Bar View
    
    @ViewBuilder
    func searchBarView() -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 16))
                
                if #available(iOS 17.0, *) {
                    TextField("Search time periods...", text: $searchText)
                        .foregroundColor(.white)
                        .font(.custom(AppFont.regular, size: 16))
                        .textFieldStyle(PlainTextFieldStyle())
                        .onChange(of: searchText) { _, newValue in
                            performSearch(query: newValue)
                        }
                } else {
                    TextField("Search time periods...", text: $searchText)
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
            
            // Search suggestions (same as before)
            if searchText.isEmpty {
                searchSuggestionsView()
            }
        }
    }
    
    // MARK: - Search Suggestions View
    
    @ViewBuilder
    func searchSuggestionsView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Search Suggestions")
                    .foregroundColor(.white)
                    .font(.custom(AppFont.regular, size: 20))
                Spacer()
                Image(systemName: "lightbulb")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 4)
            
            // Examples and Quick Actions
            searchExamplesSection()
            quickActionsSection()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
    
    // MARK: - Search Examples Section
    
    @ViewBuilder
    func searchExamplesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 14))
                Text("Try searching for:")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.custom(AppFont.regular, size: 16))
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(getSearchExamples(), id: \.self) { example in
                        Button(action: {
                            searchText = example
                            performSearch(query: example)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "quote.bubble")
                                    .foregroundColor(.white.opacity(0.6))
                                    .font(.system(size: 12))
                                Text(example)
                                    .foregroundColor(.white)
                                    .font(.custom(AppFont.regular, size: 14))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(SearchSuggestionButtonStyle())
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Quick Actions Section
    
    @ViewBuilder
    func quickActionsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 14))
                Text("Quick Actions")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.custom(AppFont.regular, size: 16))
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(getQuickActions(), id: \.title) { action in
                    Button(action: {
                        searchText = action.query
                        performSearch(query: action.query)
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: action.gradientColors),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .shadow(color: action.gradientColors.first?.opacity(0.3) ?? Color.clear, radius: 4, x: 0, y: 2)
                                
                                Image(systemName: action.icon)
                                    .foregroundColor(.white)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            
                            Text(action.title)
                                .foregroundColor(.white)
                                .font(.custom(AppFont.regular, size: 14))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.white.opacity(0.1),
                                                    Color.white.opacity(0.05)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .buttonStyle(QuickActionButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Search Results View
    
    @ViewBuilder
    func searchResultsView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.custom(AppFont.regular, size: 14))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            if searchResults.isEmpty && !searchText.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 28))
                    Text("No results found")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.custom(AppFont.regular, size: 16))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                VStack(spacing: 8) {
                    ForEach(searchResults, id: \.id) { result in
                        Button(action: {
                            selectSearchResult(result)
                        }) {
                            simpleSearchResultRow(result: result)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
    
    // MARK: - Simple Search Result Row
    
    @ViewBuilder
    func simpleSearchResultRow(result: SearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.type == .year ? "calendar" : "rectangle.stack")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 18))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}
