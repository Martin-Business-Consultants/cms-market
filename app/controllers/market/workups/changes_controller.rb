# frozen_string_literal: true

module Market
  module Workups
    # One of a work-up's changes sent on (Market::Workup::Sending): to
    # Approvals, a draft page, searches tracked, or a task on the plan.
    class ChangesController < Market::ApplicationController
      requires_capability "market:write", only: :create
      before_action :require_content_rights, only: :create

      def create
        result = @workup.send_change!(params[:index], by: Current.user)
        redirect_to back_or(market_work_path(subject: @workup.subject)), notice: notice_for(result)
      rescue Workup::Refused, ActiveRecord::RecordInvalid => error
        redirect_to back_or(market_work_path(subject: @workup.subject)), alert: error.message
      end

      private

      # Sending a page change or a post proposes content: it takes the right to write it.
      def require_content_rights
        @workup = Workup.find(params[:workup_id])
        change = @workup.changes[params[:index].to_i] or raise ActiveRecord::RecordNotFound
        capability = {"update_page" => "pages:write", "new_page" => "pages:write", "new_post" => "entries:write"}[change["kind"]]
        return if capability.nil? || Current.user.can?(capability)

        redirect_to back_or(market_work_path(subject: @workup.subject)), alert: "Your role can't write #{capability.split(":").first}"
      end

      def notice_for(result)
        case result["kind"]
        when "update_page", "new_post" then "Sent to Approvals: a person compares it with what's live and puts it live"
        when "new_page" then "Draft page started"
        when "track_searches" then "Tracking #{result["keywords"].to_a.to_sentence}"
        else "On the plan"
        end
      end
    end
  end
end
