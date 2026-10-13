# frozen_string_literal: true

module Market
  module Api
    # /api/market/workups: AI work-ups, newest first (?subject= for one
    # thing's); POST {subject} drafts one (a minute or so), GET /:id reads it.
    # Subjects: keyword:<id>, map:<keyword id>, visibility:own,
    # visibility:<competitor id>, opportunity:<id>.
    class WorkupsController < BaseController
      requires_capability "market:read", only: [:index, :show]
      requires_capability "market:write", only: :create

      def index
        scope = Workup.latest_first.limit(50)
        scope = scope.where(subject: params[:subject]) if params[:subject].present?
        @workups = scope.to_a
      end

      def show
        @workup = Workup.find(params[:id])
      end

      def create
        return refuse(Plan.ai_unavailable_reason) unless Plan.ai_available?

        subject = params.require(:subject)
        Workup::Brief.new(subject)
        return refuse("A work-up of #{subject} is already running") if Workup.latest(subject)&.working?

        @workup = Workup.start(subject, user: Current.user)
        render :show, status: :accepted
      rescue ActiveRecord::RecordNotFound
        refuse("No such subject: #{params[:subject]}", status: :unprocessable_content)
      end
    end
  end
end
