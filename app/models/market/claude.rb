# frozen_string_literal: true

require "net/http"

# One structured answer from Claude (the Messages API, with the key and model
# in Settings › Market), in the shape of a JSON schema. Plain Net::HTTP: a
# plugin may use only the gems the core bundles. The transport is injectable
# for tests.
class Market::Claude
  class Error < StandardError; end

  ENDPOINT = URI("https://api.anthropic.com/v1/messages")
  TIMEOUT = 300

  def initialize(settings: Market::Settings.current, transport: nil)
    @settings = settings
    @transport = transport || method(:post)
  end

  # The answer, as a Hash in `schema`'s shape. Raises Error.
  def structured(system:, prompt:, schema:, max_tokens: 16_000)
    raise Error, "No Anthropic API key is set in Settings › Market" if @settings.ai_key.blank?

    body = {model: @settings.ai_model, max_tokens: max_tokens, output_config: {effort: "medium", format: {type: "json_schema", schema: schema}},
            fallbacks: "default", system: system, messages: [{role: "user", content: prompt}]}
    status, raw = @transport.call(body)
    answer = JSON.parse(raw.to_s) rescue {}
    raise Error, failure(status, answer) unless status.to_i.between?(200, 299)

    case answer["stop_reason"]
    when "refusal" then raise Error, "Claude declined to answer"
    when "max_tokens" then raise Error, "The answer ran too long; try again"
    end
    JSON.parse(Array(answer["content"]).select { it["type"] == "text" }.map { it["text"] }.join)
  rescue JSON::ParserError
    raise Error, "Claude's answer wasn't in the expected shape; try again"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Error, "Couldn't reach Anthropic: #{error.class.name.demodulize}"
  end

  private

  def post(body)
    http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = TIMEOUT
    request = Net::HTTP::Post.new(ENDPOINT.request_uri)
    request["content-type"] = "application/json"
    request["x-api-key"] = @settings.ai_key
    request["anthropic-version"] = "2023-06-01"
    request["anthropic-beta"] = "server-side-fallback-2026-07-01"
    request.body = JSON.generate(body)
    response = http.request(request)
    [response.code.to_i, response.body]
  end

  def failure(status, answer)
    detail = answer.dig("error", "message").presence
    case status.to_i
    when 401 then "Anthropic didn't accept the API key in Settings › Market"
    when 429 then "Anthropic is rate limiting this key; try again shortly"
    else "Anthropic answered #{status}#{": #{detail}" if detail}"
    end
  end
end
