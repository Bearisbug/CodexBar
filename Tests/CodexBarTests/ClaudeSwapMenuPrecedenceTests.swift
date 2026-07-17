import CodexBarCore
import Testing
@testable import CodexBar

struct ClaudeSwapMenuPrecedenceTests {
    @Test
    func multiple_Claude_swap_accounts_take_precedence() {
        #expect(ClaudeSwapMenuPrecedence.prefersClaudeSwap(provider: .claude, accountCount: 2))
    }

    @Test
    func precedence_requires_Claude_and_multiple_swap_accounts() {
        #expect(!ClaudeSwapMenuPrecedence.prefersClaudeSwap(provider: .claude, accountCount: 0))
        #expect(!ClaudeSwapMenuPrecedence.prefersClaudeSwap(provider: .claude, accountCount: 1))
        #expect(!ClaudeSwapMenuPrecedence.prefersClaudeSwap(provider: .openai, accountCount: 2))
    }
}
