import Foundation

class QuotesManager: ObservableObject {
    static let shared = QuotesManager()
    
    @Published var currentQuote: String = ""
    
    private let quotes = [
        "you got this!",
        "one step at a time",
        "progress over perfection",
        "small wins matter",
        "keep going",
        "you're doing great",
        "trust the process",
        "clarity is coming",
        "less is more",
        "breathe and begin",
        "make space for what matters",
        "simplicity wins",
        "you're stronger than you think",
        "focus on today",
        "let it go",
        "start where you are",
        "done is better than perfect",
        "keep it simple"
    ]
    
    private init() {
        selectRandomQuote()
    }
    
    func selectRandomQuote() {
        currentQuote = quotes.randomElement() ?? "you got this!"
    }
}
