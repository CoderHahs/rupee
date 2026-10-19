# The model providers a household can choose when it turns Rupee on
# (design §4.12). The choice is upstream's instance-wide Setting.llm_provider,
# which LLM_PROVIDER pins when set. OpenAI pointed at OPENAI_URI_BASE is a
# self-hosted, OpenAI-compatible model.
class Fork::AiProviderChoice
  KEYS = %w[openai anthropic].freeze

  Option = Data.define(:key, :name, :host, :configured) do
    def self_hosted? = host.present?
  end

  def options
    keys = locked? ? [ current ] : KEYS
    keys.map { |key| option(key) }
  end

  def configured_options
    options.select(&:configured)
  end

  def current
    (ENV["LLM_PROVIDER"].presence || Setting.llm_provider).to_s.downcase == "anthropic" ? "anthropic" : "openai"
  end

  def locked?
    ENV["LLM_PROVIDER"].present?
  end

  def available?(key)
    configured_options.any? { |option| option.key == key }
  end

  def choose!(key)
    raise ArgumentError, "#{key} is not an available provider" unless available?(key)

    Setting.llm_provider = key unless locked?
  end

  private
    def option(key)
      case key
      when "anthropic"
        Option.new(key:, name: "Anthropic", host: nil, configured: Provider::Anthropic.configured?)
      else
        uri_base = ENV["OPENAI_URI_BASE"].presence || Setting.openai_uri_base
        Option.new(key:, name: "OpenAI", host: uri_base.presence && URI.parse(uri_base).host, configured: Provider::Openai.configured?)
      end
    rescue URI::InvalidURIError
      Option.new(key:, name: "OpenAI", host: uri_base, configured: Provider::Openai.configured?)
    end
end
