# frozen_string_literal: true

module Market
  module Api
    # POST /api/market/workups/:id/changes/:index: sends one change on, as a
    # person's button does (Market::Workup::Sending). Page changes and posts
    # are held in Approvals, never put live.
    class WorkupChangesController < BaseController
      requires_capability "market:write", only: :create

      def create
        workup = Workup.find(params[:workup_id])
        change = workup.changes[params[:index].to_i] or raise ActiveRecord::RecordNotFound
        capability = {"update_page" => "pages:write", "new_page" => "pages:write", "new_post" => "entries:write"}[change["kind"]]
        return refuse("Your role can't write #{capability.split(":").first}", status: :forbidden) if capability && !Current.user.can?(capability)

        render json: {sent: workup.send_change!(params[:index], by: Current.user), workup_id: workup.id, index: params[:index].to_i}, status: :created
      rescue Workup::Refused, ActiveRecord::RecordInvalid => error
        refuse(error.message)
      end
    end
  end
end
