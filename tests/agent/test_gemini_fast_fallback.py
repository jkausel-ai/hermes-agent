from run_agent import AIAgent


class AvailablePool:
    def has_available(self):
        return True


def make_agent(provider: str, base_url: str):
    agent = object.__new__(AIAgent)
    agent.provider = provider
    agent.base_url = base_url
    agent._credential_pool = AvailablePool()
    return agent


def test_cloudcode_gemini_rate_limit_prefers_fallback_over_pool():
    agent = make_agent("google-gemini-cli", "cloudcode-pa://google")

    assert agent._credential_pool_may_recover_rate_limit() is False


def test_cloudcode_base_url_prefers_fallback_even_with_alias_provider():
    agent = make_agent("custom-provider", "cloudcode-pa://google")

    assert agent._credential_pool_may_recover_rate_limit() is False


def test_non_cloudcode_provider_can_recover_with_available_pool():
    agent = make_agent("openrouter", "https://openrouter.ai/api/v1")

    assert agent._credential_pool_may_recover_rate_limit() is True
