import CodexBarCore
import Testing

struct ProviderConfigEnvironmentTests {
    @Test
    func applies_API_key_override_for_amp() {
        let config = ProviderConfig(id: .amp, apiKey: "sgamp-config")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .amp,
            config: config)

        #expect(env[AmpSettingsReader.apiTokenKey] == "sgamp-config")
        #expect(ProviderTokenResolver.ampToken(environment: env) == "sgamp-config")
    }

    @Test
    func applies_API_key_override_for_zai() {
        let config = ProviderConfig(id: .zai, apiKey: "z-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .zai,
            config: config)

        #expect(env[ZaiSettingsReader.apiTokenKey] == "z-token")
        #expect(env[ZaiSettingsReader.bigModelOrganizationKey] == nil)
        #expect(env[ZaiSettingsReader.bigModelProjectKey] == nil)
    }

    @Test
    func applies_API_key_override_for_warp() {
        let config = ProviderConfig(id: .warp, apiKey: "w-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .warp,
            config: config)

        let key = WarpSettingsReader.apiKeyEnvironmentKeys.first
        #expect(key != nil)
        guard let key else { return }

        #expect(env[key] == "w-token")
    }

    @Test
    func applies_API_key_override_for_open_router() {
        let config = ProviderConfig(id: .openrouter, apiKey: "or-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .openrouter,
            config: config)

        #expect(env[OpenRouterSettingsReader.envKey] == "or-token")
    }

    @Test
    func applies_API_key_override_for_cross_model() {
        let config = ProviderConfig(id: .crossmodel, apiKey: "cm-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .crossmodel,
            config: config)

        #expect(env[CrossModelSettingsReader.envKey] == "cm-token")
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .crossmodel))
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .zenmux))
    }

    @Test
    func applies_API_key_override_for_doubao() {
        let config = ProviderConfig(id: .doubao, apiKey: "db-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .doubao,
            config: config)

        #expect(env[DoubaoSettingsReader.apiKeyEnvironmentKeys[0]] == "db-token")
        #expect(ProviderTokenResolver.doubaoToken(environment: env) == "db-token")
    }

    @Test
    func preserves_doubao_ark_API_key_when_environment_secret_key_is_present() {
        let config = ProviderConfig(id: .doubao, apiKey: "ark-config")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                DoubaoSettingsReader.secretAccessKeyEnvironmentKeys[0]: "sk-env",
            ],
            provider: .doubao,
            config: config)

        #expect(env[DoubaoSettingsReader.apiKeyEnvironmentKeys[0]] == "ark-config")
        #expect(env[DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]] == nil)
        #expect(env[DoubaoSettingsReader.secretAccessKeyEnvironmentKeys[0]] == nil)
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env) == nil)
        #expect(ProviderTokenResolver.doubaoToken(environment: env) == "ark-config")
    }

    @Test
    func preserves_doubao_ark_API_key_when_config_secret_key_is_present() {
        let config = ProviderConfig(
            id: .doubao,
            apiKey: "ark-config",
            secretKey: "sk-config")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .doubao,
            config: config)

        #expect(env[DoubaoSettingsReader.apiKeyEnvironmentKeys[0]] == "ark-config")
        #expect(env[DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]] == nil)
        #expect(env[DoubaoSettingsReader.secretAccessKeyEnvironmentKeys[0]] == nil)
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env) == nil)
        #expect(ProviderTokenResolver.doubaoToken(environment: env) == "ark-config")
    }

    @Test
    func doubao_ark_API_key_config_overrides_environment_coding_plan_credentials() {
        let config = ProviderConfig(id: .doubao, apiKey: "ark-config")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]: "AKLT-env",
                DoubaoSettingsReader.secretAccessKeyEnvironmentKeys[0]: "sk-env",
                DoubaoSettingsReader.regionEnvironmentKeys[0]: "cn-shanghai",
            ],
            provider: .doubao,
            config: config)

        #expect(env[DoubaoSettingsReader.apiKeyEnvironmentKeys[0]] == "ark-config")
        #expect(env[DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]] == nil)
        #expect(env[DoubaoSettingsReader.secretAccessKeyEnvironmentKeys[0]] == nil)
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env) == nil)
        #expect(ProviderTokenResolver.doubaoToken(environment: env) == "ark-config")
    }

    @Test
    func reads_doubao_volcengine_secret_key_alias() {
        let env = [
            DoubaoSettingsReader.accessKeyIDEnvironmentKeys[1]: "AKLT-env",
            "VOLCENGINE_SECRET_KEY": "sk-env",
        ]

        #expect(DoubaoSettingsReader.secretAccessKeyEnvironmentKeys.contains("VOLCENGINE_SECRET_KEY"))
        #expect(DoubaoSettingsReader.secretAccessKey(environment: env) == "sk-env")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.accessKeyID == "AKLT-env")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.secretAccessKey == "sk-env")
    }

    @Test
    func reads_doubao_volc_sdk_credential_aliases() {
        let env = [
            "VOLC_ACCESSKEY": "AKLT-volc",
            "VOLC_SECRETKEY": "sk-volc",
            "VOLC_REGION": "cn-shanghai",
        ]

        #expect(DoubaoSettingsReader.accessKeyIDEnvironmentKeys.contains("VOLC_ACCESSKEY"))
        #expect(DoubaoSettingsReader.secretAccessKeyEnvironmentKeys.contains("VOLC_SECRETKEY"))
        #expect(DoubaoSettingsReader.regionEnvironmentKeys.contains("VOLC_REGION"))
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.accessKeyID == "AKLT-volc")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.secretAccessKey == "sk-volc")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.region == "cn-shanghai")
    }

    @Test
    func does_not_project_incomplete_doubao_access_key_as_ark_API_key() {
        let config = ProviderConfig(id: .doubao, apiKey: "AKLT-config")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .doubao,
            config: config)

        #expect(env[DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]] == nil)
        #expect(env[DoubaoSettingsReader.apiKeyEnvironmentKeys[0]] == nil)
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env) == nil)
        #expect(ProviderTokenResolver.doubaoToken(environment: env) == nil)
    }

    @Test
    func keeps_base_doubao_ark_API_key_when_config_access_key_lacks_secret() {
        let config = ProviderConfig(id: .doubao, apiKey: "AKLT-config")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                DoubaoSettingsReader.apiKeyEnvironmentKeys[0]: "ark-env",
            ],
            provider: .doubao,
            config: config)

        #expect(env[DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]] == nil)
        #expect(env[DoubaoSettingsReader.apiKeyEnvironmentKeys[0]] == "ark-env")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env) == nil)
        #expect(ProviderTokenResolver.doubaoToken(environment: env) == "ark-env")
    }

    @Test
    func applies_volcengine_access_key_override_for_doubao_coding_plan() {
        let config = ProviderConfig(
            id: .doubao,
            apiKey: "AKLT-config",
            secretKey: "sk-config",
            region: "cn-shanghai")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .doubao,
            config: config)

        #expect(env[DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]] == "AKLT-config")
        #expect(env[DoubaoSettingsReader.secretAccessKeyEnvironmentKeys[0]] == "sk-config")
        #expect(env[DoubaoSettingsReader.regionEnvironmentKeys[0]] == "cn-shanghai")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.accessKeyID == "AKLT-config")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.secretAccessKey == "sk-config")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.region == "cn-shanghai")
    }

    @Test
    func merges_doubao_config_access_key_with_environment_secret_key() {
        let config = ProviderConfig(
            id: .doubao,
            apiKey: "AKLT-config")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                DoubaoSettingsReader.secretAccessKeyEnvironmentKeys[0]: "sk-env",
                DoubaoSettingsReader.regionEnvironmentKeys[2]: "cn-shanghai",
            ],
            provider: .doubao,
            config: config)

        #expect(env[DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]] == "AKLT-config")
        #expect(env[DoubaoSettingsReader.secretAccessKeyEnvironmentKeys[0]] == "sk-env")
        #expect(env[DoubaoSettingsReader.regionEnvironmentKeys[0]] == "cn-shanghai")
        #expect(env[DoubaoSettingsReader.apiKeyEnvironmentKeys[0]] == nil)
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.accessKeyID == "AKLT-config")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.secretAccessKey == "sk-env")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.region == "cn-shanghai")
    }

    @Test
    func merges_doubao_environment_access_key_with_config_secret_key() {
        let config = ProviderConfig(
            id: .doubao,
            secretKey: "sk-config")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]: "AKLT-env",
                DoubaoSettingsReader.regionEnvironmentKeys[1]: "cn-beijing",
            ],
            provider: .doubao,
            config: config)

        #expect(env[DoubaoSettingsReader.accessKeyIDEnvironmentKeys[0]] == "AKLT-env")
        #expect(env[DoubaoSettingsReader.secretAccessKeyEnvironmentKeys[0]] == "sk-config")
        #expect(env[DoubaoSettingsReader.regionEnvironmentKeys[0]] == "cn-beijing")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.accessKeyID == "AKLT-env")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.secretAccessKey == "sk-config")
        #expect(DoubaoSettingsReader.codingPlanCredentials(environment: env)?.region == "cn-beijing")
    }

    @Test
    func applies_cookie_header_override_for_sakana() {
        let config = ProviderConfig(id: .sakana, cookieHeader: "Cookie: session=abc")
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [:],
            provider: .sakana,
            config: config)

        #expect(env[SakanaSettingsReader.cookieHeaderKey] == "Cookie: session=abc")
        #expect(SakanaSettingsReader.cookieHeader(environment: env) == "session=abc")
    }

    @Test
    func applies_cookie_header_override_for_longcat() {
        let config = ProviderConfig(
            id: .longcat,
            cookieHeader: "Cookie: passport_token=abc; uid=42",
            cookieSource: .manual)
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [:],
            provider: .longcat,
            config: config)

        #expect(env[LongCatSettingsReader.cookieHeaderKey] == "Cookie: passport_token=abc; uid=42")
        #expect(LongCatSettingsReader.cookieHeader(environment: env) == "Cookie: passport_token=abc; uid=42")
    }

    @Test
    func does_not_expose_stored_longcat_cookie_outside_manual_mode() {
        for source in [ProviderCookieSource.auto, .off] {
            let config = ProviderConfig(id: .longcat, cookieHeader: "stale=1", cookieSource: source)
            let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
                base: [:],
                provider: .longcat,
                config: config)

            #expect(env[LongCatSettingsReader.cookieHeaderKey] == nil)
        }
    }

    @Test
    func applies_API_key_override_for_moonshot() {
        let config = ProviderConfig(id: .moonshot, apiKey: "moon-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .moonshot,
            config: config)

        let key = MoonshotSettingsReader.apiKeyEnvironmentKeys.first
        #expect(key != nil)
        guard let key else { return }

        #expect(env[key] == "moon-token")
    }

    @Test
    func applies_Kimi_API_key_and_base_URL_config_overrides() throws {
        let config = ProviderConfig(
            id: .kimi,
            apiKey: "kimi-api-token",
            enterpriseHost: "https://proxy.example.com/kimi")
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [:],
            provider: .kimi,
            config: config)

        #expect(env["KIMI_CODE_API_KEY"] == "kimi-api-token")
        #expect(env["KIMI_API_KEY"] == nil)
        #expect(env[KimiSettingsReader.codeAPIBaseURLEnvironmentKey] == "https://proxy.example.com/kimi")
        #expect(ProviderTokenResolver.kimiAPIToken(environment: env) == "kimi-api-token")
        #expect(try KimiSettingsReader.codeAPIBaseURL(environment: env).absoluteString ==
            "https://proxy.example.com/kimi")
    }

    @Test
    func applies_API_key_override_for_elevenlabs() {
        let config = ProviderConfig(id: .elevenlabs, apiKey: "xi-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .elevenlabs,
            config: config)

        #expect(env[ElevenLabsSettingsReader.apiKeyEnvironmentKey] == "xi-token")
        #expect(ProviderTokenResolver.elevenLabsToken(environment: env) == "xi-token")
    }

    @Test
    func applies_API_key_override_for_groq() {
        let config = ProviderConfig(id: .groq, apiKey: "gsk-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .groq,
            config: config)

        #expect(env[GroqSettingsReader.apiKeyEnvironmentKey] == "gsk-token")
        #expect(ProviderTokenResolver.groqToken(environment: env) == "gsk-token")
    }

    @Test
    func applies_LLM_Proxy_config_overrides() {
        let config = ProviderConfig(
            id: .llmproxy,
            apiKey: "proxy-token",
            enterpriseHost: "https://proxy.example.com")
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [:],
            provider: .llmproxy,
            config: config)

        #expect(env[LLMProxySettingsReader.apiKeyEnvironmentKey] == "proxy-token")
        #expect(env[LLMProxySettingsReader.baseURLEnvironmentKey] == "https://proxy.example.com")
        #expect(ProviderTokenResolver.llmProxyToken(environment: env) == "proxy-token")
    }

    @Test
    func applies_LiteLLM_config_overrides() {
        let config = ProviderConfig(
            id: .litellm,
            apiKey: "litellm-token",
            enterpriseHost: "https://litellm.example.com/v1")
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [:],
            provider: .litellm,
            config: config)

        #expect(env[LiteLLMSettingsReader.apiKeyEnvironmentKey] == "litellm-token")
        #expect(env[LiteLLMSettingsReader.baseURLEnvironmentKey] == "https://litellm.example.com/v1")
        #expect(ProviderTokenResolver.liteLLMToken(environment: env) == "litellm-token")
    }

    @Test
    func openai_config_override_uses_preferred_admin_key_environment() {
        let config = ProviderConfig(id: .openai, apiKey: "config-openai-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey: "env-admin-token",
                OpenAIAPISettingsReader.apiKeyEnvironmentKey: "env-api-token",
            ],
            provider: .openai,
            config: config)

        #expect(env[OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey] == "config-openai-token")
        #expect(env[OpenAIAPISettingsReader.apiKeyEnvironmentKey] == "env-api-token")
        #expect(ProviderTokenResolver.openAIAPIToken(environment: env) == "config-openai-token")
    }

    @Test
    func openai_config_override_applies_project_ID_without_replacing_environment_key() {
        let config = ProviderConfig(id: .openai, workspaceID: "proj_config")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey: "env-admin-token",
            ],
            provider: .openai,
            config: config)

        #expect(env[OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey] == "env-admin-token")
        #expect(env[OpenAIAPISettingsReader.projectIDEnvironmentKey] == "proj_config")
        #expect(OpenAIAPISettingsReader.projectID(environment: env) == "proj_config")
    }

    @Test
    func applies_Azure_OpenAI_config_overrides() {
        let config = ProviderConfig(
            id: .azureopenai,
            apiKey: "config-azure-token",
            workspaceID: "chat-prod",
            enterpriseHost: "https://example-resource.openai.azure.com")
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [
                AzureOpenAISettingsReader.apiKeyEnvironmentKey: "env-azure-token",
                AzureOpenAISettingsReader.endpointEnvironmentKey: "https://env-resource.openai.azure.com",
                AzureOpenAISettingsReader.deploymentNameEnvironmentKey: "env-deployment",
            ],
            provider: .azureopenai,
            config: config)

        #expect(env[AzureOpenAISettingsReader.apiKeyEnvironmentKey] == "config-azure-token")
        #expect(env[AzureOpenAISettingsReader.endpointEnvironmentKey] == "https://example-resource.openai.azure.com")
        #expect(env[AzureOpenAISettingsReader.deploymentNameEnvironmentKey] == "chat-prod")
        #expect(ProviderTokenResolver.azureOpenAIToken(environment: env) == "config-azure-token")
        #expect(AzureOpenAISettingsReader.deploymentName(environment: env) == "chat-prod")
    }

    @Test
    func bedrock_config_maps_AWS_credential_fields() {
        let config = ProviderConfig(
            id: .bedrock,
            apiKey: "AKIATEST",
            secretKey: "secret",
            cookieHeader: "legacy-cookie-secret",
            region: "us-west-2")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .bedrock,
            config: config)

        #expect(env[BedrockSettingsReader.accessKeyIDKey] == "AKIATEST")
        #expect(env[BedrockSettingsReader.secretAccessKeyKey] == "secret")
        #expect(env[BedrockSettingsReader.regionKeys[0]] == "us-west-2")
        #expect(!env.values.contains("legacy-cookie-secret"))
    }

    @Test
    func bedrock_config_merges_secret_and_region_without_replacing_environment_access_key() {
        let config = ProviderConfig(
            id: .bedrock,
            apiKey: nil,
            secretKey: "config-secret",
            region: "eu-central-1")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [BedrockSettingsReader.accessKeyIDKey: "env-access"],
            provider: .bedrock,
            config: config)

        #expect(env[BedrockSettingsReader.accessKeyIDKey] == "env-access")
        #expect(env[BedrockSettingsReader.secretAccessKeyKey] == "config-secret")
        #expect(env[BedrockSettingsReader.regionKeys[0]] == "eu-central-1")
        #expect(BedrockSettingsReader.hasCredentials(environment: env))
    }

    @Test
    func bedrock_merged_static_credentials_win_over_inherited_AWS_PROFILE() {
        let config = ProviderConfig(
            id: .bedrock,
            secretKey: "config-secret",
            region: "eu-central-1")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                BedrockSettingsReader.profileKey: "work",
                BedrockSettingsReader.accessKeyIDKey: "env-access",
            ],
            provider: .bedrock,
            config: config)

        #expect(env[BedrockSettingsReader.accessKeyIDKey] == "env-access")
        #expect(env[BedrockSettingsReader.secretAccessKeyKey] == "config-secret")
        #expect(env[BedrockSettingsReader.regionKeys[0]] == "eu-central-1")
        #expect(BedrockSettingsReader.authMode(environment: env) == .keys)
    }

    @Test
    func bedrock_profile_mode_projects_AWS_PROFILE_without_saved_static_keys() {
        let config = ProviderConfig(
            id: .bedrock,
            apiKey: "AKIATEST",
            secretKey: "secret",
            region: "eu-west-1",
            awsProfile: "work",
            awsAuthMode: "profile")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .bedrock,
            config: config)
        #expect(env[BedrockSettingsReader.authModeKey] == "profile")
        #expect(env[BedrockSettingsReader.profileKey] == "work")
        #expect(env[BedrockSettingsReader.regionKeys[0]] == "eu-west-1")
        #expect(env[BedrockSettingsReader.accessKeyIDKey] == nil)
        #expect(env[BedrockSettingsReader.secretAccessKeyKey] == nil)
    }

    @Test
    func bedrock_config_without_explicit_mode_preserves_env_profile_inference() {
        let config = ProviderConfig(id: .bedrock, region: "us-east-1")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [BedrockSettingsReader.profileKey: "work"],
            provider: .bedrock,
            config: config)
        #expect(env[BedrockSettingsReader.authModeKey] == nil)
        #expect(env[BedrockSettingsReader.profileKey] == "work")
        #expect(BedrockSettingsReader.authMode(environment: env) == .profile)
    }

    @Test
    func bedrock_saved_static_keys_survive_base_AWS_PROFILE_when_auth_mode_is_unset() {
        let config = ProviderConfig(
            id: .bedrock,
            apiKey: "AKIASAVED",
            secretKey: "saved-secret",
            region: "us-east-1")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [BedrockSettingsReader.profileKey: "work"],
            provider: .bedrock,
            config: config)
        // Upgrade path: saved keys win over an inherited AWS_PROFILE, no silent switch.
        #expect(env[BedrockSettingsReader.accessKeyIDKey] == "AKIASAVED")
        #expect(env[BedrockSettingsReader.secretAccessKeyKey] == "saved-secret")
        #expect(BedrockSettingsReader.authMode(environment: env) == .keys)
    }

    @Test
    func bedrock_profile_mode_preserves_inherited_static_credentials_for_environment_source_profiles() {
        let config = ProviderConfig(id: .bedrock, awsProfile: "work", awsAuthMode: "profile")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                BedrockSettingsReader.accessKeyIDKey: "AKIAINHERITED",
                BedrockSettingsReader.secretAccessKeyKey: "inherited-secret",
                BedrockSettingsReader.sessionTokenKey: "inherited-token",
            ],
            provider: .bedrock,
            config: config)
        #expect(env[BedrockSettingsReader.accessKeyIDKey] == "AKIAINHERITED")
        #expect(env[BedrockSettingsReader.secretAccessKeyKey] == "inherited-secret")
        #expect(env[BedrockSettingsReader.sessionTokenKey] == "inherited-token")
        #expect(env[BedrockSettingsReader.profileKey] == "work")
    }

    @Test
    func bedrock_env_profile_mode_does_not_project_saved_static_credentials() {
        let config = ProviderConfig(
            id: .bedrock,
            apiKey: "AKIASAVED",
            secretKey: "saved-secret")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [
                BedrockSettingsReader.authModeKey: "profile",
                BedrockSettingsReader.profileKey: "work",
            ],
            provider: .bedrock,
            config: config)

        #expect(env[BedrockSettingsReader.authModeKey] == "profile")
        #expect(env[BedrockSettingsReader.profileKey] == "work")
        #expect(env[BedrockSettingsReader.accessKeyIDKey] == nil)
        #expect(env[BedrockSettingsReader.secretAccessKeyKey] == nil)
    }

    @Test
    func bedrock_keys_mode_still_projects_static_credentials() {
        let config = ProviderConfig(
            id: .bedrock,
            apiKey: "AKIATEST",
            secretKey: "secret",
            region: "us-west-2",
            awsAuthMode: "keys")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .bedrock,
            config: config)
        #expect(env[BedrockSettingsReader.authModeKey] == "keys")
        #expect(env[BedrockSettingsReader.accessKeyIDKey] == "AKIATEST")
        #expect(env[BedrockSettingsReader.secretAccessKeyKey] == "secret")
        #expect(env[BedrockSettingsReader.profileKey] == nil)
    }

    @Test
    func ignores_legacy_API_key_override_for_deepseek() {
        let config = ProviderConfig(id: .deepseek, apiKey: "ds-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .deepseek,
            config: config)

        let key = DeepSeekSettingsReader.apiKeyEnvironmentKeys.first
        #expect(key != nil)
        guard let key else { return }

        #expect(env[key] == nil)
        #expect(ProviderTokenResolver.deepseekToken(environment: env) == nil)
    }

    @Test
    func projects_the_legacy_DeepSeek_Platform_token_and_stable_profile_identifier() {
        let config = ProviderConfig(
            id: .deepseek,
            apiKey: "legacy-api-key",
            cookieHeader: "browser-platform-token",
            deepseekProfileID: "/profiles/Profile 2",
            deepseekProfileScope: "account-id")
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [:],
            provider: .deepseek,
            config: config)

        #expect(env[DeepSeekSettingsReader.apiKeyEnvironmentKey] == nil)
        #expect(env[DeepSeekSettingsReader.platformTokenEnvironmentKey] == "browser-platform-token")
        #expect(env[DeepSeekSettingsReader.profileIDEnvironmentKey] == "chrome:Profile 2")
        #expect(env[DeepSeekSettingsReader.profileScopeEnvironmentKey] == "account-id")
    }

    @Test
    func normalization_preserves_a_legacy_DeepSeek_browser_token_and_canonicalizes_the_profile_path() throws {
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .deepseek,
                cookieHeader: "browser-platform-token",
                deepseekProfileID: "/profiles/Profile 2",
                deepseekProfileScope: " account-id "),
        ]).normalized()
        let deepseek = try #require(config.providerConfig(for: .deepseek))

        #expect(deepseek.cookieHeader == "browser-platform-token")
        #expect(deepseek.deepseekProfileID == "chrome:Profile 2")
        #expect(deepseek.deepseekProfileScope == "account-id")
    }

    @Test
    func applies_API_key_override_for_kilo() {
        let config = ProviderConfig(id: .kilo, apiKey: "kilo-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .kilo,
            config: config)

        #expect(env[KiloSettingsReader.apiTokenKey] == "kilo-token")
        #expect(ProviderTokenResolver.kiloToken(environment: env, authFileURL: nil) == "kilo-token")
    }

    @Test
    func applies_API_key_override_for_factory() {
        let config = ProviderConfig(id: .factory, apiKey: "fk-config-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .factory,
            config: config)

        #expect(env[FactorySettingsReader.apiTokenKey] == "fk-config-token")
        #expect(FactorySettingsReader.apiKey(environment: env) == "fk-config-token")
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .factory))
    }

    @Test
    func factory_config_api_key_wins_over_existing_FACTORY_API_KEY() {
        let config = ProviderConfig(id: .factory, apiKey: "fk-config-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [FactorySettingsReader.apiTokenKey: "fk-env-token"],
            provider: .factory,
            config: config)

        #expect(env[FactorySettingsReader.apiTokenKey] == "fk-config-token")
        #expect(FactorySettingsReader.apiKey(environment: env) == "fk-config-token")
    }

    @Test
    func open_router_config_override_wins_over_environment_token() {
        let config = ProviderConfig(id: .openrouter, apiKey: "config-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [OpenRouterSettingsReader.envKey: "env-token"],
            provider: .openrouter,
            config: config)

        #expect(env[OpenRouterSettingsReader.envKey] == "config-token")
        #expect(ProviderTokenResolver.openRouterToken(environment: env) == "config-token")
    }

    @Test
    func deepseek_config_override_leaves_environment_token_alone() {
        let config = ProviderConfig(id: .deepseek, apiKey: "config-token")
        let envKey = DeepSeekSettingsReader.apiKeyEnvironmentKeys[0]
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [envKey: "env-token"],
            provider: .deepseek,
            config: config)

        #expect(env[envKey] == "env-token")
        #expect(ProviderTokenResolver.deepseekToken(environment: env) == "env-token")
    }

    @Test
    func applies_API_key_override_for_codebuff() {
        let config = ProviderConfig(id: .codebuff, apiKey: "cb-config-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .codebuff,
            config: config)

        #expect(env[CodebuffSettingsReader.apiTokenKey] == "cb-config-token")
        #expect(
            ProviderTokenResolver.codebuffToken(environment: env, authFileURL: nil)
                == "cb-config-token")
    }

    @Test
    func applies_API_key_override_for_deepgram() {
        let config = ProviderConfig(id: .deepgram, apiKey: "dg-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .deepgram,
            config: config)

        #expect(env[DeepgramSettingsReader.apiKeyEnvironmentKey] == "dg-token")
        #expect(ProviderTokenResolver.deepgramResolution(
            type: .apiKey,
            environment: env)
            == "dg-token")
    }

    @Test
    func applies_Deepgram_project_ID_override_from_provider_config() {
        let config = ProviderConfig(id: .deepgram, workspaceID: "proj-123")
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [:],
            provider: .deepgram,
            config: config)

        #expect(env[DeepgramSettingsReader.projectIDEnvironmentKey] == "proj-123")
    }

    @Test
    func Deepgram_project_ID_config_overrides_environment() {
        let config = ProviderConfig(id: .deepgram, workspaceID: "config-project")
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [DeepgramSettingsReader.projectIDEnvironmentKey: "env-project"],
            provider: .deepgram,
            config: config)

        #expect(env[DeepgramSettingsReader.projectIDEnvironmentKey] == "config-project")
    }

    @Test
    func codebuff_config_override_leaves_environment_token_alone() {
        let config = ProviderConfig(id: .codebuff, apiKey: "config-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [CodebuffSettingsReader.apiTokenKey: "env-token"],
            provider: .codebuff,
            config: config)

        #expect(env[CodebuffSettingsReader.apiTokenKey] == "env-token")
        #expect(
            ProviderTokenResolver.codebuffToken(environment: env, authFileURL: nil)
                == "env-token")
    }

    @Test
    func leaves_environment_when_API_key_missing() {
        let config = ProviderConfig(id: .zai, apiKey: nil)
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [ZaiSettingsReader.apiTokenKey: "existing"],
            provider: .zai,
            config: config)

        #expect(env[ZaiSettingsReader.apiTokenKey] == "existing")
    }

    @Test
    func applies_API_key_override_for_poe() {
        let config = ProviderConfig(id: .poe, apiKey: "poe-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .poe,
            config: config)

        #expect(env[PoeSettingsReader.apiKeyEnvironmentKey] == "poe-token")
        #expect(ProviderTokenResolver.poeToken(environment: env) == "poe-token")
    }

    @Test
    func poe_supports_API_key_override() {
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .poe) == true)
    }
}
