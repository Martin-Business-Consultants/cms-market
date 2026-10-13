# frozen_string_literal: true

module Market
  # Goals, set and changed on the Plan (Market::Goal): a metric, its target, and by when.
  class GoalsController < ApplicationController
    requires_capability "market:write", only: [:create, :update, :destroy]

    def create
      goal = Goal.new(goal_params.merge(position: Goal.maximum(:position).to_i + 1))
      if goal.save
        redirect_to market_plan_path(anchor: "goals"), notice: "Goal set: #{goal.title}#{", now #{goal.describe(goal.current)}" if goal.current}"
      else
        redirect_to market_plan_path(anchor: "goals"), alert: goal.errors.full_messages.to_sentence
      end
    end

    def update
      goal = Goal.find(params[:id])
      goal.update!(goal_params)
      redirect_to market_plan_path(anchor: "goals"), notice: "Goal saved"
    end

    def destroy
      Goal.find(params[:id]).destroy!
      redirect_to market_plan_path(anchor: "goals"), notice: "Goal removed"
    end

    private

    def goal_params
      params.require(:goal).permit(:metric, :keyword_id, :target, :due_on, :why, :state).tap do |attributes|
        attributes[:keyword_id] = nil if attributes[:keyword_id].blank?
      end
    end
  end
end
