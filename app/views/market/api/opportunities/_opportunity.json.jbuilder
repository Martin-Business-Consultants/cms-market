# frozen_string_literal: true

json.extract! opportunity, :id, :title, :channel, :detail, :evidence, :impact, :effort, :horizon, :state, :plan_id, :decided_by_name, :decided_at
json.page opportunity.page ? {path: opportunity.page.path, title: opportunity.page.title, status: opportunity.page.status} : nil
