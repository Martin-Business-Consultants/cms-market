# frozen_string_literal: true

json.extract! finding, :id, :key, :kind, :severity, :channel, :title, :detail, :evidence, :sources, :state,
  :first_seen_at, :last_seen_at, :changed_at, :resolved_at, :dismissed_at, :dismissed_by_name
