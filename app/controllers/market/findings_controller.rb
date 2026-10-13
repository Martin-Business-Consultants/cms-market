# frozen_string_literal: true

module Market
  # What the data says, worst first, each with its evidence: dismiss one, or
  # work them out again now.
  class FindingsController < ApplicationController
    requires_capability "market:read", only: :index
    requires_capability "market:write", only: [:update, :refresh]

    def index
      @state = params[:state].presence_in(Finding::STATES + ["all"]) || "open"
      @findings = Finding.in_state(@state).by_severity.to_a
      @counts = {"open" => Finding.open.count, "dismissed" => Finding.in_state("dismissed").count, "resolved" => Finding.in_state("resolved").count}
    end

    def update
      finding = Finding.find(params[:id])
      params.require(:finding)[:state] == "dismissed" ? finding.dismiss(by: Current.user) : finding.reopen
      redirect_back_or_to market_findings_path, notice: "#{finding.state == "dismissed" ? "Dismissed" : "Open again"}: #{finding.title}"
    end

    def refresh
      found = Finding.refresh
      redirect_to market_findings_path, notice: "#{found.size} open #{"finding".pluralize(found.size)}"
    end
  end
end
