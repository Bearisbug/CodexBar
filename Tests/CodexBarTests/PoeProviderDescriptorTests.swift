import CodexBarCore
import Testing

struct PoeProviderDescriptorTests {
    @Test
    func Poe_uses_the_official_brand_color_and_icon() {
        let branding = PoeProviderDescriptor.descriptor.branding

        #expect(branding.iconResourceName == "ProviderIcon-poe")
        #expect(branding.color == ProviderColor(red: 93 / 255, green: 92 / 255, blue: 222 / 255))
    }
}
