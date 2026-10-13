# frozen_string_literal: true

module Market
  # Wins back the links to a page that no longer answers: a 301 from its old
  # address to the page chosen (the CMS's own redirects, Tools › Redirects).
  class LinkRedirectsController < ApplicationController
    requires_capability "market:write", only: :create

    def create
      back = back_or(market_search_path(tab: "links", anchor: "broken"))
      return redirect_to(back, alert: "Adding redirects takes Redirects › write") unless Current.user.can?("redirects:write")

      from = ::Redirect.normalize_path(URI.parse(params[:path].to_s).path.to_s)
      to = params[:to].to_s.strip
      return redirect_to(back, alert: "Choose the page to send it to") unless to.start_with?("/") && from != "/" && from != ::Redirect.normalize_path(to)
      return redirect_to(back, alert: "#{from} is redirected already") if ::Redirect.match(from)

      redirect = ::Redirect.new(source_path: from, destination_url: to, status_code: 301, active: true,
        notes: "From Market: other sites link to #{from}, which no longer answers")
      if redirect.save
        redirect.track_event(:created, source: redirect.source_path)
        redirect_to back, notice: "#{from} now redirects to #{to}: its links count again"
      else
        redirect_to back, alert: redirect.errors.full_messages.to_sentence
      end
    rescue URI::InvalidURIError
      redirect_to back, alert: "That address can't be read"
    end
  end
end
