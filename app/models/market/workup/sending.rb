# frozen_string_literal: true

# Sending one of a work-up's changes on. A change to a page, and a new post,
# go to Approvals (cms-approvals, through Cms::Plugins.api_write_hold) for a
# person to compare with what's live and put live; a new page is started as a
# draft for a person to build; searches are tracked; a task goes on the plan.
# What each became is kept in `sent`, so it's sent once.
module Market::Workup::Sending
  extend ActiveSupport::Concern

  # What couldn't be sent, said for a person.
  class Refused < StandardError; end

  POST_COLLECTIONS = %w[posts blog news articles insights].freeze

  class_methods do
    def approvals? = Cms::Plugins.api_write_hold.present?

    # The collection posts are written into: the first named like one.
    def posts_collection = ::Collection.where(slug: POST_COLLECTIONS).min_by { POST_COLLECTIONS.index(it.slug) }
  end

  # Answers what it became: {"kind", "approval_id", "path", "page_path", "opportunity_id", "keywords", "at"}.
  def send_change!(index, by:)
    change = changes[index.to_i] or raise ActiveRecord::RecordNotFound
    return sent_for(index) if sent_for(index)

    result = public_send(:"send_#{change["kind"]}", change, by: by).merge("kind" => change["kind"], "at" => Time.current.iso8601)
    update!(sent: sent.to_h.merge(index.to_s => result))
    result
  end

  def send_update_page(change, by:)
    page = ::Page.find_by(path: change["page_path"].to_s.delete_prefix("/").presence || "home") or raise Refused, "That page isn't on the site any more"
    seo = page.seo.to_h.merge(seo_of(change))
    page.assign_attributes(title: change["page_title"].presence || page.title, seo: seo, blocks: edited_blocks(page, change["text_edits"]))
    hold(:update, page, {"title" => page.title, "seo" => page.seo, "blocks" => page.blocks}.select { |name, _| page.will_save_change_to_attribute?(name) }, prefix: "pages")
      .merge("page_path" => page.path)
  end

  def send_new_post(change, by:)
    collection = self.class.posts_collection or raise Refused, "There's no posts collection to write it into (one named #{POST_COLLECTIONS.first(3).join(", ")})"
    title = change["page_title"].presence || change["title"]
    entry = collection.entries.new(title: title.truncate(150), slug: free_slug(collection.entries, change["slug"].presence || title),
      body_markdown: change["body_markdown"], status: "draft", locale: default_locale, frontmatter: {}, blocks: [],
      seo: seo_of(change))
    hold(:create, entry, entry.attributes.slice("title", "slug", "body_markdown", "seo", "locale", "frontmatter", "blocks", "collection_id"), prefix: "entries")
  end

  def send_new_page(change, by:)
    title = change["page_title"].presence || change["title"]
    page = ::Page.create!(title: title.truncate(150), slug: free_slug(::Page.where(parent_id: nil), change["slug"].presence || title), status: "draft",
      locale: default_locale, blocks: [], frontmatter: {}, seo: seo_of(change))
    page.track_creation if page.respond_to?(:track_creation)
    {"path" => Rails.application.routes.url_helpers.edit_page_path(page.path), "page_path" => page.path}
  end

  def send_track_searches(change, by:)
    added, = Market::Keyword.track(Array(change["searches"]).join("\n"), source: "plan")
    raise Refused, "Those searches are tracked already" if added.empty?

    {"keywords" => added.map(&:keyword)}
  end

  def send_task(change, by:)
    opportunity = Market::Opportunity.find_by(finding_key: "workup:#{id}:#{change["title"].parameterize.first(60)}") ||
      Market::Opportunity.create!(finding_key: "workup:#{id}:#{change["title"].parameterize.first(60)}", title: change["title"].truncate(200),
        detail: change["why"].presence, channel: change["channel"].presence_in(Market::Opportunity::CHANNELS.keys) || "local",
        impact: "medium", effort: "low", horizon: "now")
    {"opportunity_id" => opportunity.id}
  end

  private

  # Held in Approvals: {"approval_id", "path"}. Refused without it, as nothing here may put a change live.
  def hold(action, record, attributes, prefix:)
    hold = Cms::Plugins.api_write_hold or raise Refused, "Changes go to Approvals for a person to put live: turn the Approvals plugin on in Settings › Plugins"
    raise Refused, record.errors.full_messages.to_sentence if record.invalid?

    held = hold.call(Cms::Plugins::HeldWrite.new(action: action.to_s, record: record, attributes: attributes.stringify_keys, prefix: prefix))
    raise Refused, "It changes nothing on the page as it is now" if held.nil?

    approval = held.with_indifferent_access[:approval] || {}
    {"approval_id" => approval[:id], "path" => approval[:path]}.compact
  end

  # The page's blocks with the edits' wording put in, by field id ("blocks.2.data.heading").
  def edited_blocks(page, edits)
    blocks = page.blocks.deep_dup
    known = Market::Workup::Brief.text_fields(page)
    Array(edits).each do |edit|
      next unless known.key?(edit["field"])

      *path, last = edit["field"].split(".").drop(1).map { it.match?(/\A\d+\z/) ? it.to_i : it }
      parent = path.empty? ? blocks : blocks.dig(*path)
      parent[last] = edit["text"] if parent.is_a?(Hash) || parent.is_a?(Array)
    end
    blocks
  end

  def free_slug(scope, text)
    base = text.to_s.parameterize.first(80).presence || "untitled"
    taken = scope.where("slug = ? OR slug LIKE ?", base, "#{base}-%").pluck(:slug)
    taken.include?(base) ? (2..).lazy.map { "#{base}-#{it}" }.find { !taken.include?(it) } : base
  end

  def seo_of(change) = change.slice("meta_title", "meta_description", "focus_keyword", "json_ld").compact_blank

  def default_locale = Setting.get("general")["default_locale"].presence || "en"
end
