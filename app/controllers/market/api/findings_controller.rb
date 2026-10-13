# frozen_string_literal: true

module Market
  module Api
    # GET /api/market/findings: worst first, each with its stable key, exact
    # evidence and sources. ?since=<ISO time> answers only what appeared,
    # changed, resolved or was dismissed after it (every state, unless ?state
    # says); pass back the answer's as_of next time to hear each change once.
    class FindingsController < BaseController
      requires_capability "market:read", only: :index
      requires_capability "market:write", only: [:update, :refresh]

      def index
        @as_of = Time.current
        if params[:since].present?
          @since = (Time.iso8601(params[:since].to_s) rescue nil)
          return render(json: {error: "invalid", message: "since should be an ISO 8601 time, like 2026-10-12T09:00:00Z"}, status: :unprocessable_content) unless @since
        end
        @state = params[:state].presence_in(Finding::STATES + ["all"]) || (@since ? "all" : "open")
        scope = Finding.in_state(@state).by_severity
        scope = scope.where(severity: params[:severity]) if params[:severity].in?(Finding::SEVERITIES)
        scope = scope.where(kind: params[:kind]) if params[:kind].present?
        scope = scope.where(channel: params[:channel]) if params[:channel].present?
        scope = scope.where(changed_at: @since..) if @since
        @findings = scope.limit(500).to_a
      end

      def update
        @finding = Finding.find(params[:id])
        state = params.require(:finding)[:state]
        return render(json: {error: "invalid", message: "state should be dismissed or open"}, status: :unprocessable_content) unless state.in?(%w[dismissed open])

        (state == "dismissed") ? @finding.dismiss(by: Current.user) : @finding.reopen
        render partial: "market/api/findings/finding", locals: {finding: @finding}
      end

      def refresh
        @as_of = Time.current
        @state = "open"
        @findings = Finding.refresh.by_severity.to_a
        render :index
      end
    end
  end
end
