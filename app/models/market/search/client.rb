# frozen_string_literal: true

require "net/http"

module Market
  module Search
    # DataForSEO's API (v3), as robust as a paid service needs to be:
    #
    # - Every call is checked against the month's budget first (Market::Settings#remaining_budget, from
    #   the ledger) with a ceiling for what it might cost, and refused if it could go over.
    # - Every call is written to the ledger (SearchRequest) whatever happens: its status, what it
    #   cost, how many tries and how long it took.
    # - What may pass (the network, timeouts, 429 and 5xx, DataForSEO's rate limits and
    #   "try again") is tried up to MAX_ATTEMPTS times, waiting longer each time. What won't (a
    #   wrong login, no funds, an invalid field) fails at once, as its own error class, so a pull
    #   knows to stop or to carry on.
    # - A response is only trusted when both the response and its task say 20000.
    #
    # The transport is injectable: tests answer without the network.
    class Client
      BASE = URI("https://api.dataforseo.com/v3/")
      # DataForSEO's sandbox: the same answers in shape, with made-up data, free (Settings › Market › Test mode).
      SANDBOX = URI("https://sandbox.dataforseo.com/v3/")
      MAX_ATTEMPTS = 3
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 90
      RETRY_CODES = [40103, 40202, 40209, 50000, 50303, 50401, 50402].freeze

      class Error < StandardError
        attr_reader :code

        def initialize(message, code: nil)
          super(message)
          @code = code
        end
      end
      class AuthError < Error; end       # the login or password is wrong: stop
      class FundsError < Error; end      # no balance, or DataForSEO's own cost limit: stop
      class BudgetError < Error; end     # this month's budget here: stop
      class InvalidError < Error; end    # this request is wrong (a location, a field): skip it
      class UnavailableError < Error; end # not in the plan (backlinks without the subscription): skip it
      class Transient < Error; end       # tried MAX_ATTEMPTS times and still failing
      class NotReady < Error; end        # a queued task that isn't done yet: ask again later

      STOPPING = [AuthError, FundsError, BudgetError].freeze

      def self.stopping?(error) = STOPPING.any? { error.is_a?(it) }

      def initialize(setting: Market::Settings.current, pull: nil, transport: nil, wait: ->(seconds) { sleep(seconds) })
        @setting = setting
        @pull = pull
        @transport = transport || method(:http)
        @wait = wait
      end

      # One live task: the task's `result` array. `ceiling` is the most it might cost, in dollars.
      def post(endpoint, task, target:, ceiling:, created: false)
        raise AuthError.new("DataForSEO isn't connected: add the login and password in Settings › Market.") unless @setting.search_connected?
        if ceiling.to_d > @setting.remaining_budget
          raise BudgetError.new("This month's search budget ($#{format("%.2f", @setting.budget)}) has $#{format("%.2f", @setting.remaining_budget)} left: " \
                                "not enough for #{endpoint.split("/")[-2] || endpoint} on #{target}. Raise it in Settings › Market.")
        end

        call(:post, endpoint, [task], target: target, created: created)
      end

      # A queued task set (task_post, Standard): its id, to fetch with #task_result once DataForSEO has done it.
      def post_task(endpoint, task, target:, ceiling:)
        post(endpoint, task, target: target, ceiling: ceiling, created: true)
        @last_task&.dig("id") or raise InvalidError.new("DataForSEO set no task for #{endpoint}")
      end

      # Up to 100 queued tasks set in one request (Standard, about a third of Live's price): their ids,
      # in order, nil for one DataForSEO refused. `ceiling` is the most they might cost together.
      def post_tasks(endpoint, tasks, target:, ceiling:)
        raise AuthError.new("DataForSEO isn't connected: add the login and password in Settings › Market.") unless @setting.search_connected?
        raise BudgetError.new("This month's search budget has $#{format("%.2f", @setting.remaining_budget)} left: not enough to queue #{tasks.size} #{endpoint.split("/")[-2]} checks.") if ceiling.to_d > @setting.remaining_budget

        tasks.each_slice(100).flat_map do |batch|
          json = nil
          error = nil
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            json = parse(*@transport.call(:post, (@setting.sandbox? ? SANDBOX : BASE) + endpoint, batch))
            check!(json["status_code"], json["status_message"])
            Array(json["tasks"]).map { it["id"] if it["status_code"].to_i == 20100 }
          rescue Error => failure
            error = failure
            raise
          ensure
            record(endpoint, target, json, error, 1, started)
          end
        end
      end

      # A queued task's result (task_get, free): its `result` array; NotReady while it's still being done.
      def task_result(endpoint) = get(endpoint)

      # A free GET (a list of models or locations): the task's `result` array.
      def get(endpoint)
        raise AuthError.new("DataForSEO isn't connected: add the login and password in Settings › Market.") unless @setting.search_connected?

        call(:get, endpoint, nil, target: nil)
      end

      # The account's balance in dollars (appendix/user_data, which costs nothing).
      def balance
        raise AuthError.new("Add the DataForSEO login and password first.") unless @setting.search_connected?

        call(:get, "appendix/user_data", nil, target: nil).first&.dig("money", "balance").to_d
      end

      private

      def call(method, endpoint, body, target:, created: false)
        attempts = 0
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        json = nil
        error = nil
        begin
          attempts += 1
          json = parse(*@transport.call(method, (@setting.sandbox? ? SANDBOX : BASE) + endpoint, body))
          task = Array(json["tasks"]).first || {}
          @last_task = task
          check!(json["status_code"], json["status_message"])
          check!(task["status_code"], task["status_message"]) unless created && task["status_code"].to_i == 20100
          Array(task["result"])
        rescue Transient => failure
          if attempts < MAX_ATTEMPTS
            @wait.call(2**attempts)
            retry
          end
          error = failure
          raise
        rescue Error => failure
          error = failure
          raise
        end
      ensure
        record(endpoint, target, json, error, attempts, started)
      end

      def parse(status, body)
        raise Transient.new("DataForSEO answered HTTP #{status}", code: status) if status.to_i == 429 || status.to_i >= 500
        raise AuthError.new("DataForSEO refused the login (HTTP 401): check it in Settings › Market.", code: 40100) if status.to_i == 401

        JSON.parse(body.to_s)
      rescue JSON::ParserError
        raise Transient.new("DataForSEO answered something that isn't JSON (HTTP #{status})", code: status)
      end

      def check!(code, message)
        code = code.to_i
        return if code == 20000

        text = "DataForSEO #{code}: #{message}"
        raise case
        when code.in?([40601, 40602]) then NotReady.new(text, code:)
        when code == 40100 then AuthError.new("#{text}. Check the login and password in Settings › Market.", code:)
        when code.in?([40200, 40210, 40203]) then FundsError.new("#{text}. Top up the DataForSEO account, or raise its limit.", code:)
        when RETRY_CODES.include?(code) || code >= 50000 then Transient.new(text, code:)
        when code.between?(40200, 40299) || code.between?(40400, 40499) then UnavailableError.new(text, code:)
        else InvalidError.new(text, code:)
        end
      end

      def record(endpoint, target, json, error, attempts, started)
        task = Array(json&.dig("tasks")).first || {}
        Market::SearchRequest.create!(pull: @pull, endpoint: endpoint, target: target, attempts: attempts,
          status_code: task["status_code"] || json&.dig("status_code") || error&.code,
          status_message: (task["status_message"] || json&.dig("status_message")).to_s.truncate(250).presence,
          cost: json&.dig("cost").to_d, error: error&.message&.truncate(500),
          duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round, created_at: Time.current)
      rescue => failure
        Rails.logger.error("[market] couldn't record a DataForSEO request: #{failure.class}: #{failure.message}")
      end

      # [status, body] over HTTPS with Basic auth; the network's own failures may pass.
      def http(method, uri, body)
        request = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
        request.basic_auth(@setting.dataforseo_login, @setting.dataforseo_password)
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = JSON.generate(body) if body
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, ssl_timeout: OPEN_TIMEOUT) do |http|
          response = http.request(request)
          [response.code.to_i, response.body]
        end
      rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError => failure
        raise Transient.new("Couldn't reach DataForSEO: #{failure.class.name.demodulize}: #{failure.message}".truncate(250))
      end
    end
  end
end
