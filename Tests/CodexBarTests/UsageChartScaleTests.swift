import CodexBarCore
import Testing

struct UsageChartScaleTests {
    @Test
    func sub_dollar_maximum_fills_the_chart() {
        let scale = UsageChartScale(values: [0.10, 0.25, 0.50])

        #expect(scale.maximum == 0.50)
        #expect(scale.fraction(for: 0.50) == 1)
        #expect(scale.fraction(for: 0.25) == 0.5)
    }

    @Test
    func scale_ignores_invalid_and_nonpositive_values() {
        let scale = UsageChartScale(values: [.nan, .infinity, -10, 0, 4])

        #expect(scale.maximum == 4)
        #expect(scale.fraction(for: .nan) == 0)
        #expect(scale.fraction(for: -1) == 0)
        #expect(scale.fraction(for: 8) == 1)
    }
}
