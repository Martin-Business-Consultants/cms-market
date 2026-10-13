# frozen_string_literal: true

module Market
  module Api
    # /api/market/goals: what the marketing is for, measured (Market::Goal).
    class GoalsController < BaseController
      requires_capability "market:read", only: :index
      requires_capability "market:write", only: [:create, :update, :destroy]

      def index
        render json: {goals: Goal.ordered.includes(:keyword).map { Goal.as_api(it) }, metrics: Goal::METRICS.transform_values { it.slice(:label, :unit, :search, :source) }}
      end

      def create
        goal = Goal.new(goal_params.merge(position: Goal.maximum(:position).to_i + 1))
        return refuse(goal.errors.full_messages.to_sentence, status: :unprocessable_content) unless goal.save

        render json: Goal.as_api(goal), status: :created
      end

      def update
        goal = Goal.find(params[:id])
        return refuse(goal.errors.full_messages.to_sentence, status: :unprocessable_content) unless goal.update(goal_params)

        render json: Goal.as_api(goal)
      end

      def destroy
        Goal.find(params[:id]).destroy!
        head :no_content
      end

      private

      def goal_params
        params.require(:goal).permit(:metric, :keyword_id, :target, :due_on, :why, :state).tap do |attributes|
          attributes[:keyword_id] = nil if attributes.key?(:keyword_id) && attributes[:keyword_id].blank?
        end
      end
    end
  end
end
